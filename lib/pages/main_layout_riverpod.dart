import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainLayoutUiState {
  const MainLayoutUiState({
    this.showVolumeHud = false,
    this.showImmersiveTabBar = true,
  });

  final bool showVolumeHud;
  final bool showImmersiveTabBar;

  MainLayoutUiState copyWith({bool? showVolumeHud, bool? showImmersiveTabBar}) {
    return MainLayoutUiState(
      showVolumeHud: showVolumeHud ?? this.showVolumeHud,
      showImmersiveTabBar: showImmersiveTabBar ?? this.showImmersiveTabBar,
    );
  }
}

class MainLayoutUiController extends Notifier<MainLayoutUiState> {
  Timer? _hudTimer;
  Timer? _immersiveTabBarTimer;
  bool _disposed = false;

  @override
  MainLayoutUiState build() {
    ref.onDispose(() {
      _disposed = true;
      _hudTimer?.cancel();
      _immersiveTabBarTimer?.cancel();
    });
    return const MainLayoutUiState();
  }

  void showVolumeHud() {
    state = state.copyWith(showVolumeHud: true);
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed) return;
      state = state.copyWith(showVolumeHud: false);
    });
  }

  void showImmersiveTabBar() {
    _immersiveTabBarTimer?.cancel();
    state = state.copyWith(showImmersiveTabBar: true);
  }

  void hideImmersiveTabBarAfter(Duration delay) {
    _immersiveTabBarTimer?.cancel();
    _immersiveTabBarTimer = Timer(delay, () {
      if (_disposed) return;
      state = state.copyWith(showImmersiveTabBar: false);
    });
  }
}

final mainLayoutUiControllerProvider =
    NotifierProvider.autoDispose<MainLayoutUiController, MainLayoutUiState>(
      MainLayoutUiController.new,
    );
