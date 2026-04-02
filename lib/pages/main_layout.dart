import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../player/audio_service.dart';
import '../player/settings_service.dart';
import '../pages/folder_page.dart';
import '../pages/playback_page.dart';
import '../pages/playlist_page.dart';
import '../pages/queue_page.dart';
import '../pages/settings_page.dart';
import '../widgets/playback_hero_card.dart';
import '../widgets/volume_controls.dart';
import '../widgets/global_drop_target.dart';
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

class MainLayout extends StatefulWidget {
  final List<String> args;
  final int initialIndex;

  const MainLayout({super.key, required this.args, this.initialIndex = 1});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> with WindowListener {
  late int _currentIndex;
  bool _showVolumeHUD = false;
  Timer? _hudTimer;
  double? _lastVolume;
  late AudioService _audioService;
  // _isFullScreen 决定了标题栏全屏按钮的图标状态（全屏 vs 窗口化）
  // 该状态通过 _syncWindowState() 与原生窗口状态保持同步
  bool _isFullScreen = false;
  bool _isMaximized = false;

  void _handleDesktopPointerActivity(PointerEvent event) {
    if (event is PointerDownEvent) {
      debugPrint('event.buttons: ${event.buttons}');
      if (event.buttons == 16) {
        // Forward button
        _audioService.setVolume((_audioService.volume + 5).roundToDouble());
      } else if (event.buttons == 8) {
        // Back button
        _audioService.setVolume((_audioService.volume - 5).roundToDouble());
      }
    }

    if (_currentIndex != 1) {
      return;
    }
    final settings = context.read<SettingsService>();
    if (settings.isImmersiveTabBarEnabled) {
      settings.resetInactivity();
    }
  }

  void _triggerHUD() {
    if (!mounted) return;
    setState(() {
      _showVolumeHUD = true;
    });
    _hudTimer?.cancel();
    _hudTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showVolumeHUD = false;
        });
      }
    });
  }

  void _onAudioServiceChange() {
    if (!mounted) return;
    if (_lastVolume != null &&
        (_lastVolume! - _audioService.volume).abs() > 0.1) {
      _triggerHUD();
    }
    _lastVolume = _audioService.volume;
  }

  // 同步当前原生窗口状态到 Flutter UI 状态
  Future<void> _syncWindowState() async {
    if (!mounted) return;

    final isFull = await windowManager.isFullScreen();
    final isMax = await windowManager.isMaximized();
    if (mounted) {
      if (_isFullScreen != isFull || _isMaximized != isMax) {
        setState(() {
          _isFullScreen = isFull;
          _isMaximized = isMax;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _audioService = context.read<AudioService>();
    _audioService.addListener(_onAudioServiceChange);

    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (isDesktop) {
      windowManager.addListener(this);
      _syncWindowState();
    }

    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleArgs();
      });
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _audioService.removeListener(_onAudioServiceChange);
    _hudTimer?.cancel();
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    // 系统触发进入全屏时同步状态
    unawaited(_syncWindowState());
  }

  @override
  void onWindowLeaveFullScreen() {
    // 系统触发退出全屏时同步状态

    windowManager.setFullScreen(false);
    // Future.delayed(Duration(milliseconds: 100));
    unawaited(_syncWindowState());
  }

  @override
  void onWindowMinimize() {
    unawaited(_syncWindowState());
  }

  @override
  void onWindowRestore() {
    // 窗口从最小化恢复或从最大化恢复时都会触发
    Future.delayed(const Duration(milliseconds: 50), () {
      unawaited(_syncWindowState());
    });
  }

  @override
  void onWindowMaximize() {
    unawaited(_syncWindowState());
  }

  @override
  void onWindowUnmaximize() {
    // 监听窗口取消最大化
    debugPrint("--- 监听到取消最大化 ---");
    // 强制执行状态同步，且略微延迟以等待原生 API 状态位翻转
    Future.delayed(const Duration(milliseconds: 50), () {
      unawaited(_syncWindowState());
    });
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

  Future<void> _handleArgs() async {
    if (widget.args.isEmpty) {
      return;
    }

    final audio = context.read<AudioService>();
    final List<String> audioExtensions = [
      '.mp3',
      '.m4a',
      '.wav',
      '.flac',
      '.ogg',
    ];

    for (var arg in widget.args) {
      final path = arg.replaceAll('"', '').trim();
      if (path.isEmpty) continue;
      if (File(path).existsSync()) {
        final ext = p.extension(path).toLowerCase();
        if (audioExtensions.contains(ext)) {
          audio.playFile(path, p.basename(path), append: true);
          if (!mounted) return;
          await navigateToMainTab(context, index: 1);
          break;
        }
      }
    }
  }

  Future<void> _onDestinationSelected(int index) async {
    if (index == 4) {
      _showMoreMenu();
      return;
    }
    if (index == _currentIndex) {
      return;
    }
    await navigateToMainTab(context, index: index);
  }

  Future<void> _showMoreMenu() async {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    final value = await showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        size.width,
        offset.dy + size.height - 100,
        0,
        0,
      ),
      items: [
        PopupMenuItem(
          value: 'settings',
          child: ListTile(
            leading: Icon(Icons.settings),
            title: Text(AppLocalizations.of(context)!.settings),
          ),
        ),
      ],
    );
    if (!mounted || value != 'settings') {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsPage()),
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
          child: const PlaylistPage(),
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
    return [
      NavigationDestination(
        icon: Icon(
          Icons.folder_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.folder,
          color: isPlayback ? Colors.white : null,
        ),
        label: AppLocalizations.of(context)!.file,
      ),
      NavigationDestination(
        icon: Icon(
          Icons.play_circle_outline,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.play_circle,
          color: isPlayback ? Colors.white : null,
        ),
        label: AppLocalizations.of(context)!.play,
      ),
      NavigationDestination(
        icon: Icon(
          Icons.playlist_play_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.playlist_play,
          color: isPlayback ? Colors.white : null,
        ),
        label: AppLocalizations.of(context)!.list,
      ),
      NavigationDestination(
        icon: Icon(
          Icons.queue_music_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.queue_music,
          color: isPlayback ? Colors.white : null,
        ),
        label: AppLocalizations.of(context)!.queueTab,
      ),
      NavigationDestination(
        icon: Icon(
          Icons.more_horiz_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.more_horiz,
          color: isPlayback ? Colors.white : null,
        ),
        label: '更多',
      ),
    ];
  }

  List<NavigationRailDestination> _buildRailDestinations(
    BuildContext context,
    bool isPlayback,
  ) {
    return [
      NavigationRailDestination(
        icon: Icon(
          Icons.folder_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.folder,
          color: isPlayback ? Colors.white : null,
        ),
        label: Text(AppLocalizations.of(context)!.file),
      ),
      NavigationRailDestination(
        icon: Icon(
          Icons.play_circle_outline,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.play_circle,
          color: isPlayback ? Colors.white : null,
        ),
        label: Text(AppLocalizations.of(context)!.play),
      ),
      NavigationRailDestination(
        icon: Icon(
          Icons.playlist_play_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.playlist_play,
          color: isPlayback ? Colors.white : null,
        ),
        label: Text(AppLocalizations.of(context)!.list),
      ),
      NavigationRailDestination(
        icon: Icon(
          Icons.queue_music_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.queue_music,
          color: isPlayback ? Colors.white : null,
        ),
        label: Text(AppLocalizations.of(context)!.queueTab),
      ),
      NavigationRailDestination(
        icon: Icon(
          Icons.more_horiz_outlined,
          color: isPlayback ? Colors.white70 : null,
        ),
        selectedIcon: Icon(
          Icons.more_horiz,
          color: isPlayback ? Colors.white : null,
        ),
        label: const Text('更多'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final theme = Theme.of(context);
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
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

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space):
            const PlayPauseIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true):
            const NextIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true):
            const PreviousIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true):
            const VolumeUpIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true):
            const VolumeDownIntent(),
        const SingleActivator(LogicalKeyboardKey.keyM, control: true):
            const MuteIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const SeekBackwardIntent(),
        const SingleActivator(LogicalKeyboardKey.f11):
            const ToggleFullScreenIntent(),
      },
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
            onInvoke: (_) => _audioService.setVolume(
              (_audioService.volume + 5).roundToDouble(),
            ),
          ),
          VolumeDownIntent: CallbackAction<VolumeDownIntent>(
            onInvoke: (_) => _audioService.setVolume(
              (_audioService.volume - 5).roundToDouble(),
            ),
          ),
          MuteIntent: CallbackAction<MuteIntent>(
            onInvoke: (_) => _audioService.toggleMute(),
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
              await _setFullScreen(!_isFullScreen);
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
                          width:
                              (isPlayback &&
                                  settings.isImmersiveTabBarEnabled &&
                                  settings.isUserInactive)
                              ? 0.0
                              : 80.0,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            physics: const NeverScrollableScrollPhysics(),
                            child: SizedBox(
                              width: 80,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 500),
                                opacity:
                                    (isPlayback &&
                                        settings.isImmersiveTabBarEnabled &&
                                        settings.isUserInactive)
                                    ? 0.0
                                    : 1.0,
                                child: TweenAnimationBuilder<double>(
                                  duration: const Duration(milliseconds: 120),
                                  curve: Curves.easeOut,
                                  tween: Tween<double>(
                                    begin: 1.0,
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
                    if (isDesktop)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            DragToMoveArea(
                              child: SizedBox(
                                height: 32,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    _WindowButton(
                                      icon:
                                          _isFullScreen
                                              ? Icons.fullscreen_exit
                                              : Icons.fullscreen,
                                      brightness:
                                          isPlayback
                                              ? Brightness.dark
                                              : theme.brightness,
                                      onPressed:
                                          () => _setFullScreen(!_isFullScreen),
                                    ),
                                    _WindowButton(
                                      icon: Icons.remove,
                                      brightness:
                                          isPlayback
                                              ? Brightness.dark
                                              : theme.brightness,
                                      onPressed: () async {
                                        if (_isFullScreen) {
                                          await _setFullScreen(false);
                                        }
                                        await windowManager.minimize();
                                      },
                                    ),
                                    _WindowButton(
                                      icon:
                                          _isMaximized
                                              ? Icons.filter_none
                                              : Icons.crop_square,
                                      iconSize: 14,
                                      brightness:
                                          isPlayback
                                              ? Brightness.dark
                                              : theme.brightness,
                                      onPressed: () async {
                                        if (_isFullScreen) {
                                          await _setFullScreen(false);
                                        } else if (_isMaximized) {
                                          await windowManager.unmaximize();
                                        } else {
                                          await windowManager.maximize();
                                        }
                                      },
                                    ),
                                    _WindowButton(
                                      icon: Icons.close,
                                      isClose: true,
                                      brightness:
                                          isPlayback
                                              ? Brightness.dark
                                              : theme.brightness,
                                      onPressed: windowManager.close,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
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
                                  final audio = context.read<AudioService>();
                                  return Container(
                                    key: const ValueKey('dynamic-island'),
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                          0.9,
                                    ),
                                    child: PlaybackHeroCard(
                                      isMini: true,
                                      onMiniTap: () =>
                                          _onDestinationSelected(1),
                                      onPrevious: audio.previous,
                                      onPlayPause: audio.togglePlay,
                                      onNext: audio.next,
                                    ),
                                  );
                                },
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('empty-island'),
                              ),
                      ),
                    ),
                    if (_showVolumeHUD) VolumeHUD(volume: _audioService.volume),
                  ],
                ),
                bottomNavigationBar: useSidebar
                    ? null
                    : AnimatedOpacity(
                        duration: const Duration(milliseconds: 500),
                        opacity:
                            (isPlayback &&
                                settings.isImmersiveTabBarEnabled &&
                                settings.isUserInactive)
                            ? 0.0
                            : 1.0,
                        child: TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 120),
                          curve: Curves.easeOut,
                          tween: Tween<double>(
                            begin: 1.0,
                            end: navBgOpacityTarget,
                          ),
                          builder: (context, animatedOpacity, child) {
                            return NavigationBar(
                              height: 60,
                              labelBehavior:
                                  NavigationDestinationLabelBehavior.alwaysHide,
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
                              destinations: _buildBottomDestinations(
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
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final Brightness brightness;
  final bool isClose;
  final double iconSize;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.brightness,
    this.isClose = false,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor =
        brightness == Brightness.dark ? Colors.white : Colors.black87;

    Color? hoverColor;
    if (isClose) {
      hoverColor = Colors.red.withValues(alpha: 0.8);
    } else {
      hoverColor =
          brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: hoverColor,
        child: Container(
          width: 46,
          height: 32,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: iconSize,
            color: isClose ? null : iconColor,
          ),
        ),
      ),
    );
  }
}
