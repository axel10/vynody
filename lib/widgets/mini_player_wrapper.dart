import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/pages/main_layout.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';
import 'package:vynody/pages/settings_page.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/widgets/floating_dock_bottom_bar.dart';
import 'package:vynody/widgets/library_selection_scope.dart';
import 'package:vynody/widgets/playback_hero_card.dart';
import 'package:vynody/widgets/playback_ui_tuning.dart';

export 'playback_ui_tuning.dart';

class MiniPlayerWrapper extends ConsumerStatefulWidget {
  const MiniPlayerWrapper({
    super.key,
    required this.child,
    this.tabIndex,
  });

  final Widget child;
  final int? tabIndex;

  @override
  ConsumerState<MiniPlayerWrapper> createState() => _MiniPlayerWrapperState();
}

class _MiniPlayerWrapperState extends ConsumerState<MiniPlayerWrapper> {
  bool _showMiniVolumeSlider = false;

  @override
  Widget build(BuildContext context) {
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final settings = ref.watch(settingsServiceProvider);
    final currentTabIndex = ref.watch(mainTabIndexProvider);
    final activeTabIndex = widget.tabIndex ?? currentTabIndex;

    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final Size size = MediaQuery.of(context).size;
    final bool isSmallWin = PlaybackPageUiTuning.isSmallWindow(
      size,
      isWaveformEnabled: ref.watch(isEffectiveWaveformEnabledProvider),
      isSmallWindowMode: settings.isSmallWindowMode,
    );
    final bool isDrawerOpen =
        isDesktop && !isSmallWin && ref.watch(rightQueueDrawerProvider);
    final double effectiveWidth =
        size.width - (isDrawerOpen ? kRightQueueDrawerWidth : 0.0);
    final bool isLandscape = !isSmallWin && (effectiveWidth > size.height);
    final bool useSidebar = isLandscape;

    final selectionScope = ref.watch(librarySelectionScopeProvider);
    final librarySelectionActive = selectionScope != LibrarySelectionScope.none;
    final bool isKeyboardVisible =
        MediaQuery.of(context).viewInsets.bottom > 0;
    final showPlayer =
        currentMusic != null && !librarySelectionActive && !isKeyboardVisible;

    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        if (useSidebar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            bottom: showPlayer
                ? (20.0 + MediaQuery.of(context).padding.bottom)
                : -120.0,
            left: 0,
            right: 0,
            child: Center(
              child: currentMusic != null
                  ? Builder(
                      builder: (context) {
                        final audio = ref.read(audioServiceProvider);
                        return Container(
                          key: const ValueKey('dynamic-island-detail'),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width >= 568.0
                                ? (MediaQuery.of(context).size.width * 0.9)
                                    .clamp(568.0, double.infinity)
                                : MediaQuery.of(context).size.width * 0.9,
                          ),
                          child: PlaybackHeroCard(
                            isMini: true,
                            enableHero: false,
                            isLandscape: isLandscape,
                            showMiniVolumeSlider: _showMiniVolumeSlider,
                            onMiniTap: () =>
                                navigateToMainTab(context, index: 1),
                            onPrevious: audio.previous,
                            onPlayPause: audio.togglePlay,
                            onNext: audio.next,
                            onScrubbing: (val) {
                              // Mini player handles scrubbing internally
                            },
                            onSeek: (val) {
                              audio.seek(
                                Duration(
                                  milliseconds:
                                      (audio.duration.inMilliseconds * val)
                                          .toInt(),
                                ),
                              );
                            },
                            onVolumeTap: () {
                              ref
                                  .read(settingsServiceProvider)
                                  .resetInactivity();
                              final nextVisible = !_showMiniVolumeSlider;
                              setState(() {
                                _showMiniVolumeSlider = nextVisible;
                              });
                            },
                            onMiniMouseExit: () {
                              if (!_showMiniVolumeSlider) return;
                              setState(() {
                                _showMiniVolumeSlider = false;
                              });
                            },
                            onVolumeChanged: (value) {
                              ref
                                  .read(settingsServiceProvider)
                                  .resetInactivity();
                              ref
                                  .read(mainLayoutUiControllerProvider.notifier)
                                  .setVolumeHudVisible(true);
                              audio.setVolume(value.roundToDouble());
                            },
                            onVolumeScroll: (deltaY) {
                              ref
                                  .read(settingsServiceProvider)
                                  .resetInactivity();
                              ref
                                  .read(mainLayoutUiControllerProvider.notifier)
                                  .setVolumeHudVisible(true);
                              audio.setVolume(
                                (audio.volume - deltaY * 0.1)
                                    .clamp(0.0, 100.0)
                                    .roundToDouble(),
                              );
                            },
                          ),
                        );
                      },
                    )
                  : const SizedBox.shrink(key: ValueKey('empty-island-detail')),
            ),
          )
        else
          FloatingDockBottomBar(
            currentIndex: activeTabIndex,
            onDestinationSelected: (index) async {
              // 在二级页面内点击当前所在的主 tab 保持当前页面，不做任何操作
              if (index == activeTabIndex) {
                return;
              }
              if (index == 5) {
                if (Platform.isIOS || Platform.isMacOS) {
                  await Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                } else {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                    ),
                  );
                }
                return;
              }
              if (index == 1) {
                await navigateToMainTab(context, index: 1);
                return;
              }
              Navigator.of(context).popUntil((route) => route.isFirst);
              await navigateToMainTab(context, index: index);
            },
            isPlayback: false,
            isHidden: librarySelectionActive || isKeyboardVisible,
            hideMiniPlayer: librarySelectionActive || isKeyboardVisible,
          ),
      ],
    );
  }
}
