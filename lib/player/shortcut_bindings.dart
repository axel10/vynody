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
    AppShortcutAction.playPause => '播放 / 暂停',
    AppShortcutAction.next => '下一首',
    AppShortcutAction.previous => '上一首',
    AppShortcutAction.volumeUp => '音量增加',
    AppShortcutAction.volumeDown => '音量减少',
    AppShortcutAction.mute => '静音切换',
    AppShortcutAction.seekForward => '快进 5 秒',
    AppShortcutAction.seekBackward => '后退 5 秒',
    AppShortcutAction.toggleFullScreen => '切换全屏',
  };

  String get description => switch (this) {
    AppShortcutAction.playPause => '控制当前播放状态。',
    AppShortcutAction.next => '切换到下一首歌曲。',
    AppShortcutAction.previous => '切换到上一首歌曲。',
    AppShortcutAction.volumeUp => '每次增加 5% 音量。',
    AppShortcutAction.volumeDown => '每次减少 5% 音量。',
    AppShortcutAction.mute => '切换静音。',
    AppShortcutAction.seekForward => '向前快进 5 秒。',
    AppShortcutAction.seekBackward => '向后快退 5 秒。',
    AppShortcutAction.toggleFullScreen => '在窗口模式和全屏模式之间切换。',
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
      return '未知按键';
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
