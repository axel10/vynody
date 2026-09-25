import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/list_reorder_utils.dart';

void main() {
  group('ListReorderUtils', () {
    test('moveItem moves elements accurately forward and backward', () {
      final list = ['A', 'B', 'C', 'D'];

      // Move 0 -> 2: ['B', 'C', 'A', 'D']
      expect(ListReorderUtils.moveItem(list, 0, 2), isTrue);
      expect(list, equals(['B', 'C', 'A', 'D']));

      // Move 2 -> 0: ['A', 'B', 'C', 'D']
      expect(ListReorderUtils.moveItem(list, 2, 0), isTrue);
      expect(list, equals(['A', 'B', 'C', 'D']));

      // Invalid moves
      expect(ListReorderUtils.moveItem(list, -1, 2), isFalse);
      expect(ListReorderUtils.moveItem(list, 1, 10), isFalse);
      expect(ListReorderUtils.moveItem(list, 1, 1), isFalse);
    });

    test('reorderIndex tracks active playing cursor accurately', () {
      // Current index at 0, moved to 2 -> becomes 2
      expect(
        ListReorderUtils.reorderIndex(0, oldIndex: 0, newIndex: 2),
        equals(2),
      );

      // Current index at 2, moved to 0 -> becomes 0
      expect(
        ListReorderUtils.reorderIndex(2, oldIndex: 2, newIndex: 0),
        equals(0),
      );

      // Item before cursor moved after cursor (0 moved to 3, cursor was at 2) -> cursor shifts -1 (becomes 1)
      expect(
        ListReorderUtils.reorderIndex(2, oldIndex: 0, newIndex: 3),
        equals(1),
      );

      // Item after cursor moved before cursor (3 moved to 0, cursor was at 1) -> cursor shifts +1 (becomes 2)
      expect(
        ListReorderUtils.reorderIndex(1, oldIndex: 3, newIndex: 0),
        equals(2),
      );

      // Irrelevant items moving after cursor -> cursor unchanged
      expect(
        ListReorderUtils.reorderIndex(0, oldIndex: 2, newIndex: 3),
        equals(0),
      );
    });

    test('reorderSelectedIndices correctly transforms selection sets', () {
      // Selection at {0, 2}. Item 0 moved to 1 -> {1, 2}
      final s1 = ListReorderUtils.reorderSelectedIndices(
        {0, 2},
        oldIndex: 0,
        newIndex: 1,
      );
      expect(s1, equals({1, 2}));

      // Selection at {1}. Item 2 moved to 0 -> {2}
      final s2 = ListReorderUtils.reorderSelectedIndices(
        {1},
        oldIndex: 2,
        newIndex: 0,
      );
      expect(s2, equals({2}));
    });
  });

  group('ReorderableKeyPool', () {
    test('creates, moves, and synchronizes keys correctly', () {
      final pool = ReorderableKeyPool(debugPrefix: 'test');

      final key0 = pool.getKey(0);
      final key1 = pool.getKey(1);
      final key2 = pool.getKey(2);

      expect(pool.length, equals(3));
      expect(pool.getKey(0), equals(key0));
      expect(pool.getKey(1), equals(key1));

      // Move key from 0 to 2
      pool.moveKey(0, 2);
      expect(pool.getKey(0), equals(key1));
      expect(pool.getKey(1), equals(key2));
      expect(pool.getKey(2), equals(key0));

      // Sync length shrinks pool
      pool.syncLength(2);
      expect(pool.length, equals(2));

      // Clear
      pool.clear();
      expect(pool.length, equals(0));
    });
  });
}
