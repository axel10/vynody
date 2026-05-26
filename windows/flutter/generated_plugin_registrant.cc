//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <dart_chromaprint/dart_chromaprint_plugin_c_api.h>
#include <file_selector_windows/file_selector_windows.h>
#include <permission_handler_windows/permission_handler_windows_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  DartChromaprintPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("DartChromaprintPluginCApi"));
  FileSelectorWindowsRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FileSelectorWindows"));
  PermissionHandlerWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("PermissionHandlerWindowsPlugin"));
}
