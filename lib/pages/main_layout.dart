import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../player/audio_service.dart';
import '../player/settings_service.dart';
import '../pages/folder_page.dart';
import '../pages/playback_page.dart';
import '../pages/playlist_page.dart';
import '../pages/queue_page.dart';
import '../pages/settings_page.dart';
import '../widgets/dynamic_island_player.dart';

Route<void> buildMainLayoutRoute({
  required List<String> args,
  required int initialIndex,
}) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: 'main-tab-$initialIndex'),
    pageBuilder: (context, animation, secondaryAnimation) =>
        MainLayout(args: args, initialIndex: initialIndex),
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 220),
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

class MainLayout extends StatefulWidget {
  final List<String> args;
  final int initialIndex;

  const MainLayout({super.key, required this.args, this.initialIndex = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;

  void _handleDesktopPointerActivity(PointerEvent _) {
    if (_currentIndex != 1) {
      return;
    }
    final settings = context.read<SettingsService>();
    if (settings.isImmersiveTabBarEnabled && settings.isUserInactive) {
      settings.isUserInactive = false;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;

    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleArgs();
      });
    }
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
          audio.playFile(arg, p.basename(arg));
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
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(leading: Icon(Icons.settings), title: Text('璁剧疆')),
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

    return Listener(
      behavior: HitTestBehavior.translucent,
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
                    ? Container(
                        key: const ValueKey('dynamic-island'),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.9,
                        ),
                        child: GestureDetector(
                          onTap: () => _onDestinationSelected(1),
                          child: const DynamicIslandPlayer(),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('empty-island')),
              ),
            ),
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
                    label: '文件', // 修复：鏂囦欢 -> 文件
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
                    label: '播放', // 修复：鎾斁 -> 播放
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
                    label: '列表', // 修复：鍒楄〃 -> 列表
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
                    label: '队列', // 修复：闃熷垪 -> 队列
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
    );
  }
}
