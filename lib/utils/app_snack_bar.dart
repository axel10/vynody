import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../pages/main_layout_riverpod.dart';

class AppSnackBar {
  static void show(
    BuildContext context,
    WidgetRef? ref,
    SnackBar snackBar, {
    double offset = 70.0,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    final controller = ref != null
        ? ref.read(mainLayoutUiControllerProvider.notifier)
        : ProviderScope.containerOf(context, listen: false)
            .read(mainLayoutUiControllerProvider.notifier);

    // Dismiss any active snackbar immediately to avoid queuing and layout collision
    messenger.hideCurrentSnackBar();
    controller.setSnackBarOffset(offset);

    messenger.showSnackBar(snackBar).closed.then((reason) {
      // Only reset if this was the last snackbar or if we want to be safe.
      // In a more complex app, we'd count active snackbars.
      controller.setSnackBarOffset(0.0);
    });
  }
}
