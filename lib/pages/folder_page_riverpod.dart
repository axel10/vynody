import 'package:flutter_riverpod/flutter_riverpod.dart';

class FolderSelectionModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) {
    state = enabled;
  }
}

final folderSelectionModeProvider =
    NotifierProvider<FolderSelectionModeController, bool>(
      FolderSelectionModeController.new,
    );

class FolderRootSelectionModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) {
    state = enabled;
  }
}

final folderRootSelectionModeProvider =
    NotifierProvider<FolderRootSelectionModeController, bool>(
      FolderRootSelectionModeController.new,
    );

