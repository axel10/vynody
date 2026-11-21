import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

typedef _GetAsyncKeyStateNative = ffi.Int16 Function(ffi.Int32 vKey);
typedef _GetAsyncKeyStateDart = int Function(int vKey);

/// Utility class for checking desktop keyboard modifier keys (Shift, Ctrl, Cmd, Alt).
class ModifierKeyUtils {
  const ModifierKeyUtils._();

  static const int _vkShift = 0x10;
  static const int _vkControl = 0x11;
  static const int _vkMenu = 0x12;

  static final bool _isFlutterTest =
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  static bool _win32LookupAttempted = false;
  static _GetAsyncKeyStateDart? _getAsyncKeyState;

  /// Optional test hook to simulate Windows `GetAsyncKeyState` responses.
  @visibleForTesting
  static bool Function(int vkCode)? debugWindowsKeyStateOverride;

  static bool? _queryWindowsKeyDown(int vkCode) {
    final override = debugWindowsKeyStateOverride;
    if (override != null) {
      return defaultTargetPlatform == TargetPlatform.windows
          ? override(vkCode)
          : null;
    }
    if (kIsWeb ||
        _isFlutterTest ||
        !Platform.isWindows ||
        defaultTargetPlatform != TargetPlatform.windows) {
      return null;
    }
    if (!_win32LookupAttempted) {
      _win32LookupAttempted = true;
      try {
        final user32 = ffi.DynamicLibrary.open('user32.dll');
        _getAsyncKeyState = user32
            .lookupFunction<_GetAsyncKeyStateNative, _GetAsyncKeyStateDart>(
              'GetAsyncKeyState',
            );
      } catch (_) {
        _getAsyncKeyState = null;
      }
    }
    final fn = _getAsyncKeyState;
    if (fn == null) return null;
    return (fn(vkCode) & 0x8000) != 0;
  }

  /// Returns true if Shift key is currently pressed (used for range selection).
  static bool get isRangeSelectPressed {
    final winState = _queryWindowsKeyDown(_vkShift);
    if (winState != null) return winState;
    return HardwareKeyboard.instance.isShiftPressed;
  }

  /// Returns true if Control (Windows/Linux/macOS) or Meta/Command (macOS only)
  /// key is currently pressed (used for discrete multi-selection).
  static bool get isDiscreteSelectPressed {
    final winState = _queryWindowsKeyDown(_vkControl);
    if (winState != null) return winState;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed) return true;
    return defaultTargetPlatform == TargetPlatform.macOS &&
        keyboard.isMetaPressed;
  }

  /// Returns true if Alt / Option key is currently pressed.
  static bool get isAltPressed {
    final winState = _queryWindowsKeyDown(_vkMenu);
    if (winState != null) return winState;
    return HardwareKeyboard.instance.isAltPressed;
  }

  /// Returns true if either Shift or Ctrl/Cmd is pressed.
  static bool get hasModifierPressed =>
      isRangeSelectPressed || isDiscreteSelectPressed;

  /// Calculates a closed index range [min(anchor, current), max(anchor, current)].
  static Iterable<int> getIndexRange(int anchor, int current) sync* {
    final start = math.min(anchor, current);
    final end = math.max(anchor, current);
    for (int i = start; i <= end; i++) {
      yield i;
    }
  }

  /// Helper to compute range keys for a list of items given an anchor and current index.
  static Set<K> computeRangeKeys<T, K>({
    required List<T> items,
    required int anchorIndex,
    required int currentIndex,
    required K Function(T item) keySelector,
    Set<K>? existingKeys,
  }) {
    final result = existingKeys != null ? Set<K>.from(existingKeys) : <K>{};
    final range = getIndexRange(anchorIndex, currentIndex);
    for (final i in range) {
      if (i >= 0 && i < items.length) {
        result.add(keySelector(items[i]));
      }
    }
    return result;
  }
}

/// Generic interaction helper that centralizes Shift/Ctrl/Normal tap logic for multi-selection.
class SelectionActionHelper {
  const SelectionActionHelper._();

  /// Handles an item tap event with keyboard modifier shortcuts (Shift range selection, Ctrl/Cmd toggle selection).
  ///
  /// Returns `true` if the event was handled as a selection operation, or `false` if `onNormalTap` was executed.
  static bool handleItemTap<T, K>({
    required int index,
    required K itemKey,
    required List<T> items,
    required K Function(T item) keySelector,
    required bool isSelectionMode,
    required Set<K> selectedKeys,
    required int? lastAnchorIndex,
    required void Function(int newAnchor) onUpdateAnchor,
    required void Function(Set<K> newKeys) onSetSelection,
    required void Function(K key) onToggleSelection,
    void Function()? onNormalTap,
    void Function()? onEnterSelectionMode,
  }) {
    final isShift = ModifierKeyUtils.isRangeSelectPressed;
    final isCtrl = ModifierKeyUtils.isDiscreteSelectPressed;

    if (isShift) {
      if (!isSelectionMode) {
        onEnterSelectionMode?.call();
      }
      final anchor = lastAnchorIndex ?? index;
      if (lastAnchorIndex == null) {
        onUpdateAnchor(index);
      }
      final newKeys = ModifierKeyUtils.computeRangeKeys(
        items: items,
        anchorIndex: anchor,
        currentIndex: index,
        keySelector: keySelector,
        existingKeys: selectedKeys,
      );
      onSetSelection(newKeys);
      return true;
    } else if (isCtrl) {
      if (!isSelectionMode) {
        onEnterSelectionMode?.call();
      }
      onToggleSelection(itemKey);
      onUpdateAnchor(index);
      return true;
    } else {
      if (isSelectionMode) {
        onToggleSelection(itemKey);
        onUpdateAnchor(index);
        return true;
      } else {
        onUpdateAnchor(index);
        onNormalTap?.call();
        return false;
      }
    }
  }
}
