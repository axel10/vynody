import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

const double kRightQueueDrawerWidth = 340.0;
const double kMinComfortableWindowWidth = 920.0;
const Size kDefaultRegularMinWindowSize = Size(400.0, 650.0);
const Size kDrawerOpenMinWindowSize = Size(740.0, 650.0);

class RightQueueDrawerNotifier extends Notifier<bool> {
  double? _expandedDeltaWidth;
  Size? _sizeBeforeAutoExpand;

  @override
  bool build() => false;

  /// Toggles the drawer state
  Future<void> toggle() async {
    if (state) {
      await close();
    } else {
      await open();
    }
  }

  /// Opens the drawer. Constrains the minimum window width to [kDrawerOpenMinWindowSize]
  /// and, if the current window width is too narrow (< 920px), smoothly expands the
  /// window width by [kRightQueueDrawerWidth] to prevent squeezing the main content.
  Future<void> open() async {
    if (state) return;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        await windowManager.setMinimumSize(kDrawerOpenMinWindowSize);

        final isMax = await windowManager.isMaximized();
        final isFull = await windowManager.isFullScreen();

        if (!isMax && !isFull) {
          final currentSize = await windowManager.getSize();
          if (currentSize.width < kMinComfortableWindowWidth) {
            _expandedDeltaWidth = kRightQueueDrawerWidth;
            _sizeBeforeAutoExpand = currentSize;

            final targetWidth = (currentSize.width + kRightQueueDrawerWidth)
                .clamp(kDrawerOpenMinWindowSize.width, 99999.0);
            debugPrint(
              '[RightQueueDrawer] Auto-expanding window width from ${currentSize.width} to $targetWidth',
            );
            await windowManager.setSize(Size(targetWidth, currentSize.height));
          } else if (currentSize.width < kDrawerOpenMinWindowSize.width) {
            await windowManager.setSize(
              Size(kDrawerOpenMinWindowSize.width, currentSize.height),
            );
          }
        }
      } catch (e) {
        debugPrint('[RightQueueDrawer] Error checking/expanding window size: $e');
      }
    }

    state = true;
  }

  /// Closes the drawer. Restores the minimum window size to [kDefaultRegularMinWindowSize]
  /// and, if the window was previously auto-expanded, gracefully restores the original window width.
  Future<void> close({bool restoreWindowSize = true}) async {
    if (!state) return;

    state = false;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        await windowManager.setMinimumSize(kDefaultRegularMinWindowSize);
      } catch (e) {
        debugPrint('[RightQueueDrawer] Error restoring minimum window size: $e');
      }
    }

    if (restoreWindowSize &&
        _expandedDeltaWidth != null &&
        !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final delta = _expandedDeltaWidth!;
      final oldSize = _sizeBeforeAutoExpand;
      _expandedDeltaWidth = null;
      _sizeBeforeAutoExpand = null;

      try {
        final isMax = await windowManager.isMaximized();
        final isFull = await windowManager.isFullScreen();

        if (!isMax && !isFull) {
          final currentSize = await windowManager.getSize();
          // If the user didn't drastically change the width manually, restore it
          if (oldSize == null || (currentSize.width - (oldSize.width + delta)).abs() < 40.0) {
            final restoredWidth = (currentSize.width - delta).clamp(
              kDefaultRegularMinWindowSize.width,
              99999.0,
            );
            debugPrint(
              '[RightQueueDrawer] Restoring window width to $restoredWidth',
            );
            await windowManager.setSize(Size(restoredWidth, currentSize.height));
          }
        }
      } catch (e) {
        debugPrint('[RightQueueDrawer] Error restoring window size: $e');
      }
    } else {
      _expandedDeltaWidth = null;
      _sizeBeforeAutoExpand = null;
    }
  }
}

final rightQueueDrawerProvider =
    NotifierProvider<RightQueueDrawerNotifier, bool>(RightQueueDrawerNotifier.new);
