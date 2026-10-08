#include "flutter_window.h"

#include <optional>
#include <windowsx.h>
#include <commctrl.h>

#include "flutter/generated_plugin_registrant.h"
#include <desktop_multi_window/desktop_multi_window_plugin.h>

#include <appmodel.h>
#include <chrono>
#include <cmath>
#include <memory>
#include <shobjidl.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Services.Store.h>
#include <winrt/Windows.Security.Credentials.h>

#include "utils.h"

#pragma comment(lib, "comctl32.lib")

namespace {

int GetResizeBorderThickness(HWND hwnd) {
  int border_thickness = ::GetSystemMetrics(SM_CYFRAME) + ::GetSystemMetrics(SM_CXPADDEDBORDER);
  if (border_thickness <= 0) {
    border_thickness = 8;
  }
  HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (user32) {
    using GetDpiForWindowFunc = UINT(WINAPI*)(HWND);
    using GetSystemMetricsForDpiFunc = int(WINAPI*)(int, UINT);
    auto get_dpi_for_window = reinterpret_cast<GetDpiForWindowFunc>(
        ::GetProcAddress(user32, "GetDpiForWindow"));
    auto get_system_metrics_for_dpi = reinterpret_cast<GetSystemMetricsForDpiFunc>(
        ::GetProcAddress(user32, "GetSystemMetricsForDpi"));
    if (get_dpi_for_window && get_system_metrics_for_dpi) {
      UINT dpi = get_dpi_for_window(hwnd);
      int frame = get_system_metrics_for_dpi(SM_CYFRAME, dpi);
      int padding = get_system_metrics_for_dpi(SM_CXPADDEDBORDER, dpi);
      if (frame + padding > 0) {
        border_thickness = frame + padding;
      }
    }
  }
  return border_thickness;
}

LRESULT CALLBACK ChildWindowSubclassProc(
    HWND hWnd, UINT uMsg, WPARAM wParam, LPARAM lParam,
    UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
  if (uMsg == WM_NCHITTEST) {
    HWND parent = ::GetAncestor(hWnd, GA_PARENT);
    if (parent && !::IsZoomed(parent)) {
      LONG_PTR const style = ::GetWindowLongPtr(parent, GWL_STYLE);
      if (style & WS_THICKFRAME) {
        POINT pt = {GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
        POINT pt_client = pt;
        if (::ScreenToClient(hWnd, &pt_client)) {
          int const border_thickness = GetResizeBorderThickness(parent);
          if (pt_client.y >= -border_thickness && pt_client.y < border_thickness) {
            return HTTRANSPARENT;
          }
        }
      }
    }
  }
  return DefSubclassProc(hWnd, uMsg, wParam, lParam);
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);
  });
  HWND child_hwnd = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(child_hwnd);
  if (child_hwnd) {
    ::SetWindowSubclass(child_hwnd, ChildWindowSubclassProc, 1, 0);
  }

  // Set unique window property to identify this Vynody instance
  ::SetPropW(GetHandle(), L"VynodyInstanceProp", (HANDLE)1);

  // Initialize communication channel
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "vynody/single_instance",
      &flutter::StandardMethodCodec::GetInstance());

  HWND hwnd = GetHandle();
  channel_->SetMethodCallHandler(
      [hwnd](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "registerShortcut") {
          extern void RegisterAppUserModelIDAndShortcut();
          RegisterAppUserModelIDAndShortcut();
          result->Success(flutter::EncodableValue(true));
        } else if (call.method_name() == "getStoreLicense") {
          auto result_ptr = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
          try {
            UINT32 length = 0;
            LONG rc = GetCurrentPackageFullName(&length, NULL);
            if (rc == APPMODEL_ERROR_NO_PACKAGE) {
              // Not running inside MSIX/MS Store package
              flutter::EncodableMap res;
              res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(false);
              result_ptr->Success(flutter::EncodableValue(res));
              return;
            }

            winrt::Windows::Services::Store::StoreContext context =
                winrt::Windows::Services::Store::StoreContext::GetDefault();

            // Associate current HWND if IInitializeWithWindow is supported
            auto initWindow = context.try_as<IInitializeWithWindow>();
            if (initWindow && hwnd != nullptr) {
              initWindow->Initialize(hwnd);
            }

            context.GetAppLicenseAsync().Completed(
                [result_ptr](winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Services::Store::StoreAppLicense> const& asyncOp,
                             winrt::Windows::Foundation::AsyncStatus const status) {
                  try {
                    if (status == winrt::Windows::Foundation::AsyncStatus::Completed) {
                      auto license = asyncOp.GetResults();
                      bool isAppActive = license.IsActive();
                      bool isProPurchased = false;
                      bool isProTrial = false;
                      int remainingDays = 0;
                      int64_t remainingSeconds = 0;

                      // Check Add-on licenses (e.g. 9NS00LQ3KGZN / pro_lifetime)
                      auto addOnLicenses = license.AddOnLicenses();
                      for (auto const& pair : addOnLicenses) {
                        auto const& addOn = pair.Value();
                        if (addOn.IsActive()) {
                          isProPurchased = true;
                        }
                      }

                      // Fallback: If base app itself is configured with a store trial
                      if (!isProPurchased && license.IsTrial()) {
                        isProTrial = true;
                        auto timeRemaining = license.TrialTimeRemaining();
                        int64_t sec = std::chrono::duration_cast<std::chrono::seconds>(timeRemaining).count();
                        if (sec > remainingSeconds) {
                          remainingSeconds = sec;
                          remainingDays = static_cast<int>(std::ceil(static_cast<double>(sec) / 86400.0));
                        }
                      }

                      flutter::EncodableMap res;
                      res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(true);
                      res[flutter::EncodableValue("isActive")] = flutter::EncodableValue(isAppActive);
                      res[flutter::EncodableValue("isProPurchased")] = flutter::EncodableValue(isProPurchased);
                      res[flutter::EncodableValue("isTrial")] = flutter::EncodableValue(isProTrial);
                      res[flutter::EncodableValue("remainingDays")] = flutter::EncodableValue(remainingDays);
                      res[flutter::EncodableValue("remainingSeconds")] = flutter::EncodableValue(remainingSeconds);

                      result_ptr->Success(flutter::EncodableValue(res));
                    } else {
                      flutter::EncodableMap res;
                      res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(true);
                      res[flutter::EncodableValue("error")] = flutter::EncodableValue("AsyncOperation not completed");
                      result_ptr->Success(flutter::EncodableValue(res));
                    }
                  } catch (const std::exception& ex) {
                    result_ptr->Error("STORE_EXCEPTION", ex.what());
                  } catch (...) {
                    result_ptr->Error("STORE_EXCEPTION", "Unknown winrt exception");
                  }
                });
          } catch (const std::exception& ex) {
            flutter::EncodableMap res;
            res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(false);
            res[flutter::EncodableValue("error")] = flutter::EncodableValue(ex.what());
            result_ptr->Success(flutter::EncodableValue(res));
          } catch (...) {
            flutter::EncodableMap res;
            res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(false);
            result_ptr->Success(flutter::EncodableValue(res));
          }
        } else if (call.method_name() == "purchaseStoreProduct") {
          auto result_ptr = std::shared_ptr<flutter::MethodResult<flutter::EncodableValue>>(std::move(result));
          try {
            UINT32 length = 0;
            LONG rc = GetCurrentPackageFullName(&length, NULL);
            if (rc == APPMODEL_ERROR_NO_PACKAGE) {
              flutter::EncodableMap res;
              res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(false);
              res[flutter::EncodableValue("success")] = flutter::EncodableValue(false);
              result_ptr->Success(flutter::EncodableValue(res));
              return;
            }

            std::string store_id_str = "9NS00LQ3KGZN";
            if (auto args = std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = args->find(flutter::EncodableValue("storeId"));
              if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
                store_id_str = std::get<std::string>(it->second);
              }
            }

            winrt::Windows::Services::Store::StoreContext context =
                winrt::Windows::Services::Store::StoreContext::GetDefault();

            auto initWindow = context.try_as<IInitializeWithWindow>();
            if (initWindow && hwnd != nullptr) {
              initWindow->Initialize(hwnd);
            }

            winrt::hstring storeId = winrt::to_hstring(store_id_str);
            context.RequestPurchaseAsync(storeId).Completed(
                [result_ptr](winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Services::Store::StorePurchaseResult> const& asyncOp,
                             winrt::Windows::Foundation::AsyncStatus const status) {
                  try {
                    if (status == winrt::Windows::Foundation::AsyncStatus::Completed) {
                      auto purchaseResult = asyncOp.GetResults();
                      auto purchaseStatus = purchaseResult.Status();
                      bool success = (purchaseStatus == winrt::Windows::Services::Store::StorePurchaseStatus::Succeeded ||
                                      purchaseStatus == winrt::Windows::Services::Store::StorePurchaseStatus::AlreadyPurchased);
                      flutter::EncodableMap res;
                      res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(true);
                      res[flutter::EncodableValue("success")] = flutter::EncodableValue(success);
                      res[flutter::EncodableValue("status")] = flutter::EncodableValue(static_cast<int>(purchaseStatus));
                      result_ptr->Success(flutter::EncodableValue(res));
                    } else {
                      flutter::EncodableMap res;
                      res[flutter::EncodableValue("isPackaged")] = flutter::EncodableValue(true);
                      res[flutter::EncodableValue("success")] = flutter::EncodableValue(false);
                      res[flutter::EncodableValue("status")] = flutter::EncodableValue(-1);
                      result_ptr->Success(flutter::EncodableValue(res));
                    }
                  } catch (const std::exception& ex) {
                    result_ptr->Error("PURCHASE_EXCEPTION", ex.what());
                  } catch (...) {
                    result_ptr->Error("PURCHASE_EXCEPTION", "Unknown winrt exception during purchase");
                  }
                });
          } catch (const std::exception& ex) {
            result_ptr->Error("PURCHASE_EXCEPTION", ex.what());
          } catch (...) {
            result_ptr->Error("PURCHASE_EXCEPTION", "Unknown winrt exception");
          }
        } else if (call.method_name() == "getSecureVaultString") {
          try {
            std::string key_str;
            if (auto args = std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = args->find(flutter::EncodableValue("key"));
              if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
                key_str = std::get<std::string>(it->second);
              }
            }
            if (key_str.empty()) {
              result->Success(flutter::EncodableValue());
              return;
            }
            winrt::hstring key_w = winrt::to_hstring(key_str);
            winrt::Windows::Security::Credentials::PasswordVault vault;
            auto cred = vault.Retrieve(L"VynodyApp", key_w);
            cred.RetrievePassword();
            std::string pass_str = winrt::to_string(cred.Password());
            result->Success(flutter::EncodableValue(pass_str));
          } catch (...) {
            result->Success(flutter::EncodableValue());
          }
        } else if (call.method_name() == "setSecureVaultString") {
          try {
            std::string key_str;
            std::string val_str;
            if (auto args = std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = args->find(flutter::EncodableValue("key"));
              if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
                key_str = std::get<std::string>(it->second);
              }
              auto it_val = args->find(flutter::EncodableValue("value"));
              if (it_val != args->end() && std::holds_alternative<std::string>(it_val->second)) {
                val_str = std::get<std::string>(it_val->second);
              }
            }
            if (key_str.empty()) {
              result->Success(flutter::EncodableValue(false));
              return;
            }
            winrt::hstring key_w = winrt::to_hstring(key_str);
            winrt::hstring val_w = winrt::to_hstring(val_str);
            winrt::Windows::Security::Credentials::PasswordVault vault;
            try {
              auto existing = vault.Retrieve(L"VynodyApp", key_w);
              vault.Remove(existing);
            } catch (...) {}
            if (!val_str.empty()) {
              winrt::Windows::Security::Credentials::PasswordCredential cred(
                  L"VynodyApp", key_w, val_w);
              vault.Add(cred);
            }
            result->Success(flutter::EncodableValue(true));
          } catch (const std::exception& ex) {
            result->Error("VAULT_EXCEPTION", ex.what());
          } catch (...) {
            result->Error("VAULT_EXCEPTION", "Unknown error writing to PasswordVault");
          }
        } else if (call.method_name() == "deleteSecureVaultString") {
          try {
            std::string key_str;
            if (auto args = std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = args->find(flutter::EncodableValue("key"));
              if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
                key_str = std::get<std::string>(it->second);
              }
            }
            if (!key_str.empty()) {
              winrt::hstring key_w = winrt::to_hstring(key_str);
              winrt::Windows::Security::Credentials::PasswordVault vault;
              try {
                auto existing = vault.Retrieve(L"VynodyApp", key_w);
                vault.Remove(existing);
              } catch (...) {}
            }
            result->Success(flutter::EncodableValue(true));
          } catch (...) {
            result->Success(flutter::EncodableValue(false));
          }
        } else if (call.method_name() == "getSecureVaultTrialTime") {
          try {
            winrt::Windows::Security::Credentials::PasswordVault vault;
            auto cred = vault.Retrieve(L"VynodyApp", L"TrialFirstLaunchEpochMs");
            cred.RetrievePassword();
            std::wstring pass = cred.Password().c_str();
            int64_t epoch_ms = _wtoi64(pass.c_str());
            result->Success(flutter::EncodableValue(epoch_ms));
          } catch (...) {
            result->Success(flutter::EncodableValue());
          }
        } else if (call.method_name() == "setSecureVaultTrialTime") {
          try {
            int64_t epoch_ms = 0;
            if (auto args = std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = args->find(flutter::EncodableValue("epochMs"));
              if (it != args->end()) {
                if (std::holds_alternative<int64_t>(it->second)) {
                  epoch_ms = std::get<int64_t>(it->second);
                } else if (std::holds_alternative<int32_t>(it->second)) {
                  epoch_ms = std::get<int32_t>(it->second);
                }
              }
            }
            winrt::Windows::Security::Credentials::PasswordVault vault;
            try {
              auto existing = vault.Retrieve(L"VynodyApp", L"TrialFirstLaunchEpochMs");
              vault.Remove(existing);
            } catch (...) {}
            if (epoch_ms > 0) {
              std::wstring pass = std::to_wstring(epoch_ms);
              winrt::Windows::Security::Credentials::PasswordCredential cred(
                  L"VynodyApp", L"TrialFirstLaunchEpochMs", winrt::hstring(pass));
              vault.Add(cred);
            }
            result->Success(flutter::EncodableValue(true));
          } catch (const std::exception& ex) {
            result->Error("VAULT_EXCEPTION", ex.what());
          } catch (...) {
            result->Error("VAULT_EXCEPTION", "Unknown error writing to PasswordVault");
          }
        } else if (call.method_name() == "getSecureVaultTrialResetV2132") {
          try {
            winrt::Windows::Security::Credentials::PasswordVault vault;
            auto cred = vault.Retrieve(L"VynodyApp", L"TrialResetV2132Done");
            cred.RetrievePassword();
            std::wstring pass = cred.Password().c_str();
            result->Success(flutter::EncodableValue(pass == L"1" || pass == L"true"));
          } catch (...) {
            result->Success(flutter::EncodableValue(false));
          }
        } else if (call.method_name() == "setSecureVaultTrialResetV2132") {
          try {
            bool done = false;
            if (auto args = std::get_if<flutter::EncodableMap>(call.arguments())) {
              auto it = args->find(flutter::EncodableValue("done"));
              if (it != args->end()) {
                if (std::holds_alternative<bool>(it->second)) {
                  done = std::get<bool>(it->second);
                }
              }
            }
            winrt::Windows::Security::Credentials::PasswordVault vault;
            try {
              auto existing = vault.Retrieve(L"VynodyApp", L"TrialResetV2132Done");
              vault.Remove(existing);
            } catch (...) {}
            if (done) {
              winrt::Windows::Security::Credentials::PasswordCredential cred(
                  L"VynodyApp", L"TrialResetV2132Done", L"1");
              vault.Add(cred);
            }
            result->Success(flutter::EncodableValue(true));
          } catch (const std::exception& ex) {
            result->Error("VAULT_EXCEPTION", ex.what());
          } catch (...) {
            result->Error("VAULT_EXCEPTION", "Unknown error writing to PasswordVault");
          }
        } else {
          result->NotImplemented();
        }
      });

  // Note: Window display is managed by Dart via window_manager (waitUntilReadyToShow)
  // to avoid premature display with native titlebar on Windows 10.
  // flutter_controller_->engine()->SetNextFrameCallback([&]() {
  //   this->Show();
  // });
  // flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_ && flutter_controller_->view()) {
    HWND child_hwnd = flutter_controller_->view()->GetNativeWindow();
    if (child_hwnd) {
      ::RemoveWindowSubclass(child_hwnd, ChildWindowSubclassProc, 1);
    }
  }

  // Clean up the window property
  ::RemovePropW(GetHandle(), L"VynodyInstanceProp");

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_NCHITTEST: {
      // Allow window resizing from the top edge when using custom title bar (TitleBarStyle.hidden).
      // In TitleBarStyle.hidden, WM_NCCALCSIZE sets top margin to 0 to prevent DWM from rendering
      // a native title bar. We hit-test the top edge here so Windows can show the resize cursor and resize.
      LONG_PTR const style = ::GetWindowLongPtr(hwnd, GWL_STYLE);
      if (!::IsZoomed(hwnd) && (style & WS_THICKFRAME)) {
        POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        POINT pt_client = pt;
        if (::ScreenToClient(hwnd, &pt_client)) {
          int const border_thickness = GetResizeBorderThickness(hwnd);
          if (pt_client.y >= -border_thickness && pt_client.y < border_thickness) {
            RECT client_rect;
            ::GetClientRect(hwnd, &client_rect);
            int const corner_width = border_thickness * 2;
            if (pt_client.x < corner_width) {
              return HTTOPLEFT;
            } else if (pt_client.x >= client_rect.right - corner_width) {
              return HTTOPRIGHT;
            } else {
              return HTTOP;
            }
          }
        }
      }
      break;
    }
    case WM_COPYDATA: {
      COPYDATASTRUCT* cds = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (cds && cds->dwData == 1) {
        std::string payload(reinterpret_cast<char*>(cds->lpData), cds->cbData);
        
        // Split newline-separated arguments
        std::vector<std::string> args;
        size_t start = 0;
        size_t end = payload.find('\n');
        while (end != std::string::npos) {
          args.push_back(payload.substr(start, end - start));
          start = end + 1;
          end = payload.find('\n', start);
        }
        if (start < payload.size()) {
          args.push_back(payload.substr(start));
        }

        // Pass arguments list to Flutter
        flutter::EncodableList encodable_args;
        for (const auto& arg : args) {
          encodable_args.push_back(flutter::EncodableValue(arg));
        }
        if (channel_) {
          channel_->InvokeMethod("onSecondInstance", std::make_unique<flutter::EncodableValue>(encodable_args));
        }

        // Focus and activate the main window
        HWND main_hwnd = GetHandle();
        if (!::IsWindowVisible(main_hwnd)) {
          ::ShowWindow(main_hwnd, SW_SHOW);
        }
        if (::IsIconic(main_hwnd)) {
          ::ShowWindow(main_hwnd, SW_RESTORE);
        }
        ::SetForegroundWindow(main_hwnd);
        ::SetFocus(main_hwnd);
        ::SetActiveWindow(main_hwnd);
      }
      return 0;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
