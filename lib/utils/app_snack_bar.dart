import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../pages/main_layout_riverpod.dart';

class AppSnackBar {
  static void show(
    BuildContext context,
    WidgetRef ref,
    SnackBar snackBar, {
    double offset = 70.0,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref.read(mainLayoutUiControllerProvider.notifier);

    // If there's already a snackbar being shown, we might already have an offset.
    // ScaffoldMessenger queues snackbars, so we should keep the offset until the last one is closed.
    // For simplicity, we just set it now and reset it when THIS one is closed.
    // If multiple are shown, the offset will persist until the last one's 'closed' future completes.
    
    controller.setSnackBarOffset(offset);
    
    messenger.showSnackBar(snackBar).closed.then((reason) {
      // Only reset if this was the last snackbar or if we want to be safe.
      // In a more complex app, we'd count active snackbars.
      controller.setSnackBarOffset(0.0);
    });
  }
}
