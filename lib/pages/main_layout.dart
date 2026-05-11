import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../player/audio_riverpod.dart';
import '../player/audio_service.dart';
import '../pages/folder_page.dart';
import '../pages/playback_page.dart';
import '../pages/library_page.dart';
import '../pages/queue_page.dart';
import '../pages/settings_page.dart';
import '../player/music_file_utils.dart';
import '../player/settings_service.dart';
import '../player/shortcut_bindings.dart';
import 'main_layout_riverpod.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/playback_hero_card.dart';
import '../widgets/volume_controls.dart';
import '../widgets/global_drop_target.dart';
import '../utils/deleted_song_snack.dart';
import 'dart:async';

Route<void> buildMainLayoutRoute({
  required List<String> args,
  required int initialIndex,
}) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: 'main-tab-$initialIndex'),
    pageBuilder: (context, animation, secondaryAnimation) =>
        MainLayout(args: args, initialIndex: initialIndex),
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return child;
    },
  );
}

Future<void> navigateToMainTab(
  BuildContext context, {
  required int index,
  List<String> args = const [],
}) {
  return Navigator.of(
    context,
  ).pushReplacement(buildMainLayoutRoute(args: args, initialIndex: index));
}

class PlayPauseIntent extends Intent {
  const PlayPauseIntent();
}

class NextIntent extends Intent {
  const NextIntent();
}

class PreviousIntent extends Intent {
  const PreviousIntent();
}

class VolumeUpIntent extends Intent {
  const VolumeUpIntent();
}

class VolumeDownIntent extends Intent {
  const VolumeDownIntent();
}

class MuteIntent extends Intent {
  const MuteIntent();
}

class SeekForwardIntent extends Intent {
  const SeekForwardIntent();
}

class SeekBackwardIntent extends Intent {
  const SeekBackwardIntent();
}

class ToggleFullScreenIntent extends Intent {
  const ToggleFullScreenIntent();
}

class MainLayout extends ConsumerStatefulWidget {
  final List<String> args;
  final int initialIndex;

