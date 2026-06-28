import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/settings/settings_service.dart';

class DesktopTrayService with TrayListener {
  final AudioService audioService;
  final SettingsService settingsService;
  bool _initialized = false;
  bool? _lastIsPlaying;
  bool? _lastIsMuted;

  DesktopTrayService({
    required this.audioService,
    required this.settingsService,
  }) {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      settingsService.addListener(_handleSettingsChange);
      _syncTrayState();
    }
  }

  void _handleSettingsChange() {
    _syncTrayState();
  }

  Future<void> _syncTrayState() async {
    final enabled = settingsService.enableSystemTray;
    if (enabled && !_initialized) {
      await _initTray();
    } else if (!enabled && _initialized) {
      await _destroyTray();
    }
  }

  Future<void> _initTray() async {
    try {
      debugPrint('[Tray] Initializing system tray...');
      final iconPath = Platform.isWindows ? 'assets/images/app_icon.ico' : 'assets/images/icon.png';
      debugPrint('[Tray] Setting icon: $iconPath');
      await trayManager.setIcon(iconPath);
      if (!Platform.isLinux) {
        debugPrint('[Tray] Setting tooltip...');
        try {
          await trayManager.setToolTip('Vynody');
        } catch (e) {
          debugPrint('[Tray] Failed to set tooltip: $e');
        }
      }
      trayManager.addListener(this);
      _initialized = true;
      debugPrint('[Tray] System tray initialized. Setting up menu...');
      await updateMenu(force: true);
    } catch (e) {
      debugPrint('[Tray] Failed to initialize tray: $e');
    }
  }

  Future<void> _destroyTray() async {
    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
      _initialized = false;
      _lastIsPlaying = null;
      _lastIsMuted = null;
    } catch (e) {
      debugPrint('Failed to destroy tray: $e');
    }
  }

  Future<void> updateMenu({bool force = false}) async {
    if (!_initialized) {
      return;
    }

    final isPlaying = audioService.isPlaying;
    final isMuted = audioService.isMuted;

    if (!force && isPlaying == _lastIsPlaying && isMuted == _lastIsMuted) {
      return;
    }

    _lastIsPlaying = isPlaying;
    _lastIsMuted = isMuted;

    try {
      final menu = Menu(items: [
        MenuItem(
          key: 'previous',
          label: '上一首',
        ),
        MenuItem(
          key: 'toggle_play',
          label: isPlaying ? '暂停' : '播放',
        ),
        MenuItem(
          key: 'next',
          label: '下一首',
        ),
        MenuItem(
          key: 'toggle_mute',
          label: isMuted ? '取消静音' : '静音',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'disable_tray',
          label: '停用系统托盘',
        ),
        MenuItem(
          key: 'exit',
          label: '退出',
        ),
      ]);
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('[Tray] Failed to set tray context menu: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    _showAndFocusWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    debugPrint('[Tray] Menu item clicked: ${menuItem.key} (${menuItem.label})');
    switch (menuItem.key) {
      case 'previous':
        audioService.previous();
        break;
      case 'toggle_play':
        audioService.togglePlay();
        break;
      case 'next':
        audioService.next();
        break;
      case 'toggle_mute':
        audioService.toggleMute();
        break;
      case 'disable_tray':
        settingsService.enableSystemTray = false;
        break;
      case 'exit':
        _destroyTray().then((_) {
          exit(0);
        });
        break;
    }
  }

  Future<void> _showAndFocusWindow() async {
    try {
      final isMinimized = await windowManager.isMinimized();
      if (isMinimized) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('Failed to show and focus window: $e');
    }
  }

  void dispose() {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      settingsService.removeListener(_handleSettingsChange);
      _destroyTray();
    }
  }
}
