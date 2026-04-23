import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

enum AppShortcutAction {
  playPause,
  next,
  previous,
  volumeUp,
  volumeDown,
  mute,
  seekForward,
  seekBackward,
  toggleFullScreen,
}

extension AppShortcutActionX on AppShortcutAction {
  bool get _isZhLocale =>
      WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'zh';

  String get storageKey => switch (this) {
    AppShortcutAction.playPause => 'play_pause',
    AppShortcutAction.next => 'next',
    AppShortcutAction.previous => 'previous',
    AppShortcutAction.volumeUp => 'volume_up',
    AppShortcutAction.volumeDown => 'volume_down',
    AppShortcutAction.mute => 'mute',
    AppShortcutAction.seekForward => 'seek_forward',
    AppShortcutAction.seekBackward => 'seek_backward',
    AppShortcutAction.toggleFullScreen => 'toggle_full_screen',
  };

  String get label => switch (this) {
    AppShortcutAction.playPause => _isZhLocale ? '播放 / 暂停' : 'Play / Pause',
    AppShortcutAction.next => _isZhLocale ? '下一首' : 'Next',
    AppShortcutAction.previous => _isZhLocale ? '上一首' : 'Previous',
    AppShortcutAction.volumeUp => _isZhLocale ? '音量增加' : 'Volume Up',
    AppShortcutAction.volumeDown => _isZhLocale ? '音量减少' : 'Volume Down',
    AppShortcutAction.mute => _isZhLocale ? '静音切换' : 'Toggle Mute',
    AppShortcutAction.seekForward => _isZhLocale ? '快进 5 秒' : 'Seek Forward 5s',
    AppShortcutAction.seekBackward =>
      _isZhLocale ? '后退 5 秒' : 'Seek Backward 5s',
    AppShortcutAction.toggleFullScreen =>
      _isZhLocale ? '切换全屏' : 'Toggle Full Screen',
  };

  String get description => switch (this) {
    AppShortcutAction.playPause =>
      _isZhLocale ? '控制当前播放状态。' : 'Control the current playback state.',
    AppShortcutAction.next =>
      _isZhLocale ? '切换到下一首歌曲。' : 'Skip to the next song.',
    AppShortcutAction.previous =>
      _isZhLocale ? '切换到上一首歌曲。' : 'Go back to the previous song.',
    AppShortcutAction.volumeUp =>
      _isZhLocale ? '每次增加 5% 音量。' : 'Increase volume by 5% each time.',
    AppShortcutAction.volumeDown =>
      _isZhLocale ? '每次减少 5% 音量。' : 'Decrease volume by 5% each time.',
    AppShortcutAction.mute => _isZhLocale ? '切换静音。' : 'Toggle mute.',
    AppShortcutAction.seekForward =>
      _isZhLocale ? '向前快进 5 秒。' : 'Seek forward 5 seconds.',
    AppShortcutAction.seekBackward =>
      _isZhLocale ? '向后快退 5 秒。' : 'Seek backward 5 seconds.',
    AppShortcutAction.toggleFullScreen =>
      _isZhLocale
          ? '在窗口模式和全屏模式之间切换。'
          : 'Switch between windowed mode and full screen.',
  };

  ShortcutBinding get defaultBinding => switch (this) {
    AppShortcutAction.playPause => ShortcutBinding(
      keyId: LogicalKeyboardKey.space.keyId,
    ),
    AppShortcutAction.next => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowRight.keyId,
      control: true,
    ),
    AppShortcutAction.previous => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowLeft.keyId,
      control: true,
    ),
    AppShortcutAction.volumeUp => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowUp.keyId,
      control: true,
    ),
    AppShortcutAction.volumeDown => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowDown.keyId,
      control: true,
    ),
    AppShortcutAction.mute => ShortcutBinding(
      keyId: LogicalKeyboardKey.audioVolumeMute.keyId,
    ),
    AppShortcutAction.seekForward => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowRight.keyId,
      alt: true,
    ),
    AppShortcutAction.seekBackward => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowLeft.keyId,
    ),
    AppShortcutAction.toggleFullScreen => ShortcutBinding(
      keyId: LogicalKeyboardKey.f11.keyId,
    ),
  };

  static AppShortcutAction fromStorageKey(String key) {
    final normalized = key.trim().toLowerCase();
    for (final action in AppShortcutAction.values) {
      if (action.storageKey == normalized) {
        return action;
      }
    }
    return AppShortcutAction.playPause;
  }
}

class ShortcutBinding {
  final int keyId;
  final bool control;
  final bool shift;
  final bool alt;
  final bool meta;

  const ShortcutBinding({
    required this.keyId,
    this.control = false,
    this.shift = false,
    this.alt = false,
    this.meta = false,
  });

  LogicalKeyboardKey? get logicalKey =>
      LogicalKeyboardKey.findKeyByKeyId(keyId);

  ShortcutActivator? toActivator() {
    final key = logicalKey;
    if (key == null) {
      return null;
    }
    return SingleActivator(
      key,
      control: control,
      shift: shift,
      alt: alt,
      meta: meta,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'keyId': keyId,
    'control': control,
    'shift': shift,
    'alt': alt,
    'meta': meta,
  };

  static ShortcutBinding? fromJson(Object? json) {
    if (json is! Map) {
      return null;
    }

    final keyId = json['keyId'];
    if (keyId is! int) {
      return null;
    }

    return ShortcutBinding(
      keyId: keyId,
      control: json['control'] as bool? ?? false,
      shift: json['shift'] as bool? ?? false,
      alt: json['alt'] as bool? ?? false,
      meta: json['meta'] as bool? ?? false,
    );
  }

  static ShortcutBinding fromActivator(ShortcutActivator activator) {
    if (activator is! SingleActivator) {
      throw ArgumentError(
        'Only SingleActivator is supported for shortcut bindings.',
      );
    }

    return ShortcutBinding(
      keyId: activator.trigger.keyId,
      control: activator.control,
      shift: activator.shift,
      alt: activator.alt,
      meta: activator.meta,
    );
  }

  static ShortcutBinding? fromKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return null;
    }

    final logicalKey = event.logicalKey;
    if (_isModifierKey(logicalKey)) {
      return null;
    }

    return ShortcutBinding(
      keyId: logicalKey.keyId,
      control: HardwareKeyboard.instance.isControlPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
      alt: HardwareKeyboard.instance.isAltPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
    );
  }

  static bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  String get displayLabel {
    final key = logicalKey;
    final parts = <String>[
      if (control) 'Ctrl',
      if (shift) 'Shift',
      if (alt) 'Alt',
      if (meta) 'Meta',
      _formatKeyLabel(key),
    ];
    return parts.join(' + ');
  }

  static String _formatKeyLabel(LogicalKeyboardKey? key) {
    if (key == null) {
      return WidgetsBinding.instance.platformDispatcher.locale.languageCode ==
              'zh'
          ? '未知按键'
          : 'Unknown key';
    }

    final label = key.keyLabel.trim();
    if (label.isNotEmpty) {
      return label.length == 1 ? label.toUpperCase() : label;
    }

    final debugName = key.debugName?.trim();
    if (debugName != null && debugName.isNotEmpty) {
      return debugName;
    }

    return '0x${key.keyId.toRadixString(16)}';
  }
}
