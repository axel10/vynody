import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Utility class for checking desktop keyboard modifier keys (Shift, Ctrl, Cmd, Alt).
class ModifierKeyUtils {
  const ModifierKeyUtils._();

  /// Returns true if Shift key is currently pressed (used for range selection).
  static bool get isRangeSelectPressed =>
      HardwareKeyboard.instance.isShiftPressed;

  /// Returns true if Control (Windows/Linux) or Meta/Command (macOS) key is currently pressed (used for discrete multi-selection).
  static bool get isDiscreteSelectPressed =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// Returns true if Alt / Option key is currently pressed.
  static bool get isAltPressed => HardwareKeyboard.instance.isAltPressed;

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

/// Manages index-based multi-selection state for lists on desktop.
/// Handles Shift-range, Ctrl/Cmd-toggle, selection mode, select all, and anchor tracking.
class IndexSelectionController extends ChangeNotifier {
  final Set<int> _selectedIndices = {};
  bool _isSelectionMode = false;
  int? _lastAnchorIndex;

  Set<int> get selectedIndices => _selectedIndices;
  bool get isSelectionMode => _isSelectionMode;
  bool get isNotEmpty => _selectedIndices.isNotEmpty;
  bool get isEmpty => _selectedIndices.isEmpty;
  int get length => _selectedIndices.length;
  int? get lastAnchorIndex => _lastAnchorIndex;

  bool contains(int index) => _selectedIndices.contains(index);

  void handleItemTap(
    int index,
    int totalLength, {
    void Function()? onNormalTap,
  }) {
    final isShift = ModifierKeyUtils.isRangeSelectPressed;
    final isCtrl = ModifierKeyUtils.isDiscreteSelectPressed;

    if (isShift) {
      final anchor = _lastAnchorIndex ?? index;
      final range = ModifierKeyUtils.getIndexRange(anchor, index);
      _isSelectionMode = true;
      _selectedIndices.addAll(range.where((i) => i >= 0 && i < totalLength));
      _lastAnchorIndex = index;
      notifyListeners();
    } else if (isCtrl) {
      _isSelectionMode = true;
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIndices.add(index);
      }
      _lastAnchorIndex = index;
      notifyListeners();
    } else if (_isSelectionMode) {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIndices.add(index);
      }
      _lastAnchorIndex = index;
      notifyListeners();
    } else {
      _lastAnchorIndex = index;
      onNormalTap?.call();
    }
  }

  void handleItemLongPress(int index) {
    _isSelectionMode = true;
    _selectedIndices.add(index);
    _lastAnchorIndex = index;
    notifyListeners();
  }

  void toggleItem(int index) {
    _isSelectionMode = true;
    if (_selectedIndices.contains(index)) {
      _selectedIndices.remove(index);
      if (_selectedIndices.isEmpty) {
        _isSelectionMode = false;
      }
    } else {
      _selectedIndices.add(index);
    }
    _lastAnchorIndex = index;
    notifyListeners();
  }

  void toggleSelectAll(int totalLength) {
    if (totalLength <= 0) return;
    _isSelectionMode = true;
    if (_selectedIndices.length == totalLength) {
      _selectedIndices.clear();
      _isSelectionMode = false;
    } else {
      _selectedIndices.clear();
      _selectedIndices.addAll(List.generate(totalLength, (i) => i));
    }
    notifyListeners();
  }

  void exitSelectionMode() {
    if (!_isSelectionMode && _selectedIndices.isEmpty && _lastAnchorIndex == null) return;
    _isSelectionMode = false;
    _selectedIndices.clear();
    _lastAnchorIndex = null;
    notifyListeners();
  }

  void cleanOutOfRange(int totalLength) {
    final before = _selectedIndices.length;
    _selectedIndices.removeWhere((idx) => idx >= totalLength || idx < 0);
    if (_selectedIndices.isEmpty && _isSelectionMode && totalLength == 0) {
      _isSelectionMode = false;
    }
    if (_selectedIndices.length != before) {
      notifyListeners();
    }
  }

  void removeIndex(int index) {
    if (_selectedIndices.remove(index)) {
      if (_selectedIndices.isEmpty) {
        _isSelectionMode = false;
      }
      notifyListeners();
    }
  }

  void clear() {
    _selectedIndices.clear();
    _isSelectionMode = false;
    _lastAnchorIndex = null;
    notifyListeners();
  }
}

