import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:vibe_flow/player/library/music_file_utils.dart';

typedef SHChangeNotifyNative = Void Function(
  Int32 wEventId,
  Uint32 uFlags,
  Pointer<Void> dwItem1,
  Pointer<Void> dwItem2,
);

typedef SHChangeNotifyDart = void Function(
  int wEventId,
  int uFlags,
  Pointer<Void> dwItem1,
  Pointer<Void> dwItem2,
);

class WindowsAssociationService {
  static const String _progId = 'VibeFlow.AssocFile';

  /// Check if the application is currently registered for file associations in the Registry.
  static Future<bool> isAssociated() async {
    if (!Platform.isWindows) return false;

    try {
      final exePath = Platform.resolvedExecutable;
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Classes\VibeFlow.AssocFile\shell\open\command',
        '/ve',
      ]);

      if (result.exitCode != 0) {
        return false;
      }

      final output = result.stdout.toString();
      // Verify that the association exists and points to our current executable path.
      return output.contains(exePath);
    } catch (e) {
      debugPrint('Error checking file association: $e');
      return false;
    }
  }

  /// Register VibeFlow to associate with all supported audio extensions.
  static Future<void> associate() async {
    if (!Platform.isWindows) return;

    final exePath = Platform.resolvedExecutable;
    final extensions = MusicFileUtils.supportedAudioExtensions;

    // 1. Register ProgID and its shell open command
    await _runReg(['add', r'HKCU\Software\Classes\VibeFlow.AssocFile', '/ve', '/t', 'REG_SZ', '/d', 'VibeFlow Music File', '/f']);
    await _runReg(['add', r'HKCU\Software\Classes\VibeFlow.AssocFile\DefaultIcon', '/ve', '/t', 'REG_SZ', '/d', '"$exePath",0', '/f']);
    await _runReg(['add', r'HKCU\Software\Classes\VibeFlow.AssocFile\shell\open\command', '/ve', '/t', 'REG_SZ', '/d', '"$exePath" "%1"', '/f']);

    // 2. Register application capabilities for Default Apps UI
    await _runReg(['add', r'HKCU\Software\VibeFlow\Capabilities', '/v', 'ApplicationName', '/t', 'REG_SZ', '/d', 'VibeFlow', '/f']);
    await _runReg(['add', r'HKCU\Software\VibeFlow\Capabilities', '/v', 'ApplicationDescription', '/t', 'REG_SZ', '/d', 'A fully functional, highly compatible, and robust cross-platform music player.', '/f']);

    for (final ext in extensions) {
      // Add association capability
      await _runReg(['add', r'HKCU\Software\VibeFlow\Capabilities\FileAssociations', '/v', ext, '/t', 'REG_SZ', '/d', _progId, '/f']);

      // Register OpenWithProgids so it shows up in "Open With" list
      await _runReg(['add', 'HKCU\\Software\\Classes\\$ext\\OpenWithProgids', '/v', _progId, '/t', 'REG_NONE', '/d', '', '/f']);

      // Set VibeFlow as default handler in Classes (only takes effect if there is no user default override)
      await _runReg(['add', 'HKCU\\Software\\Classes\\$ext', '/ve', '/t', 'REG_SZ', '/d', _progId, '/f']);
    }

    // Register application under RegisteredApplications
    await _runReg(['add', r'HKCU\Software\RegisteredApplications', '/v', 'VibeFlow', '/t', 'REG_SZ', '/d', r'Software\VibeFlow\Capabilities', '/f']);

    // 3. Notify Windows Explorer shell to refresh association icons and defaults
    _notifyShell();
  }

  /// Remove VibeFlow's registry association settings.
  static Future<void> disassociate() async {
    if (!Platform.isWindows) return;

    final extensions = MusicFileUtils.supportedAudioExtensions;

    // 1. Remove registered application keys
    await _runReg(['delete', r'HKCU\Software\RegisteredApplications', '/v', 'VibeFlow', '/f']);
    await _runReg(['delete', r'HKCU\Software\VibeFlow', '/f']);

    // 2. Remove ProgID key
    await _runReg(['delete', r'HKCU\Software\Classes\VibeFlow.AssocFile', '/f']);

    // 3. Clean up extension associations
    for (final ext in extensions) {
      await _runReg(['delete', 'HKCU\\Software\\Classes\\$ext\\OpenWithProgids', '/v', _progId, '/f']);

      // Only delete the default value for the extension class if it currently points to VibeFlow.AssocFile
      final queryResult = await Process.run('reg', [
        'query',
        'HKCU\\Software\\Classes\\$ext',
        '/ve',
      ]);
      if (queryResult.exitCode == 0 && queryResult.stdout.toString().contains(_progId)) {
        await _runReg(['delete', 'HKCU\\Software\\Classes\\$ext', '/ve', '/f']);
      }
    }

    // 4. Notify Windows Explorer shell
    _notifyShell();
  }

  /// Helper to run reg command safely.
  static Future<void> _runReg(List<String> args) async {
    try {
      final result = await Process.run('reg', args);
      if (result.exitCode != 0) {
        debugPrint('reg command failed: reg ${args.join(' ')}\nError: ${result.stderr}');
      }
    } catch (e) {
      debugPrint('Error executing reg command: $e');
    }
  }

  /// Notify Windows shell that file associations have changed.
  static void _notifyShell() {
    try {
      final shell32 = DynamicLibrary.open('shell32.dll');
      final shChangeNotify = shell32.lookupFunction<SHChangeNotifyNative, SHChangeNotifyDart>('SHChangeNotify');

      // SHCNE_ASSOCCHANGED = 0x08000000
      // SHCNF_IDLIST = 0x0000
      shChangeNotify(0x08000000, 0x0000, nullptr, nullptr);
      debugPrint('Windows Shell notified of file association change.');
    } catch (e) {
      debugPrint('Failed to notify Windows shell of association change: $e');
    }
  }
}
