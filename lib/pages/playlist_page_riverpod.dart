import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlaylistSelectionModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setEnabled(bool enabled) {
    state = enabled;
  }
}

final playlistSelectionModeProvider =
    NotifierProvider<PlaylistSelectionModeController, bool>(
      PlaylistSelectionModeController.new,
    );