  const MainLayout({super.key, required this.args, this.initialIndex = 1});

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout> {
  late int _currentIndex;
  double? _lastVolume;
  bool _showMiniVolumeSlider = false;
  late final AudioService _audioService;

  MainLayoutUiController get _ui =>
      ref.read(mainLayoutUiControllerProvider.notifier);

  void _handleDesktopPointerActivity(PointerEvent event) {
    if (event is PointerDownEvent) {
      debugPrint('event.buttons: ${event.buttons}');
      if (event.buttons == 16) {
        // Forward button
        _audioService.setVolume((_audioService.volume + 5).roundToDouble());
        _triggerHUD();
      } else if (event.buttons == 8) {
        // Back button
        _audioService.setVolume((_audioService.volume - 5).roundToDouble());
        _triggerHUD();
      }
    }

    if (_currentIndex != 1) {
      return;
    }
    final settings = ref.read(settingsServiceProvider);
    if (settings.isImmersiveTabBarEnabled) {
      if (!ref.read(mainLayoutUiControllerProvider).showImmersiveTabBar) {
        _ui.showImmersiveTabBar();
      }
      _ui.hideImmersiveTabBarAfter(const Duration(seconds: 3));
    }
  }

  void _triggerHUD() {
    if (!mounted) return;
    _ui.showVolumeHud();
  }

  void _syncDeletedSongNoticeHandler() {
    _audioService.setMissingSongNoticeHandler(({required bool skipped}) {
      if (!mounted) return;
      showDeletedSongSnack(context, skipped: skipped);
    });
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _lastVolume = ref.read(audioVolumeProvider);
    _audioService = ref.read(audioServiceProvider);
    _syncDeletedSongNoticeHandler();

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleArgs();
      });
    }
  }

  @override
  void dispose() {
    _audioService.setMissingSongNoticeHandler(null);
    super.dispose();
  }

  Future<void> _setFullScreen(bool enable) async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (enable) {
        await windowManager.maximize();
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(false);
        // 等待原生窗口状态同步，确保 unmaximize 能够正确执行
        // await Future.delayed(const Duration(milliseconds: 100));
        await windowManager.unmaximize();
      }
    }
  }

  /// 处理启动时的命令行参数 (初次启动，例如双击打开应用)
  Future<void> _handleArgs() async {
    // 无参数直接返回
    if (!mounted || widget.args.isEmpty) {
      return;
    }

    final audio = ref.read(audioServiceProvider);

    for (var arg in widget.args) {
      // 预处理路径字符串
      final path = arg.replaceAll('"', '').trim();
      if (path.isEmpty) continue;

      // 文件存在性校验
      if (File(path).existsSync()) {
        // 匹配后缀
        if (MusicFileUtils.isMusicFilePath(path)) {
          // 调用播放服务读取音频并播放
          // append: true 确保该文件插入到底部立刻切歌
          await audio.playFile(path, p.basename(path), append: true);

          if (!mounted) return;

          // 切换到播放详情视图 (索引 1)
          await navigateToMainTab(context, index: 1);

          // 处理完一个核心音频文件后停止（通常双击只打开一个文件）
          break;
        }
      }
    }
  }

  Future<void> _onDestinationSelected(int index) async {
    if (index == 4) {
      await _openSettingsPage();
      return;
    }
    if (index == _currentIndex) {
      return;
    }
    await navigateToMainTab(context, index: index);
  }

  Future<void> _openSettingsPage() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsPage()));
  }

  Map<ShortcutActivator, Intent> _buildShortcutMap(SettingsService settings) {
    final bindings = <AppShortcutAction, Intent>{
      AppShortcutAction.playPause: const PlayPauseIntent(),
      AppShortcutAction.next: const NextIntent(),
      AppShortcutAction.previous: const PreviousIntent(),
      AppShortcutAction.volumeUp: const VolumeUpIntent(),
      AppShortcutAction.volumeDown: const VolumeDownIntent(),
      AppShortcutAction.mute: const MuteIntent(),
      AppShortcutAction.seekForward: const SeekForwardIntent(),
      AppShortcutAction.seekBackward: const SeekBackwardIntent(),
      AppShortcutAction.toggleFullScreen: const ToggleFullScreenIntent(),
    };

    final shortcuts = <ShortcutActivator, Intent>{};
    for (final entry in bindings.entries) {
      final activator = settings.shortcutBinding(entry.key).toActivator();
      if (activator == null) {
        continue;
      }
      shortcuts[activator] = entry.value;
    }
    return shortcuts;
  }

  Widget _buildTooltipIcon({
    required String message,
    required IconData icon,
    Color? color,
    double? size,
  }) {
    return Tooltip(
      message: message,
      child: Icon(icon, color: color, size: size),
    );
  }

  Widget _buildCurrentPage(bool isDesktop, bool useSidebar) {
    final bool isPlayback = _currentIndex == 1;
    final double leftPadding = (useSidebar && !isPlayback) ? 80.0 : 0.0;

    switch (_currentIndex) {
      case 0:
        return Padding(
          padding: EdgeInsets.only(top: isDesktop ? 32 : 0, left: leftPadding),
          child: FoldersPage(onOpenPlayback: () => _onDestinationSelected(1)),
        );
      case 1:
        return const PlaybackPage();
      case 2:
        return Padding(
          padding: EdgeInsets.only(top: isDesktop ? 32 : 0, left: leftPadding),
          child: const LibraryPage(),
        );
      case 3:
        return Padding(
          padding: EdgeInsets.only(top: isDesktop ? 32 : 0, left: leftPadding),
          child: const QueuePage(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  List<NavigationDestination> _buildBottomDestinations(
    BuildContext context,
    bool isPlayback,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return [
      NavigationDestination(
        icon: _buildTooltipIcon(
          message: l10n.file,
          icon: Icons.folder_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: _buildTooltipIcon(
          message: l10n.file,
          icon: Icons.folder,
          color: isPlayback ? Colors.white : null,
        ),
        label: l10n.file,
      ),
      NavigationDestination(
        icon: _buildTooltipIcon(
          message: l10n.play,
          icon: Icons.play_circle_outline,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: _buildTooltipIcon(
          message: l10n.play,
          icon: Icons.play_circle,
          color: isPlayback ? Colors.white : null,
        ),
        label: l10n.play,
      ),
      NavigationDestination(
        icon: _buildTooltipIcon(
          message: l10n.list,
          icon: Icons.playlist_play_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: _buildTooltipIcon(
          message: l10n.list,
          icon: Icons.playlist_play,
          color: isPlayback ? Colors.white : null,
        ),
        label: l10n.list,
      ),
      NavigationDestination(
        icon: _buildTooltipIcon(
          message: l10n.queueTab,
          icon: Icons.queue_music_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: _buildTooltipIcon(
          message: l10n.queueTab,
          icon: Icons.queue_music,
          color: isPlayback ? Colors.white : null,
        ),
        label: l10n.queueTab,
      ),
      NavigationDestination(
        icon: _buildTooltipIcon(
          message: l10n.settings,
          icon: Icons.settings_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: _buildTooltipIcon(
          message: l10n.settings,
          icon: Icons.settings,
          color: isPlayback ? Colors.white : null,
        ),
        label: l10n.settings,
      ),
    ];
  }

  List<NavigationRailDestination> _buildRailDestinations(
    BuildContext context,
    bool isPlayback,
  ) {
    final l10n = AppLocalizations.of(context)!;
    // Keep the destination box close to the rail's built-in M3 geometry.
    // A much taller custom box makes the hover/indicator highlight appear
    // vertically offset because NavigationRail positions it from the icon size.
    const iconBoxSize = 32.0;

    Widget railIcon(Widget child) {
      return SizedBox(
        width: iconBoxSize,
        height: iconBoxSize,
        child: Center(child: child),
      );
    }

    const verticalPadding = 10.0;
    return [
      NavigationRailDestination(
        padding: const EdgeInsets.symmetric(vertical: verticalPadding),
        icon: railIcon(
          _buildTooltipIcon(
            message: l10n.file,
            icon: Icons.folder_outlined,
            color: isPlayback ? Colors.white70 : null,
          ),
        ),
        selectedIcon: railIcon(
          _buildTooltipIcon(
            message: l10n.file,
            icon: Icons.folder,
            color: isPlayback ? Colors.white : null,
          ),
        ),
        label: Text(l10n.file),
      ),
      NavigationRailDestination(
        padding: const EdgeInsets.symmetric(vertical: verticalPadding),
        icon: railIcon(
          _buildTooltipIcon(
            message: l10n.play,
            icon: Icons.play_circle_outline,
            color: isPlayback ? Colors.white70 : null,
          ),
        ),
        selectedIcon: railIcon(
          _buildTooltipIcon(
            message: l10n.play,
            icon: Icons.play_circle,
            color: isPlayback ? Colors.white : null,
          ),
        ),
        label: Text(l10n.play),
      ),
      NavigationRailDestination(
        padding: const EdgeInsets.symmetric(vertical: verticalPadding),
        icon: railIcon(
          _buildTooltipIcon(
            message: l10n.list,
            icon: Icons.playlist_play_outlined,
            color: isPlayback ? Colors.white70 : null,
          ),
        ),
        selectedIcon: railIcon(
          _buildTooltipIcon(
            message: l10n.list,
            icon: Icons.playlist_play,
            color: isPlayback ? Colors.white : null,
          ),
        ),
        label: Text(l10n.list),
      ),
      NavigationRailDestination(
        padding: const EdgeInsets.symmetric(vertical: verticalPadding),
        icon: railIcon(
          _buildTooltipIcon(
            message: l10n.queueTab,
            icon: Icons.queue_music_outlined,
            color: isPlayback ? Colors.white70 : null,
          ),
        ),
        selectedIcon: railIcon(
          _buildTooltipIcon(
            message: l10n.queueTab,
            icon: Icons.queue_music,
            color: isPlayback ? Colors.white : null,
          ),
        ),
        label: Text(l10n.queueTab),
      ),
      NavigationRailDestination(
        padding: const EdgeInsets.symmetric(vertical: verticalPadding),
        icon: railIcon(
          _buildTooltipIcon(
            message: l10n.settings,
            icon: Icons.settings_outlined,
            color: isPlayback ? Colors.white70 : null,
          ),
        ),
        selectedIcon: railIcon(
          _buildTooltipIcon(
            message: l10n.settings,
            icon: Icons.settings,
            color: isPlayback ? Colors.white : null,
          ),
        ),
        label: Text(l10n.settings),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(mainLayoutUiControllerProvider);
    ref.listen<double>(audioVolumeProvider, (previous, next) {
      if (!mounted) return;
      if (_lastVolume != null && (_lastVolume! - next).abs() > 0.1) {
        _triggerHUD();
      }
      _lastVolume = next;
    });

    final settings = ref.watch(settingsServiceProvider);
    final theme = Theme.of(context);
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final bool showCustomTitleBar = Platform.isWindows || Platform.isLinux;
    final bool isPlayback = _currentIndex == 1;
    final navBgBaseColor =
        theme.navigationBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final navIndicatorBaseColor =
        theme.navigationBarTheme.indicatorColor ??
        theme.colorScheme.secondaryContainer;
    final navBgOpacityTarget = isPlayback ? 0.0 : 1.0;

    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final bool useSidebar = isLandscape;
    final bool hideImmersiveTabBar =
        isDesktop &&
        isPlayback &&
        settings.isImmersiveTabBarEnabled &&
        !uiState.showImmersiveTabBar;
    final bool useOverlayBottomNav =
        !useSidebar && isPlayback && settings.isImmersiveTabBarEnabled;

    return Shortcuts(
      shortcuts: _buildShortcutMap(settings),
      child: Actions(
        actions: <Type, Action<Intent>>{
          PlayPauseIntent: CallbackAction<PlayPauseIntent>(
            onInvoke: (_) => _audioService.togglePlay(),
          ),
          NextIntent: CallbackAction<NextIntent>(
            onInvoke: (_) => _audioService.next(),
          ),
          PreviousIntent: CallbackAction<PreviousIntent>(
            onInvoke: (_) => _audioService.previous(),
          ),
          VolumeUpIntent: CallbackAction<VolumeUpIntent>(
            onInvoke: (_) {
              _audioService.setVolume(
                (_audioService.volume + 5).roundToDouble(),
              );
              _triggerHUD();
              return null;
            },
          ),
          VolumeDownIntent: CallbackAction<VolumeDownIntent>(
            onInvoke: (_) {
              _audioService.setVolume(
                (_audioService.volume - 5).roundToDouble(),
              );
              _triggerHUD();
              return null;
            },
          ),
          MuteIntent: CallbackAction<MuteIntent>(
            onInvoke: (_) {
              _audioService.toggleMute();
              _triggerHUD();
              return null;
            },
          ),
          SeekForwardIntent: CallbackAction<SeekForwardIntent>(
            onInvoke: (_) =>
                _audioService.seekRelative(const Duration(seconds: 5)),
          ),
          SeekBackwardIntent: CallbackAction<SeekBackwardIntent>(
            onInvoke: (_) =>
                _audioService.seekRelative(const Duration(seconds: -5)),
          ),
          ToggleFullScreenIntent: CallbackAction<ToggleFullScreenIntent>(
            onInvoke: (_) async {
              final isFullScreen = await windowManager.isFullScreen();
              await _setFullScreen(!isFullScreen);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: GlobalDropTarget(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handleDesktopPointerActivity,
              onPointerMove: _handleDesktopPointerActivity,
              onPointerHover: _handleDesktopPointerActivity,
              child: Scaffold(
                extendBody: true,
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: _buildCurrentPage(isDesktop, useSidebar),
                    ),
                    if (useSidebar)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          width: hideImmersiveTabBar ? 0.0 : 80.0,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: SizedBox(
                              width: 80,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 500),
                                opacity: hideImmersiveTabBar ? 0.0 : 1.0,
                                child: TweenAnimationBuilder<double>(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  tween: Tween<double>(
                                    begin: navBgOpacityTarget,
                                    end: navBgOpacityTarget,
                                  ),
                                  builder: (context, animatedOpacity, child) {
                                    return NavigationRail(
                                      leading: isDesktop
                                          ? const SizedBox(height: 32)
                                          : null,
                                      backgroundColor: Color.lerp(
                                        Colors.transparent,
                                        navBgBaseColor,
                                        animatedOpacity,
                                      ),
                                      selectedIndex: _currentIndex,
                                      onDestinationSelected:
                                          _onDestinationSelected,
                                      labelType: NavigationRailLabelType.none,
                                      indicatorColor: Color.lerp(
                                        Colors.transparent,
                                        navIndicatorBaseColor,
                                        animatedOpacity,
                                      ),
                                      destinations: _buildRailDestinations(
                                        context,
                                        isPlayback,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (showCustomTitleBar)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: DesktopWindowTitleBar(
                          brightness: isPlayback
                              ? Brightness.dark
                              : theme.brightness,
                        ),
                      ),
                    Positioned(
                      bottom: useSidebar ? 20 : 80,
                      left: (useSidebar && !isPlayback) ? 80 : 0,
                      right: 0,
                      child: Center(
                        child: !isPlayback
                            ? Builder(
                                builder: (context) {
                                  final audio = ref.read(audioServiceProvider);
                                  final isLandscape =
                                      MediaQuery.of(context).orientation ==
                                      Orientation.landscape;

                                  return Container(
                                    key: const ValueKey('dynamic-island'),
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.9,
                                    ),
                                    child: PlaybackHeroCard(
                                      isMini: true,
                                      isLandscape: isLandscape,
                                      showMiniVolumeSlider:
                                          _showMiniVolumeSlider,
                                      onMiniTap: () =>
                                          _onDestinationSelected(1),
                                      onPrevious: audio.previous,
                                      onPlayPause: audio.togglePlay,
                                      onNext: audio.next,
                                      onScrubbing: (val) {
                                        // 迷你播放器内部会处理局部 UI 状态
                                      },
                                      onSeek: (val) {
                                        audio.seek(
                                          Duration(
                                            milliseconds:
                                                (audio.duration.inMilliseconds *
                                                        val)
                                                    .toInt(),
                                          ),
                                        );
                                      },
                                      onVolumeTap: () {
                                        ref
                                            .read(settingsServiceProvider)
                                            .resetInactivity();
                                        setState(() {
                                          _showMiniVolumeSlider =
                                              !_showMiniVolumeSlider;
                                        });
                                      },
                                      onVolumeChanged: (value) {
                                        ref
                                            .read(settingsServiceProvider)
                                            .resetInactivity();
                                        audio.setVolume(value.roundToDouble());
                                      },
                                    ),
                                  );
                                },
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('empty-island'),
                              ),
                      ),
                    ),
                    if (uiState.showVolumeHud)
                      VolumeHUD(volume: _audioService.volume),
                    if (useOverlayBottomNav)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _buildBottomNavigationBar(
                          context,
                          isPlayback: isPlayback,
                          navBgBaseColor: navBgBaseColor,
                          navIndicatorBaseColor: navIndicatorBaseColor,
                          navBgOpacityTarget: navBgOpacityTarget,
                          isHidden:
                              settings.isImmersiveTabBarEnabled &&
                              settings.isUserInactive,
                          includeBottomPadding: true,
                        ),
                      ),
                  ],
                ),
                bottomNavigationBar: useSidebar || useOverlayBottomNav
                    ? null
                    : _buildBottomNavigationBar(
                        context,
                        isPlayback: isPlayback,
                        navBgBaseColor: navBgBaseColor,
                        navIndicatorBaseColor: navIndicatorBaseColor,
                        navBgOpacityTarget: navBgOpacityTarget,
                        isHidden:
                            isPlayback &&
                            settings.isImmersiveTabBarEnabled &&
                            settings.isUserInactive,
                        includeBottomPadding: false,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(
    BuildContext context, {
    required bool isPlayback,
    required Color navBgBaseColor,
    required Color navIndicatorBaseColor,
    required double navBgOpacityTarget,
    required bool isHidden,
    required bool includeBottomPadding,
  }) {
    final bottomPadding = includeBottomPadding
        ? MediaQuery.of(context).padding.bottom
        : 0.0;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: isHidden ? 0.0 : 1.0,
      child: IgnorePointer(
        ignoring: isHidden,
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          tween: Tween<double>(
            begin: navBgOpacityTarget,
            end: navBgOpacityTarget,
          ),
          builder: (context, animatedOpacity, child) {
            return NavigationBar(
              height: 60 + bottomPadding,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
              selectedIndex: _currentIndex,
              backgroundColor: Color.lerp(
                Colors.transparent,
                navBgBaseColor,
                animatedOpacity,
              ),
              elevation: 0,
              indicatorColor: Color.lerp(
                Colors.transparent,
                navIndicatorBaseColor,
                animatedOpacity,
              ),
              onDestinationSelected: _onDestinationSelected,
              destinations: _buildBottomDestinations(context, isPlayback),
            );
          },
        ),
      ),
    );
  }
}
