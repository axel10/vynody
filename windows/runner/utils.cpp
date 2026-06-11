#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <filesystem>
#include <iostream>
#include <string>
#include <vector>

namespace {

std::wstring GetRunnerLogPath() {
  wchar_t* local_app_data = nullptr;
  size_t len = 0;
  if (_wdupenv_s(&local_app_data, &len, L"LOCALAPPDATA") != 0 ||
      local_app_data == nullptr) {
    return L".\\VibeFlow\\logs\\runner-launch.log";
  }

  std::wstring path(local_app_data);
  free(local_app_data);
  path += L"\\VibeFlow\\logs\\runner-launch.log";
  return path;
}

void EnsureParentDirectoryExists(const std::wstring& path) {
  const auto parent = std::filesystem::path(path).parent_path();
  if (parent.empty()) {
    return;
  }

  std::filesystem::path current;
  for (const auto& part : parent) {
    current /= part;
    ::CreateDirectoryW(current.c_str(), nullptr);
  }
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}

void AppendRunnerLog(const std::string& message) {
  const std::wstring log_path = GetRunnerLogPath();
  EnsureParentDirectoryExists(log_path);

  FILE* file = nullptr;
  if (_wfopen_s(&file, log_path.c_str(), L"ab") != 0 || file == nullptr) {
    return;
  }

  const std::string line = message + "\r\n";
  fwrite(line.data(), 1, line.size(), file);
  fclose(file);
}
