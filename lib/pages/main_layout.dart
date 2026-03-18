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

class MainLayout extends StatefulWidget {
  final List<String> args;
  final int initialIndex;

  const MainLayout({super.key, required this.args, this.initialIndex = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;
  bool _showVolumeHUD = false;
  Timer? _hudTimer;
  double? _lastVolume;
  late AudioService _audioService;

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
    if (settings.isImmersiveTabBarEnabled && settings.isUserInactive) {
      settings.isUserInactive = false;
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
    if (_lastVolume != null && (_lastVolume! - _audioService.volume).abs() > 0.1) {
      _triggerHUD();
    }
    _lastVolume = _audioService.volume;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    _audioService = context.read<AudioService>();
    _audioService.addListener(_onAudioServiceChange);

    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleArgs();
      });
    }
  }

  @override
  void dispose() {
    _audioService.removeListener(_onAudioServiceChange);
    _hudTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleArgs() async {
    if (_currentIndex == 1 || widget.args.isEmpty) {
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
      if (File(arg).existsSync()) {
        final ext = p.extension(arg).toLowerCase();
        if (audioExtensions.contains(ext)) {
          audio.playFile(arg, p.basename(arg), append: true);
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
          child: ListTile(leading: Icon(Icons.settings), title: Text(AppLocalizations.of(context)!.settings)),
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

  Widget _buildCurrentPage(bool isDesktop) {
    switch (_currentIndex) {
      case 0:
        return Padding(
          padding: EdgeInsets.only(top: isDesktop ? 32 : 0),
          child: FoldersPage(onOpenPlayback: () => _onDestinationSelected(1)),
        );
      case 1:
        return const PlaybackPage();
      case 2:
        return Padding(
          padding: EdgeInsets.only(top: isDesktop ? 32 : 0),
          child: const PlaylistPage(),
        );
      case 3:
        return Padding(
          padding: EdgeInsets.only(top: isDesktop ? 32 : 0),
          child: const QueuePage(),
        );
      default:
        return const SizedBox.shrink();
    }
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

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.space): const PlayPauseIntent(),
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
        const SingleActivator(LogicalKeyboardKey.arrowRight):
            const SeekForwardIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            const SeekBackwardIntent(),
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
            onInvoke: (_) => _audioService.setVolume((_audioService.volume + 5).roundToDouble()),
          ),
          VolumeDownIntent: CallbackAction<VolumeDownIntent>(
            onInvoke: (_) => _audioService.setVolume((_audioService.volume - 5).roundToDouble()),
          ),
          MuteIntent: CallbackAction<MuteIntent>(
            onInvoke: (_) => _audioService.toggleMute(),
          ),
          SeekForwardIntent: CallbackAction<SeekForwardIntent>(
            onInvoke: (_) => _audioService.seekRelative(const Duration(seconds: 5)),
          ),
          SeekBackwardIntent: CallbackAction<SeekBackwardIntent>(
            onInvoke: (_) => _audioService.seekRelative(const Duration(seconds: -5)),
          ),
        },
        child: Focus(
          autofocus: true,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _handleDesktopPointerActivity,
            onPointerMove: _handleDesktopPointerActivity,
            onPointerHover: _handleDesktopPointerActivity,
            child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            _buildCurrentPage(isDesktop),
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
                        child: WindowCaption(
                          brightness: isPlayback
                              ? Brightness.dark
                              : theme.brightness,
                          backgroundColor: Colors.transparent,
                          title: const SizedBox(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(
                child: !isPlayback
                    ? Builder(
                        builder: (context) {
                          final audio = context.read<AudioService>();
                          return Container(
                            key: const ValueKey('dynamic-island'),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.9,
                            ),
                            child: PlaybackHeroCard(
                              isMini: true,
                              onMiniTap: () => _onDestinationSelected(1),
                              onPrevious: audio.previous,
                              onPlayPause: audio.togglePlay,
                              onNext: audio.next,
                            ),
                          );
                        },
                      )
                    : const SizedBox.shrink(key: ValueKey('empty-island')),
              ),
            ),
            if (_showVolumeHUD) VolumeHUD(volume: _audioService.volume),
          ],
        ),
        bottomNavigationBar: AnimatedOpacity(
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
            tween: Tween<double>(begin: 1.0, end: navBgOpacityTarget),
            builder: (context, animatedOpacity, child) {
              return NavigationBar(
                height: 60,
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
                destinations: [
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
                    label: AppLocalizations.of(context)!.play, // 修复：鎾斁 -> 播放
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
                    label: AppLocalizations.of(context)!.list, // 修复：鍒楄〃 -> 列表
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
                    label: AppLocalizations.of(context)!.queueTab, // 修复：闃熷垪 -> 队列
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
                    label: '更多', // 修复：鏇村 -> 更多
                  ),
                ],
              );
            },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
