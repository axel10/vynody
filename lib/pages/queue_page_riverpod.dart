import 'package:flutter_riverpod/flutter_riverpod.dart';

class QueueSelectionModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) {
    state = enabled;
  }
}

final queueSelectionModeProvider =
    NotifierProvider<QueueSelectionModeController, bool>(
      QueueSelectionModeController.new,
    );
