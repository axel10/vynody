import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/utils/selection_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computeRangeKeys', () {
    final items = ['itemA', 'itemB', 'itemC', 'itemD', 'itemE'];

    test('computes forward range correctly', () {
      final keys = ModifierKeyUtils.computeRangeKeys(
        anchorIndex: 1,
        currentIndex: 3,
        items: items,
        keySelector: (s) => s,
      );
      expect(keys, {'itemB', 'itemC', 'itemD'});
    });

    test('computes backward range correctly', () {
      final keys = ModifierKeyUtils.computeRangeKeys(
        anchorIndex: 4,
        currentIndex: 2,
        items: items,
        keySelector: (s) => s,
      );
      expect(keys, {'itemC', 'itemD', 'itemE'});
    });

    test('computes range with existing keys', () {
      final keys = ModifierKeyUtils.computeRangeKeys(
        anchorIndex: 1,
        currentIndex: 2,
        items: items,
        keySelector: (s) => s,
        existingKeys: {'item0'},
      );
      expect(keys, {'item0', 'itemB', 'itemC'});
    });
  });

  group('SelectionActionHelper', () {
    final items = ['id0', 'id1', 'id2', 'id3', 'id4'];

    test('normal click when not in selection mode triggers onNormalTap and onUpdateAnchor', () {
      int? updatedAnchor;
      bool normalTapped = false;

      SelectionActionHelper.handleItemTap(
        index: 2,
        itemKey: 'id2',
        items: items,
        keySelector: (s) => s,
        isSelectionMode: false,
        selectedKeys: {},
        lastAnchorIndex: null,
        onUpdateAnchor: (a) => updatedAnchor = a,
        onSetSelection: (_) {},
        onToggleSelection: (_) {},
        onNormalTap: () => normalTapped = true,
      );

      expect(normalTapped, isTrue);
      expect(updatedAnchor, 2);
    });

    test('normal click when in selection mode toggles selection', () {
      int? updatedAnchor;
      String? toggledKey;

      SelectionActionHelper.handleItemTap(
        index: 2,
        itemKey: 'id2',
        items: items,
        keySelector: (s) => s,
        isSelectionMode: true,
        selectedKeys: {'id1'},
        lastAnchorIndex: 1,
        onUpdateAnchor: (a) => updatedAnchor = a,
        onSetSelection: (_) {},
        onToggleSelection: (k) => toggledKey = k,
      );

      expect(toggledKey, 'id2');
      expect(updatedAnchor, 2);
    });

    testWidgets('shift click initializes anchor when lastAnchorIndex is null and performs range selection', (tester) async {
      int? currentAnchor;
      Set<String> selection = {};
      bool isMode = false;

      // Press shift
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      // First shift click on index 1
      SelectionActionHelper.handleItemTap(
        index: 1,
        itemKey: 'id1',
        items: items,
        keySelector: (s) => s,
        isSelectionMode: isMode,
        selectedKeys: selection,
        lastAnchorIndex: currentAnchor,
        onUpdateAnchor: (a) => currentAnchor = a,
        onEnterSelectionMode: () => isMode = true,
        onSetSelection: (keys) => selection = keys,
        onToggleSelection: (_) {},
      );

      expect(currentAnchor, 1);
      expect(selection, {'id1'});
      expect(isMode, isTrue);

      // Second shift click on index 3
      SelectionActionHelper.handleItemTap(
        index: 3,
        itemKey: 'id3',
        items: items,
        keySelector: (s) => s,
        isSelectionMode: isMode,
        selectedKeys: selection,
        lastAnchorIndex: currentAnchor,
        onUpdateAnchor: (a) => currentAnchor = a,
        onEnterSelectionMode: () => isMode = true,
        onSetSelection: (keys) => selection = keys,
        onToggleSelection: (_) {},
      );

      // Anchor should remain 1 and range 1..3 (id1, id2, id3) should be selected
      expect(currentAnchor, 1);
      expect(selection, {'id1', 'id2', 'id3'});

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    });

    testWidgets('Meta (Win) key does not enter selection mode on Windows', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        bool normalTapped = false;
        bool enteredSelectionMode = false;

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        try {
          expect(ModifierKeyUtils.isDiscreteSelectPressed, isFalse);

          SelectionActionHelper.handleItemTap(
            index: 1,
            itemKey: 'id1',
            items: items,
            keySelector: (s) => s,
            isSelectionMode: false,
            selectedKeys: {},
            lastAnchorIndex: null,
            onUpdateAnchor: (_) {},
            onEnterSelectionMode: () => enteredSelectionMode = true,
            onSetSelection: (_) {},
            onToggleSelection: (_) {},
            onNormalTap: () => normalTapped = true,
          );

          expect(normalTapped, isTrue);
          expect(enteredSelectionMode, isFalse);
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Meta (Cmd) key enters selection mode on macOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        bool enteredSelectionMode = false;
        String? toggledKey;

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        try {
          expect(ModifierKeyUtils.isDiscreteSelectPressed, isTrue);

          SelectionActionHelper.handleItemTap(
            index: 1,
            itemKey: 'id1',
            items: items,
            keySelector: (s) => s,
            isSelectionMode: false,
            selectedKeys: {},
            lastAnchorIndex: null,
            onUpdateAnchor: (_) {},
            onEnterSelectionMode: () => enteredSelectionMode = true,
            onSetSelection: (_) {},
            onToggleSelection: (k) => toggledKey = k,
          );

          expect(enteredSelectionMode, isTrue);
          expect(toggledKey, 'id1');
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Windows trusts native key state over stuck HardwareKeyboard state', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      ModifierKeyUtils.debugWindowsKeyStateOverride = (_) => false;
      try {
        // Simulate stuck Shift & Ctrl in Flutter HardwareKeyboard cache
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        try {
          expect(ModifierKeyUtils.isRangeSelectPressed, isFalse);
          expect(ModifierKeyUtils.isDiscreteSelectPressed, isFalse);

          bool normalTapped = false;
          bool enteredSelectionMode = false;

          SelectionActionHelper.handleItemTap(
            index: 2,
            itemKey: 'id2',
            items: items,
            keySelector: (s) => s,
            isSelectionMode: false,
            selectedKeys: {},
            lastAnchorIndex: null,
            onUpdateAnchor: (_) {},
            onEnterSelectionMode: () => enteredSelectionMode = true,
            onSetSelection: (_) {},
            onToggleSelection: (_) {},
            onNormalTap: () => normalTapped = true,
          );

          expect(normalTapped, isTrue);
          expect(enteredSelectionMode, isFalse);

          // When native key state reports Ctrl pressed (VK_CONTROL = 0x11), it enters selection mode
          ModifierKeyUtils.debugWindowsKeyStateOverride = (vk) => vk == 0x11;
          expect(ModifierKeyUtils.isDiscreteSelectPressed, isTrue);

          String? toggledKey;
          SelectionActionHelper.handleItemTap(
            index: 2,
            itemKey: 'id2',
            items: items,
            keySelector: (s) => s,
            isSelectionMode: false,
            selectedKeys: {},
            lastAnchorIndex: null,
            onUpdateAnchor: (_) {},
            onEnterSelectionMode: () => enteredSelectionMode = true,
            onSetSelection: (_) {},
            onToggleSelection: (k) => toggledKey = k,
          );

          expect(enteredSelectionMode, isTrue);
          expect(toggledKey, 'id2');
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
        ModifierKeyUtils.debugWindowsKeyStateOverride = null;
      }
    });
  });
}
