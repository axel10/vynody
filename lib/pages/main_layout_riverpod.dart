import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class MainLayoutUiState {
  const MainLayoutUiState({
    this.showVolumeHud = false,
    this.showImmersiveTabBar = true,
    this.snackBarOffset = 0.0,
    this.isVolumeSliderVisible = false,
  });

  final bool showVolumeHud;
  final bool showImmersiveTabBar;
  final double snackBarOffset;
  final bool isVolumeSliderVisible;

  MainLayoutUiState copyWith({
    bool? showVolumeHud,
    bool? showImmersiveTabBar,
    double? snackBarOffset,
    bool? isVolumeSliderVisible,
  }) {
    return MainLayoutUiState(
      showVolumeHud: showVolumeHud ?? this.showVolumeHud,
      showImmersiveTabBar: showImmersiveTabBar ?? this.showImmersiveTabBar,
      snackBarOffset: snackBarOffset ?? this.snackBarOffset,
      isVolumeSliderVisible: isVolumeSliderVisible ?? this.isVolumeSliderVisible,
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

  void setVolumeSliderVisible(bool visible) {
    if (visible) {
      _hudTimer?.cancel();
    }
    state = state.copyWith(
      isVolumeSliderVisible: visible,
      showVolumeHud: visible ? false : state.showVolumeHud,
    );
  }

  void showVolumeHud() {
    if (state.isVolumeSliderVisible) return;
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

  void setSnackBarOffset(double offset) {
    state = state.copyWith(snackBarOffset: offset);
  }
}

final mainLayoutUiControllerProvider =
    NotifierProvider.autoDispose<MainLayoutUiController, MainLayoutUiState>(
      MainLayoutUiController.new,
    );
