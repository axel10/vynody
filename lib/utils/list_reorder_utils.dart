import 'package:flutter/material.dart';

/// Utilities for reorderable lists (reordering elements, active indices, selections, and keys).
class ListReorderUtils {
  const ListReorderUtils._();

  /// Safely moves an item in [list] from [oldIndex] to [newIndex] in-place.
  ///
  /// Returns `true` if the item was moved, or `false` if indices were invalid.
  static bool moveItem<T>(List<T> list, int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= list.length ||
        newIndex < 0 ||
        newIndex >= list.length ||
        oldIndex == newIndex) {
      return false;
    }

    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    return true;
  }

  /// Calculates the new active/cursor index when an item in a list is moved from [oldIndex] to [newIndex].
  static int reorderIndex(
    int currentIndex, {
    required int oldIndex,
    required int newIndex,
  }) {
    if (currentIndex < 0) return currentIndex;
    if (currentIndex == oldIndex) {
      return newIndex;
    } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
      return currentIndex - 1;
    } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
      return currentIndex + 1;
    }
    return currentIndex;
  }

  /// Calculates the new set of selected indices after an item moves from [oldIndex] to [newIndex].
  static Set<int> reorderSelectedIndices(
    Iterable<int> selectedIndices, {
    required int oldIndex,
    required int newIndex,
  }) {
    if (selectedIndices.isEmpty || oldIndex == newIndex) {
      return selectedIndices.toSet();
    }

    final updated = <int>{};
    for (final index in selectedIndices) {
      if (index == oldIndex) {
        updated.add(newIndex);
      } else if (oldIndex < newIndex) {
        if (index > oldIndex && index <= newIndex) {
          updated.add(index - 1);
        } else {
          updated.add(index);
        }
      } else if (newIndex < oldIndex) {
        if (index >= newIndex && index < oldIndex) {
          updated.add(index + 1);
        } else {
          updated.add(index);
        }
      } else {
        updated.add(index);
      }
    }
    return updated;
  }
}

/// Helper for managing and tracking a pool of stable [GlobalKey]s in reorderable lists.
class ReorderableKeyPool {
  final List<GlobalKey> _keys = [];
  final String debugPrefix;

  ReorderableKeyPool({this.debugPrefix = 'reorderable-key'});

  /// Retrieves or creates a [GlobalKey] for [index].
  GlobalKey getKey(int index) {
    while (_keys.length <= index) {
      _keys.add(GlobalKey(debugLabel: '$debugPrefix-${_keys.length}'));
    }
    return _keys[index];
  }

  /// Reorders the keys when an item moves from [oldIndex] to [newIndex].
  void moveKey(int oldIndex, int newIndex) {
    if (oldIndex >= 0 &&
        oldIndex < _keys.length &&
        newIndex >= 0 &&
        newIndex < _keys.length &&
        oldIndex != newIndex) {
      final movedKey = _keys.removeAt(oldIndex);
      _keys.insert(newIndex, movedKey);
    }
  }

  /// Trims unused keys to prevent unbounded growth when the underlying list shrinks.
  void syncLength(int currentLength) {
    if (_keys.length > currentLength) {
      _keys.removeRange(currentLength, _keys.length);
    }
  }

  /// Clears all keys in the pool.
  void clear() {
    _keys.clear();
  }

  int get length => _keys.length;
}

/// A unified controller encapsulating [ReorderableKeyPool], in-place list reordering,
/// active index tracking, and selection remapping for reorderable lists.
class ReorderableListController<T> {
  final ReorderableKeyPool keyPool;
  List<T>? list;

  ReorderableListController({
    String debugPrefix = 'reorderable',
    this.list,
  }) : keyPool = ReorderableKeyPool(debugPrefix: debugPrefix);

  /// Retrieves or creates a [GlobalKey] for [index].
  GlobalKey getKey(int index) => keyPool.getKey(index);

  /// Trims unused keys to match the current item count.
  void syncLength(int currentLength) => keyPool.syncLength(currentLength);

  /// Clears all keys.
  void clear() => keyPool.clear();

  /// Handles a reorder event seamlessly:
  /// - Moves key in [keyPool]
  /// - Optionally moves the item in [targetList] or [list]
  /// - Optionally remaps [selectedIndices]
  /// - Optionally recalculates [currentIndex] and returns the updated index
  /// - Executes [onPersist] (e.g. Service call, IPC message, DB write)
  int? handleReorder({
    required int oldIndex,
    required int newIndex,
    List<T>? targetList,
    int? currentIndex,
    Set<int>? selectedIndices,
    void Function(Set<int> updatedSelection)? onSelectionChanged,
    void Function()? onPersist,
  }) {
    keyPool.moveKey(oldIndex, newIndex);

    final effectiveList = targetList ?? list;
    if (effectiveList != null) {
      ListReorderUtils.moveItem(effectiveList, oldIndex, newIndex);
    }

    if (selectedIndices != null && selectedIndices.isNotEmpty) {
      final updated = ListReorderUtils.reorderSelectedIndices(
        selectedIndices,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
      selectedIndices
        ..clear()
        ..addAll(updated);
      onSelectionChanged?.call(selectedIndices);
    }

    int? nextIndex;
    if (currentIndex != null) {
      nextIndex = ListReorderUtils.reorderIndex(
        currentIndex,
        oldIndex: oldIndex,
        newIndex: newIndex,
      );
    }

    onPersist?.call();
    return nextIndex;
  }
}

