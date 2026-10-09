import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../widgets/app_tooltip.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show navigatorKey;
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/lyrics/lyrics_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import '../pages/folder_page.dart';
import '../pages/playback_page.dart';
import '../pages/library_page.dart';
import '../pages/queue_page.dart';
import '../pages/settings_page.dart';
import '../pages/sharing_page.dart';
import 'package:vynody/player/sharing/sharing_riverpod.dart';
import 'package:vynody/player/sharing/sharing_service.dart';
import 'package:vynody/player/sharing/remote_control/remote_control_service.dart';
import 'package:vynody/dialogs/transfer_dialogs.dart';
import 'package:vynody/dialogs/remote_pair_dialogs.dart';
import 'package:vynody/player/library/music_file_utils.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/audio/playback_source.dart';
import 'main_layout_riverpod.dart';
import '../dialogs/music_folders_dialog.dart';
import '../dialogs/trial_reset_notice_dialog.dart';
import '../widgets/desktop_window_title_bar.dart';
import '../widgets/floating_dock_bottom_bar.dart';
import '../widgets/playback_hero_card.dart';
import '../widgets/playback_ui_tuning.dart';
import '../widgets/global_drop_target.dart';
import '../widgets/library_selection_scope.dart';
import '../widgets/folder_scan_widgets.dart';
import '../utils/layout_constants.dart';
import 'package:vynody/player/platform/right_queue_drawer_controller.dart';
import '../widgets/right_queue_panel.dart';
import 'package:vynody/utils/deleted_song_snack.dart';
import 'package:vynody/utils/corrupted_song_snack.dart';
import 'package:vynody/utils/app_snack_bar.dart';

int _currentBaseTabIndex = 0;

Route<void> buildMainLayoutRoute({
  required List<String> args,
  required int initialIndex,
  int? fromIndex,
}) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: 'main-tab-$initialIndex'),
    pageBuilder: (context, animation, secondaryAnimation) =>
        MainLayout(args: args, initialIndex: initialIndex),
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (initialIndex == 1) {
        // 进入播放页：自底向上滑入；退出播放页：自顶向下滑出收起
        // 注意：在 reverse (pop) 期间，Flutter 传入 animation 的 value 是从 1.0 递减到 0.0。
        // 若 reverseCurve 设为 easeIn，会导致动画前半段极快、后半段在屏幕底端近乎停滞并在路由销毁时突兀消失；
        // 使用 easeOutCubic 能让退场动画在后半段保持充足动量完整滑出视口。
        final slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeOutCubic,
          ),
        );
        return SlideTransition(
          position: slideAnimation,
          child: child,
        );
      } else if (fromIndex == 1) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curvedAnimation,
          child: child,
        );
      }
      return child;
    },
  );
}

Future<void> navigateToMainTab(
  BuildContext context, {
  required int index,
  int? fromIndex,
  List<String> args = const [],
}) async {
  // 切页前先收起所有 tooltip，避免鼠标事件在路由切换期间继续驱动
  // 旧页面或新页面上的 RawTooltip 状态。
  Tooltip.dismissAllToolTips();

  // 让当前指针事件先完全结束，再执行路由替换。
  await Future<void>.delayed(Duration.zero);
  if (!context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  final currentRoute = ModalRoute.of(context);
  final bool isCurrentPlayback =
      currentRoute?.settings.name == 'main-tab-1' || fromIndex == 1;

  if (index == 1) {
    if (isCurrentPlayback) return;
    await navigator.push(
      buildMainLayoutRoute(
        args: args,
        initialIndex: 1,
        fromIndex: fromIndex,
      ),
    );
  } else if (isCurrentPlayback) {
    if (navigator.canPop()) {
      if (index != _currentBaseTabIndex && currentRoute != null) {
        navigator.replaceRouteBelow<void>(
          anchorRoute: currentRoute,
          newRoute: buildMainLayoutRoute(
            args: args,
            initialIndex: index,
            fromIndex: 1,
          ),
        );
      }
      _currentBaseTabIndex = index;
      navigator.pop();
    } else {
      _currentBaseTabIndex = index;
      await navigator.pushReplacement(
        buildMainLayoutRoute(
          args: args,
          initialIndex: index,
          fromIndex: fromIndex,
        ),
      );
    }
  } else {
    _currentBaseTabIndex = index;
    await navigator.pushReplacement(
      buildMainLayoutRoute(
        args: args,
        initialIndex: index,
        fromIndex: fromIndex,
      ),
    );
  }
}


class MainLayout extends ConsumerStatefulWidget {
  final List<String> args;
  final int initialIndex;
  final int initialLibraryTabIndex;
  final bool initialAlbums3DView;
  final int initialAlbums3DIndex;

  const MainLayout({
    super.key,
    required this.args,
    this.initialIndex = 1,
    this.initialLibraryTabIndex = 0,
    this.initialAlbums3DView = false,
    this.initialAlbums3DIndex = 0,
  });

  @override
  ConsumerState<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends ConsumerState<MainLayout>
    with WindowListener, TickerProviderStateMixin {
  late int _currentIndex;
  double? _lastVolume;
  bool _showMiniVolumeSlider = false;
  late final AudioService _audioService;
  DateTime? _ignoreResizeEventsUntil;
  Timer? _windowResizeDebounceTimer;
  late final MainLayoutUiController _uiController;
  final GlobalKey<FoldersPageState> _foldersPageKey =
      GlobalKey<FoldersPageState>();
  final GlobalKey<LibraryPageState> _libraryPageKey =
      GlobalKey<LibraryPageState>();
  final Set<int> _visitedTabs = <int>{};

  bool _isOnboardingDialogOpen = false;
  bool _isTrialResetNoticeDialogOpen = false;

  MainLayoutUiController get _ui => _uiController;

  Future<void> _checkAndShowTrialResetNotice() async {
    if (_isTrialResetNoticeDialogOpen || _isOnboardingDialogOpen || !mounted) return;
    final proService = ref.read(proLicenseServiceProvider);
    if (!proService.pendingTrialResetNotice) return;

    _isTrialResetNoticeDialogOpen = true;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) {
      _isTrialResetNoticeDialogOpen = false;
      return;
    }

    await proService.consumeTrialResetNotice();
    if (!mounted) {
      _isTrialResetNoticeDialogOpen = false;
      return;
    }

    await showTrialResetNoticeDialog(context);
    _isTrialResetNoticeDialogOpen = false;
  }

  void _handleDesktopPointerActivity(PointerEvent event) {
    final settings = ref.read(settingsServiceProvider);
    if (settings.isSmallWindowMode) {
      settings.resetInactivity();
    }

    if (event is PointerDownEvent) {
      debugPrint('event.buttons: ${event.buttons}');
      if (event.buttons == 16) {
        // Forward button
        _ui.setVolumeHudVisible(true);
        _audioService.setVolume((_audioService.volume + 5).roundToDouble());
      } else if (event.buttons == 8) {
        // Back button
        _ui.setVolumeHudVisible(true);
        _audioService.setVolume((_audioService.volume - 5).roundToDouble());
      }
    }

    if (_currentIndex != 1) {
      return;
    }
    if (settings.isImmersiveTabBarEnabled) {
      if (!ref.read(mainLayoutUiControllerProvider).showImmersiveTabBar) {
        _ui.showImmersiveTabBar();
      }
      _ui.hideImmersiveTabBarAfter(const Duration(seconds: 3));
    }
  }

  Future<void> _collapsePlayback() async {
    final previousTab = ref.read(previousMainTabIndexProvider);
    final targetIndex = (previousTab == 1 || previousTab < 0) ? 0 : previousTab;
    await _onDestinationSelected(targetIndex);
  }

  Future<void> _handleBackPressed() async {
    if (!Platform.isAndroid) return;

    // 如果当前页面之上还有 Modal/浮层路由（例如弹窗、抽屉、底部面板、上下文菜单等），优先关闭最顶层 Modal
    final mainModalRoute = ModalRoute.of(context);
    final rootNav = Navigator.of(context, rootNavigator: true);
    if (mainModalRoute != null && !mainModalRoute.isCurrent) {
      final didPop = await rootNav.maybePop();
      if (didPop) return;
    }

    // 如果在播放页，返回上一 Tab
    if (_currentIndex == 1) {
      await _collapsePlayback();
      return;
    }

    // 如果在曲库页且当前处于 3D 唱片封面流视图，则返回普通网格视图并恢复竖屏
    if (_currentIndex == 2) {
      if (ref.read(isAlbum3DViewActiveProvider)) {
        ref.read(isAlbum3DViewActiveProvider.notifier).set(false);
        return;
      }
      if (_libraryPageKey.currentState?.handleBackPressed() ?? false) {
        return;
      }
    }

    // 如果在目录页，且当前处于非根目录，则返回上一级目录
    if (_currentIndex == 0) {
      if (_foldersPageKey.currentState?.handleBackPressed() ?? false) {
        return;
      }
    }

    await SystemNavigator.pop();
  }

  void _syncDeletedSongNoticeHandler() {
    _audioService.setMissingSongNoticeHandler(({required bool skipped}) {
      if (!mounted) return;
      showDeletedSongSnack(context, ref, skipped: skipped);
    });
    _audioService.setCorruptedSongNoticeHandler(({required bool skipped}) {
      if (!mounted) return;
      showCorruptedSongSnack(context, ref, skipped: skipped);
    });
    _audioService.setRemotePlaybackErrorHandler((message) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      final text = message.isNotEmpty
          ? message
          : (l10n?.remoteConnectFailed ?? '无法连接到媒体库服务器');
      AppSnackBar.show(context, ref, SnackBar(content: Text(text)));
    });
  }

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsServiceProvider);
    final needOnboarding = !settings.hasShownOnboarding;
    final isStressTest = widget.args.any(
      (arg) => arg == '--stress-test' || arg == '--audio-stress-test',
    );
    final initialIndex = isStressTest
        ? 0
        : (needOnboarding ? 0 : widget.initialIndex);
    _currentIndex = initialIndex;
    _visitedTabs.add(_currentIndex);
    _lastVolume = ref.read(audioVolumeProvider);
    _audioService = ref.read(audioServiceProvider);
    _uiController = ref.read(mainLayoutUiControllerProvider.notifier);
    _syncDeletedSongNoticeHandler();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      ref.read(desktopLyricsManagerProvider);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(mainTabIndexProvider.notifier).setIndex(_currentIndex);
      if (_currentIndex != 1) {
        _currentBaseTabIndex = _currentIndex;
      }
      if (needOnboarding) {
        _triggerOnboardingFlow();
      } else {
        _checkAndShowTrialResetNotice();
      }
    });

    final isProUnlocked = ref.read(isProUnlockedProvider);
    if (settings.lanSharingEnabled && isProUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final serverState = ref.read(sharingServerStateProvider);
        if (!serverState.isRunning) {
          ref.read(sharingServerStateProvider.notifier).start();
        }
      });
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.addListener(this);
      windowManager.isFullScreen().then((isFull) {
        if (mounted) {
          ref.read(isWindowFullScreenProvider.notifier).state = isFull;
        }
      });
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleArgs();
        _checkAndRunStressTestAutomation();
      });
    }
  }

  @override
  void dispose() {
    _windowResizeDebounceTimer?.cancel();
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.removeListener(this);
    }
    _audioService.setMissingSongNoticeHandler(null);
    _audioService.setCorruptedSongNoticeHandler(null);
    _audioService.setRemotePlaybackErrorHandler(null);
    super.dispose();
  }

  @override
  void onWindowMinimize() {
    ref.read(isWindowMinimizedProvider.notifier).state = true;
    debugPrint('[main_layout] Window minimized');
  }

  @override
  void onWindowRestore() {
    ref.read(isWindowMinimizedProvider.notifier).state = false;
    debugPrint('[main_layout] Window restored');
  }

  @override
  void onWindowMaximize() {
    ref.read(isWindowMinimizedProvider.notifier).state = false;
    final settings = ref.read(settingsServiceProvider);
    if (!settings.isSmallWindowMode) {
      settings.isRegularWindowMaximized = true;
    }
    debugPrint('[main_layout] Window maximized');
  }

  @override
  void onWindowUnmaximize() {
    ref.read(isWindowMinimizedProvider.notifier).state = false;
    final settings = ref.read(settingsServiceProvider);
    if (!settings.isSmallWindowMode) {
      settings.isRegularWindowMaximized = false;
    }
    debugPrint('[main_layout] Window unmaximized');
  }

  @override
  void onWindowFocus() {
    ref.read(isWindowMinimizedProvider.notifier).state = false;
    debugPrint('[main_layout] Window focused');
  }

  @override
  void onWindowEnterFullScreen() {
    ref.read(isWindowFullScreenProvider.notifier).state = true;
    debugPrint('[main_layout] Window entered full screen');
  }

  @override
  void onWindowLeaveFullScreen() {
    ref.read(isWindowFullScreenProvider.notifier).state = false;
    debugPrint('[main_layout] Window left full screen');
  }

  @override
  void onWindowResized() {
    if (_ignoreResizeEventsUntil != null &&
        DateTime.now().isBefore(_ignoreResizeEventsUntil!)) {
      debugPrint(
        '[vynody] onWindowResized: IGNORED because within ignore period',
      );
      return;
    }
    _windowResizeDebounceTimer?.cancel();
    _windowResizeDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final settings = ref.read(settingsServiceProvider);
      if (settings.isSmallWindowMode) {
        final size = await windowManager.getSize();
        debugPrint(
          '[vynody] onWindowResized (debounced): size=$size, mode=${settings.smallWindowBottomPanelMode}',
        );
        if (settings.smallWindowBottomPanelMode !=
            SmallWindowBottomPanelMode.collapsed) {
          settings.savedSmallWindowQueueSize = size;
          debugPrint('[vynody] savedSmallWindowQueueSize updated to $size');
        } else {
          settings.savedSmallWindowSize = size;
          debugPrint('[vynody] savedSmallWindowSize updated to $size');
        }
      } else {
        final isMaximized = await windowManager.isMaximized();
        final isFullScreen = await windowManager.isFullScreen();
        final isMinimized = await windowManager.isMinimized();
        if (!isMaximized && !isFullScreen && !isMinimized) {
          settings.isRegularWindowMaximized = false;
          final size = await windowManager.getSize();
          if (size.width >= 400 && size.height >= 650) {
            settings.savedRegularWindowSize = size;
            debugPrint('[vynody] savedRegularWindowSize updated to $size');
          }
        } else if (isMaximized) {
          settings.isRegularWindowMaximized = true;
        }
      }
    });
  }

  /// 处理启动时的命令行参数 (初次启动，例如双击打开应用)
  Future<void> _handleArgs() async {
    // 无参数直接返回
    if (!mounted || widget.args.isEmpty) {
      debugPrint(
        '[external-open] _handleArgs skipped mounted=$mounted args=${widget.args}',
      );
      return;
    }

    final audio = ref.read(audioServiceProvider);
    debugPrint('[external-open] _handleArgs start args=${widget.args}');

    for (var arg in widget.args) {
      // 预处理路径字符串
      final path = arg.replaceAll('"', '').trim();
      if (path.isEmpty) {
        debugPrint('[external-open] _handleArgs skip empty arg="$arg"');
        continue;
      }

      // 文件存在性校验
      final exists = path.startsWith('content://') || File(path).existsSync();
      final isMusic = path.startsWith('content://') || MusicFileUtils.isMusicFilePath(path);
      debugPrint(
        '[external-open] _handleArgs inspect path=$path exists=$exists isMusic=$isMusic',
      );
      if (!exists) {
        continue;
      }

      // 匹配后缀
      if (isMusic) {
        debugPrint('[external-open] _handleArgs playFile begin path=$path');
        // 调用播放服务读取音频并播放
        // append: false 确保清空队列并将此歌曲设为唯一歌曲播放
        await audio.playFile(path, p.basename(path), append: false);
        debugPrint('[external-open] _handleArgs playFile done path=$path');

        if (!mounted) {
          debugPrint(
            '[external-open] _handleArgs abort after playFile, widget unmounted',
          );
          return;
        }

        // 切换到播放详情视图 (索引 1)
        debugPrint(
          '[external-open] _handleArgs navigateToMainTab begin path=$path',
        );
        await navigateToMainTab(context, index: 1);
        debugPrint(
          '[external-open] _handleArgs navigateToMainTab done path=$path',
        );

        // 处理完一个核心音频文件后停止（通常双击只打开一个文件）
        break;
      }
    }

    debugPrint('[external-open] _handleArgs end');
  }

  Future<void> _checkAndRunStressTestAutomation() async {
    final isStressTest = widget.args.any(
      (arg) => arg == '--stress-test' || arg == '--audio-stress-test',
    );
    if (!isStressTest) return;

    debugPrint(
      '[stress-test] Stress test flag detected, starting root folders playback automation...',
    );

    // Wait for the scanner service to finish loading/initializing.
    final scanner = ref.read(scannerServiceProvider);
    await scanner.ready;

    // Poll for up to 10 seconds (50 * 200ms) until root folders are loaded and we can retrieve allRootSongs.
    AudioService? audioService;
    final allRootSongs = <MusicFile>[];
    final seenAll = <String>{};

    for (int i = 0; i < 50; i++) {
      if (!mounted) return;
      audioService = ref.read(audioServiceProvider);

      final rootFolders = scanner.rootFolders;
      seenAll.clear();
      allRootSongs.clear();
      for (final folder in rootFolders) {
        for (final song in folder.allSongs) {
          if (seenAll.add(song.path)) {
            allRootSongs.add(song);
          }
        }
      }

      if (allRootSongs.isNotEmpty) {
        debugPrint(
          '[stress-test] Found ${allRootSongs.length} root folder songs to play.',
        );
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (!mounted || audioService == null) return;

    // Fallback: If no root songs are scanned yet, try reading non-external songs from MetadataDatabase
    if (allRootSongs.isEmpty) {
      debugPrint(
        '[stress-test] Root folders empty. Checking database for non-external songs...',
      );
      try {
        final db = MetadataDatabase();
        final songs = await db.getAllSongMetadata();
        final filtered = songs.where((song) {
          final flags = song.sourceFlags ?? 0;
          return (flags & SongSourceFlags.external) == 0;
        });

        for (final firstMetadata in filtered) {
          allRootSongs.add(
            MusicFile(
              path: firstMetadata.path,
              name: p.basename(firstMetadata.path),
              title: firstMetadata.title,
              artist: firstMetadata.artist,
              album: firstMetadata.album,
              trackNumber: firstMetadata.trackNumber,
              id: firstMetadata.id,
              artworkPath: firstMetadata.artworkPath,
              thumbnailPath: firstMetadata.thumbnailPath,
              artworkWidth: firstMetadata.artworkWidth,
              artworkHeight: firstMetadata.artworkHeight,
              durationMillis: firstMetadata.duration,
              lastModifiedTime: firstMetadata.lastModifiedTime,
            ),
          );
        }
        debugPrint(
          '[stress-test] Fallback database query found ${allRootSongs.length} non-external songs.',
        );
      } catch (e) {
        debugPrint('[stress-test] Fallback database query failed: $e');
      }
    }

    if (allRootSongs.isNotEmpty) {
      debugPrint(
        '[stress-test] Triggering "Play All" on root directory and seeking first song to 0ms...',
      );
      await audioService.playPlaylist(
        allRootSongs,
        source: PlaybackSource(
          type: PlaybackSourceType.folder,
          id: 'root',
          name: 'Directory',
        ),
      );

      // Wait a bit for playback to be initialized
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      // Seek to 0ms and ensure playback is started
      await audioService.seek(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      final isPlaying = ref.read(audioIsPlayingProvider);
      if (!isPlaying) {
        debugPrint('[stress-test] Starting playback...');
        await audioService.togglePlay();
      }

      // Automatically navigate to the PlaybackPage (index 1) after clicking Play All
      debugPrint('[stress-test] Navigating to playback page...');
      await _onDestinationSelected(1);
    } else {
      debugPrint(
        '[stress-test] WARNING: No music files available to run Play All in stress test.',
      );
      // Still navigate to PlaybackPage so the UI is on the correct page
      await _onDestinationSelected(1);
    }
  }

  Future<void> _onDestinationSelected(int index) async {
    if (index == 5) {
      await _openSettingsPage();
      return;
    }
    // 在普通主页面（0: 文件夹, 2: 曲库, 3: 队列, 4: 共享）之间切换时：
    // 原位直接 setState，无需销毁重建 MainLayout，使侧边 Rail / 底部 Dock 的胶囊平移动画流畅播放！
    if (_currentIndex != 1 && index != 1) {
      if (_currentIndex != 1) {
        ref.read(previousMainTabIndexProvider.notifier).setIndex(_currentIndex);
      }
      ref.read(mainTabIndexProvider.notifier).setIndex(index);
      _currentBaseTabIndex = index;
      Tooltip.dismissAllToolTips();
      setState(() {
        _currentIndex = index;
      });
      return;
    }

    // 涉及播放页（进入/退出播放页 index: 1）时，调用 navigateToMainTab 以执行上下平移路由转场动画
    if (_currentIndex != 1) {
      ref.read(previousMainTabIndexProvider.notifier).setIndex(_currentIndex);
    }
    ref.read(mainTabIndexProvider.notifier).setIndex(index);
    await navigateToMainTab(
      context,
      index: index,
      fromIndex: _currentIndex,
    );
  }

  Future<void> _openSettingsPage() async {
    if (Platform.isIOS || Platform.isMacOS) {
      await Navigator.of(
        context,
      ).push(CupertinoPageRoute<void>(builder: (_) => const SettingsPage()));
    } else {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
    }
  }

  Widget _buildCurrentPage(
    bool isDesktop,
    bool useSidebar,
    bool isCoverFlowImmersive,
  ) {
    final bool isPlayback = _currentIndex == 1;
    if (isPlayback) {
      return const PlaybackPage();
    }

    _visitedTabs.add(_currentIndex);
    // 窗口足够宽时左侧导航栏展开为图标 + 文字，否则收回为纯图标
    final double railWidth =
        useSidebar ? sidebarRailWidthFor(MediaQuery.of(context).size.width) : 0.0;
    final double leftPadding = railWidth;

    return IndexedStack(
      index: _currentIndex.clamp(0, 4),
      children: [
        _visitedTabs.contains(0)
            ? Padding(
                padding: EdgeInsets.only(top: 0, left: leftPadding),
                child: FoldersPage(
                  key: _foldersPageKey,
                  onOpenPlayback: () => _onDestinationSelected(1),
                ),
              )
            : const SizedBox.shrink(),
        const SizedBox.shrink(),
        _visitedTabs.contains(2)
            ? Padding(
                padding: const EdgeInsets.only(top: 0, left: 0),
                child: LibraryPage(
                  key: _libraryPageKey,
                  initialTabIndex: widget.initialLibraryTabIndex,
                  initialAlbums3DView: widget.initialAlbums3DView,
                  initialAlbums3DIndex: widget.initialAlbums3DIndex,
                  useSidebar: useSidebar,
                  railWidth: railWidth,
                ),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(3)
            ? Padding(
                padding: EdgeInsets.only(top: 0, left: leftPadding),
                child: const QueuePage(),
              )
            : const SizedBox.shrink(),
        _visitedTabs.contains(4)
            ? Padding(
                padding: EdgeInsets.only(top: isDesktop ? 32 : 0, left: leftPadding),
                child: const SharingPage(),
              )
            : const SizedBox.shrink(),
      ],
    );
  }


  Future<void> _triggerOnboardingFlow() async {
    if (_isOnboardingDialogOpen || !mounted) return;
    _isOnboardingDialogOpen = true;

    // Ensure all overlying routes (e.g. SettingsPage, dialogs) are closed and return to root
    final nav =
        navigatorKey.currentState ?? Navigator.of(context, rootNavigator: true);
    nav.popUntil((route) => route.isFirst);

    // Ensure we are on directory page (tab 0)
    if (_currentIndex != 0) {
      _isOnboardingDialogOpen = false;
      await _onDestinationSelected(0);
      return;
    }

    // Give a brief moment for directory page layout/transitions to settle
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) {
      _isOnboardingDialogOpen = false;
      return;
    }

    await MusicFoldersDialog.show(context, isOnboarding: true);

    if (!mounted) return;
    _isOnboardingDialogOpen = false;

    final settings = ref.read(settingsServiceProvider);
    settings.hasShownOnboarding = true;

    if (ref.read(trialResetNoticePendingProvider)) {
      _checkAndShowTrialResetNotice();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    // Listen for pending trial reset notice
    ref.listen<bool>(
      trialResetNoticePendingProvider,
      (previous, next) {
        if (next && !_isTrialResetNoticeDialogOpen && !_isOnboardingDialogOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _checkAndShowTrialResetNotice();
            }
          });
        }
      },
    );

    // Listen for onboarding status change (e.g. reset from settings)
    ref.listen<bool>(
      settingsServiceProvider.select((s) => s.hasShownOnboarding),
      (previous, next) {
        if (!next && !_isOnboardingDialogOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _triggerOnboardingFlow();
            }
          });
        }
      },
    );

    // Listen for small window mode transitions
    ref.listen<
      ({bool isSmallMode, SmallWindowBottomPanelMode bottomPanelMode})
    >(
      settingsServiceProvider.select(
        (s) => (
          isSmallMode: s.isSmallWindowMode,
          bottomPanelMode: s.smallWindowBottomPanelMode,
        ),
      ),
      (previous, next) async {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          final settings = ref.read(settingsServiceProvider);

          final nextSmallMode = next.isSmallMode;
          final prevSmallMode = previous?.isSmallMode ?? false;
          final nextExpanded =
              next.bottomPanelMode != SmallWindowBottomPanelMode.collapsed;
          final prevExpanded =
              previous?.bottomPanelMode != SmallWindowBottomPanelMode.collapsed;

          if (nextSmallMode != prevSmallMode || nextExpanded != prevExpanded) {
            _ignoreResizeEventsUntil = DateTime.now().add(
              const Duration(milliseconds: 800),
            );
          }

          debugPrint(
            '[vynody] transition listener: prevSmall=$prevSmallMode, nextSmall=$nextSmallMode, prevExpanded=$prevExpanded, nextExpanded=$nextExpanded',
          );
          if (nextSmallMode) {
            // Enter small window mode or update small window dimensions
            final isFullScreen = await windowManager.isFullScreen();
            final isMaximized = await windowManager.isMaximized();

            if (isFullScreen) {
              await windowManager.setFullScreen(false);
            }
            if (isMaximized) {
              await windowManager.unmaximize();
            }
            await windowManager.setAlwaysOnTop(
              settings.isSmallWindowAlwaysOnTop,
            );

            // Only save regular size if transitioning from regular mode to small window mode
            // AND only if the window was in a normal state (not maximized and not fullscreen)
            if (!prevSmallMode && !isFullScreen && !isMaximized) {
              final currentSize = await windowManager.getSize();
              debugPrint(
                '[vynody] transitioning from regular to small. currentSize=$currentSize',
              );
              if (currentSize.width >=
                      PlaybackPageUiTuning.smallWindowMaxSize.width ||
                  currentSize.height >=
                      PlaybackPageUiTuning.smallWindowMaxSize.height) {
                settings.savedRegularWindowSize = currentSize;
                debugPrint(
                  '[vynody] savedRegularWindowSize set to $currentSize',
                );
              }
            }

            if (nextExpanded) {
              // Expanded small-window bottom panel mode: resizable within constraints
              const minSize = Size(360.0, 450.0);
              const maxSize = Size(480.0, 99999.0);

              await windowManager.setMinimumSize(minSize);
              await windowManager.setMaximumSize(maxSize);

              // Only change size if we weren't already in expanded mode or small mode
              if (!prevExpanded || !prevSmallMode) {
                final savedSize = settings.savedSmallWindowQueueSize;
                final clampedSize = Size(
                  savedSize.width.clamp(minSize.width, maxSize.width),
                  savedSize.height.clamp(minSize.height, maxSize.height),
                );
                debugPrint(
                  '[vynody] setting size for expanded small mode: clampedSize=$clampedSize (savedSize=$savedSize)',
                );
                await windowManager.setSize(clampedSize);
              }
            } else {
              // Collapsed mode: resizable between 360x360 and 600x600
              const minSize = Size(360.0, 360.0);
              const maxSize = Size(600.0, 600.0);

              await windowManager.setMinimumSize(minSize);
              await windowManager.setMaximumSize(maxSize);

              // Only change size if transitioning from expanded mode back to collapsed, or entering small window mode
              if (prevExpanded || !prevSmallMode) {
                final savedSize = settings.savedSmallWindowSize;
                final clampedSize = Size(
                  savedSize.width.clamp(minSize.width, maxSize.width),
                  savedSize.height.clamp(minSize.height, maxSize.height),
                );
                debugPrint(
                  '[vynody] setting size for collapsed small mode: clampedSize=$clampedSize (savedSize=$savedSize)',
                );
                await windowManager.setSize(clampedSize);
              }
            }
          } else if (prevSmallMode && !nextSmallMode) {
            // Exit small window mode
            // Save the last small window size right before we exit
            final currentSmallSize = await windowManager.getSize();
            debugPrint(
              '[vynody] exiting small window mode. currentSmallSize=$currentSmallSize',
            );
            if (previous?.bottomPanelMode !=
                SmallWindowBottomPanelMode.collapsed) {
              settings.savedSmallWindowQueueSize = currentSmallSize;
              debugPrint(
                '[vynody] exiting: savedSmallWindowQueueSize saved as $currentSmallSize',
              );
            } else {
              settings.savedSmallWindowSize = currentSmallSize;
              debugPrint(
                '[vynody] exiting: savedSmallWindowSize saved as $currentSmallSize',
              );
            }

            final isDrawerOpen = ref.read(rightQueueDrawerProvider);
            await windowManager.setMinimumSize(
              isDrawerOpen
                  ? kDrawerOpenMinWindowSize
                  : kDefaultRegularMinWindowSize,
            );
            await windowManager.setMaximumSize(const Size(99999, 99999));
            final savedSize = settings.savedRegularWindowSize;
            debugPrint(
              '[vynody] restoring regular window size: savedSize=$savedSize',
            );
            await windowManager.setSize(savedSize);
            await windowManager.setAlwaysOnTop(false);
            if (settings.isRegularWindowMaximized) {
              await windowManager.maximize();
            }
          }
        }
      },
    );

    // Listen for incoming LAN file transfers
    ref.listen<IncomingTransferRequest?>(incomingRequestProvider, (
      previous,
      next,
    ) {
      if (next != null) {
        showIncomingTransferDialog(context, next);
      }
    });

    // Listen for incoming LAN lyrics requests
    ref.listen<IncomingLyricsRequest?>(incomingLyricsRequestProvider, (
      previous,
      next,
    ) {
      if (next != null) {
        showIncomingLyricsDialog(context, next);
      }
    });

    // Listen for incoming LAN playlist requests
    ref.listen<IncomingPlaylistRequest?>(incomingPlaylistRequestProvider, (
      previous,
      next,
    ) {
      if (next != null) {
        showIncomingPlaylistDialog(context, next);
      }
    });

    // Listen for incoming playlist received completion
    ref.listen<int?>(incomingPlaylistReceivedProvider, (
      previous,
      next,
    ) {
      if (next != null) {
        AppSnackBar.show(
          context,
          ref,
          SnackBar(
            content: Text(l10n.receivePlaylistsSuccess(next)),
          ),
        );
        ref.read(incomingPlaylistReceivedProvider.notifier).clear();
      }
    });

    // Listen for incoming remote control pair requests
    ref.listen<IncomingRemotePairRequest?>(incomingRemotePairProvider, (
      previous,
      next,
    ) {
      if (next != null) {
        showIncomingRemotePairDialog(context, next);
      }
    });


    // Listen for sharing warnings
    ref.listen<String?>(sharingWarningProvider, (previous, next) {
      if (next != null) {
        AppSnackBar.show(
          context,
          ref,
          SnackBar(
            content: Text(next),
            action: SnackBarAction(
              label: l10n.goToSettings,
              onPressed: () {
                _onDestinationSelected(4);
              },
            ),
          ),
        );
        ref.read(sharingWarningProvider.notifier).setWarning(null);
      }
    });

    // Listen for transfer session updates to show progress dialogs and completion notifications
    ref.listen<List<TransferSession>>(activeTransfersProvider, (
      previous,
      next,
    ) {
      // 1. Globally show progress dialog for incoming receiving sessions
      for (final session in next) {
        if (!session.isSending &&
            (session.status == TransferStatus.transferring ||
                session.status == TransferStatus.pending)) {
          final wasTransferring = previous != null &&
              previous.any((s) =>
                  s.id == session.id &&
                  (s.status == TransferStatus.transferring ||
                      s.status == TransferStatus.pending));
          if (!wasTransferring) {
            showTransferProgressDialog(context, session.id);
          }
        }
      }

      if (previous == null) return;

      // 2. Show completion/failure SnackBar for finished sessions
      for (final session in next) {
        // We only care about receiving files
        if (session.isSending) continue;

        // Check the previous state of this session
        final prevList = previous.where((s) => s.id == session.id).toList();
        final prevSession = prevList.isNotEmpty ? prevList.first : null;

        // If it was already finished in the previous state, don't show the SnackBar again
        final wasFinished =
            prevSession != null &&
            (prevSession.status == TransferStatus.success ||
                prevSession.status == TransferStatus.failed ||
                prevSession.status == TransferStatus.cancelled);

        if (wasFinished) continue;

        // Check if the session has transitioned to a finished state
        final isFinished =
            session.status == TransferStatus.success ||
            session.status == TransferStatus.failed ||
            session.status == TransferStatus.cancelled;

        if (isFinished) {
          // If the progress dialog was shown, the dialog itself already displayed the SnackBar on dismiss
          if (hasShownTransferProgressDialog(session.id)) {
            continue;
          }

          final isSuccess = session.status == TransferStatus.success;
          final text = isSuccess
              ? l10n.receiveCompleted(session.completedFilesCount ?? session.filesCount ?? 1)
              : l10n.receiveFailed(session.fileName);

          AppSnackBar.show(context, ref, SnackBar(content: Text(text)));
        }
      }
    });

    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final selectionScope = ref.watch(librarySelectionScopeProvider);
    final hideMiniPlayerForSelection =
        selectionScope != LibrarySelectionScope.none;
    final isRootSelectionMode =
        selectionScope == LibrarySelectionScope.folderRoot;
    final isPlaylistSelectionMode =
        selectionScope == LibrarySelectionScope.playlist;
    final isQueueSelectionMode = selectionScope == LibrarySelectionScope.queue;
    ref.listen<double>(audioVolumeProvider, (previous, next) {
      if (!mounted) return;
      final volumeChanged =
          _lastVolume != null && (_lastVolume! - next).abs() > 0.1;
      if (volumeChanged &&
          _audioService.shouldShowVolumeHudForLastVolumeChange) {
        _ui.setVolumeHudVisible(true);
      }
      _lastVolume = next;
    });

    ref.listen<bool>(isProUnlockedProvider, (previous, isUnlocked) {
      if (previous == isUnlocked) return;
      final serverState = ref.read(sharingServerStateProvider);
      final lanEnabled = ref.read(settingsServiceProvider).lanSharingEnabled;
      if (!isUnlocked) {
        if (serverState.isRunning) {
          ref.read(sharingServerStateProvider.notifier).stop();
        }
        final audio = ref.read(audioServiceProvider);
        unawaited(audio.setPlaybackSpeed(1.0));
      } else if (lanEnabled && !serverState.isRunning) {
        ref.read(sharingServerStateProvider.notifier).start();
      }
    });

    final settings = ref.watch(settingsServiceProvider);
    final theme = Theme.of(context);
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final bool showCustomTitleBar =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final bool isPlayback = _currentIndex == 1;
    final navBgBaseColor =
        theme.navigationBarTheme.backgroundColor ?? theme.colorScheme.surface;
    final navIndicatorBaseColor =
        theme.navigationBarTheme.indicatorColor ??
        theme.colorScheme.secondaryContainer;
    final navBgOpacityTarget = isPlayback ? 0.0 : 1.0;

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
    final bool isLandscape =
        !isSmallWin && (effectiveWidth > size.height);
    final bool isCoverFlowImmersive =
        isLandscape &&
        ref.watch(isCoverFlowImmersiveActiveProvider);
    final bool useSidebar = isLandscape;
    final bool isSidebarHidden =
        (isLandscape && isPlayback) ||
        isCoverFlowImmersive;
    final bool hideImmersiveTabBar = isSidebarHidden;
    final bool isKeyboardVisible =
        MediaQuery.of(context).viewInsets.bottom > 0;
    final bool hideBottomBar =
        (isPlayback && isSmallWin) ||
        isCoverFlowImmersive ||
        isKeyboardVisible;

    final double railWidth =
        (useSidebar && !isSidebarHidden) ? sidebarRailWidthFor(size.width) : 0.0;

    final mainAppWidget = Focus(
      autofocus: true,
      child: PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              _handleBackPressed();
            },
            child: Listener(
              behavior: HitTestBehavior.translucent,
                onPointerDown: _handleDesktopPointerActivity,
                onPointerMove: _handleDesktopPointerActivity,
                onPointerHover: _handleDesktopPointerActivity,
                child: Scaffold(
                  resizeToAvoidBottomInset: false,
                  extendBody: true,
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: Row(
                          children: [
                            Expanded(
                              child: GlobalDropTarget(
                                enable:
                                    _currentIndex != 3 &&
                                    !(_currentIndex == 1 &&
                                        isSmallWin &&
                                        settings.smallWindowBottomPanelMode !=
                                            SmallWindowBottomPanelMode.collapsed),
                                child: _buildCurrentPage(
                                  isDesktop,
                                  useSidebar,
                                  isCoverFlowImmersive,
                                ),
                              ),
                            ),
                            if (isDesktop && !isSmallWin)
                              ClipRect(
                                child: AnimatedSize(
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.centerRight,
                                  child: ref.watch(rightQueueDrawerProvider)
                                      ? const RightQueuePanel()
                                      : const SizedBox.shrink(),
                                ),
                              ),
                          ],
                        ),
                      ),
                        if (useSidebar)
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: SizedBox(
                              width: railWidth,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                opacity: hideImmersiveTabBar ? 0.0 : 1.0,
                                child: IgnorePointer(
                                  ignoring: hideImmersiveTabBar,
                                  child: TweenAnimationBuilder<double>(
                                    duration: const Duration(milliseconds: 120),
                                    curve: Curves.easeOut,
                                    tween: Tween<double>(
                                      begin: navBgOpacityTarget,
                                      end: navBgOpacityTarget,
                                    ),
                                    builder: (context, animatedOpacity, child) {
                                      return _SlidingNavigationRail(
                                        backgroundColor: Color.lerp(
                                              navBgBaseColor.withValues(alpha: 0.0),
                                              navBgBaseColor,
                                              animatedOpacity,
                                            ) ??
                                            navBgBaseColor,
                                        width: railWidth,
                                        extended:
                                            railWidth >= kSidebarRailWidthExtended,
                                        selectedIndex: _currentIndex,
                                        onDestinationSelected: (index) {
                                          if (index == 1) {
                                            ref.read(settingsServiceProvider).resetInactivity();
                                          }
                                          _onDestinationSelected(index);
                                        },
                                        // 媒体库（index 2）激活时，在 Rail 内展开其六个子页面入口
                                        isLibraryExpanded: _currentIndex == 2,
                                        librarySubIndex: ref.watch(
                                          libraryActiveTabIndexProvider,
                                        ),
                                        onLibrarySubDestinationSelected: (
                                          subIndex,
                                        ) {
                                          Tooltip.dismissAllToolTips();
                                          ref
                                              .read(
                                                librarySelectionScopeProvider
                                                    .notifier,
                                              )
                                              .clear();
                                          ref
                                              .read(
                                                libraryActiveTabIndexProvider
                                                    .notifier,
                                              )
                                              .set(subIndex);
                                          if (_currentIndex != 2) {
                                            _onDestinationSelected(2);
                                          }
                                        },
                                        indicatorColor: Color.lerp(
                                              navIndicatorBaseColor.withValues(
                                                alpha: 0.0,
                                              ),
                                              navIndicatorBaseColor,
                                              animatedOpacity,
                                            ) ??
                                            navIndicatorBaseColor,
                                        isPlayback: isPlayback,
                                        isSettingsActive: ref.watch(
                                          isSettingsPageActiveProvider,
                                        ),
                                      );
                                    },
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
                              brightness: (isPlayback &&
                                      !ref.watch(rightQueueDrawerProvider))
                                  ? Brightness.dark
                                  : theme.brightness,
                              showSmallWindowButton: isPlayback,
                              showButtonGroupBackground: isPlayback &&
                                  !ref.watch(rightQueueDrawerProvider),
                              hideButtonsWhenInactive: isPlayback &&
                                  !ref.watch(rightQueueDrawerProvider),
                              isPlayback: isPlayback,
                              onCollapsePlayback: _collapsePlayback,
                            ),
                          ),
                        if (!showCustomTitleBar && isPlayback)
                          Positioned(
                            top: MediaQuery.paddingOf(context).top + 8,
                            left: math.max(16.0, MediaQuery.paddingOf(context).left + 8),
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 200),
                              opacity: settings.isUserInactive ? 0.0 : 1.0,
                              curve: Curves.easeInOut,
                              child: IgnorePointer(
                                ignoring: settings.isUserInactive,
                                child: _buildMobilePlaybackCollapseButton(context),
                              ),
                            ),
                          ),
                      if (useSidebar)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          bottom:
                              (!isPlayback &&
                                  currentMusic != null &&
                                  !hideMiniPlayerForSelection &&
                                  !isCoverFlowImmersive &&
                                  !isKeyboardVisible)
                                  ? (20.0 +
                                    MediaQuery.of(context).padding.bottom +
                                    (((isRootSelectionMode &&
                                                _currentIndex == 0) ||
                                            (isPlaylistSelectionMode &&
                                                _currentIndex == 2) ||
                                            (isQueueSelectionMode &&
                                                _currentIndex == 3))
                                        ? 80.0
                                        : 0.0))
                              : -120.0,
                          left: railWidth,
                          right: (isDesktop &&
                                  !isSmallWin &&
                                  ref.watch(rightQueueDrawerProvider))
                              ? kRightQueueDrawerWidth
                              : 0.0,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            opacity: isCoverFlowImmersive ? 0.0 : 1.0,
                            child: IgnorePointer(
                              ignoring: isCoverFlowImmersive,
                              child: Center(
                                child: !isPlayback && currentMusic != null
                                    ? Builder(
                                        builder: (context) {
                                          final audio = ref.read(
                                            audioServiceProvider,
                                          );
                                          final availableWidth =
                                              MediaQuery.of(context).size.width -
                                              railWidth -
                                              ((isDesktop &&
                                                      !isSmallWin &&
                                                      ref.watch(rightQueueDrawerProvider))
                                                  ? kRightQueueDrawerWidth
                                                  : 0.0);

                                          return Container(
                                            key: const ValueKey('dynamic-island'),
                                            constraints: BoxConstraints(
                                              maxWidth: availableWidth * 0.9,
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
                                                        (audio
                                                                    .duration
                                                                    .inMilliseconds *
                                                                val)
                                                            .toInt(),
                                                  ),
                                                );
                                              },
                                              onVolumeTap: () {
                                                ref
                                                    .read(settingsServiceProvider)
                                                    .resetInactivity();
                                                final nextVisible =
                                                    !_showMiniVolumeSlider;
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
                                                _ui.setVolumeHudVisible(true);
                                                audio.setVolume(
                                                  value.roundToDouble(),
                                                );
                                              },
                                              onVolumeScroll: (deltaY) {
                                                ref
                                                    .read(settingsServiceProvider)
                                                    .resetInactivity();
                                                _ui.setVolumeHudVisible(true);
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
                                    : const SizedBox.shrink(
                                        key: ValueKey('empty-island'),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      if (!useSidebar)
                        FloatingDockBottomBar(
                          currentIndex: _currentIndex,
                          onDestinationSelected: _onDestinationSelected,
                          isPlayback: isPlayback,
                          isHidden:
                              hideBottomBar ||
                              hideMiniPlayerForSelection ||
                              (isPlayback &&
                                  settings.isImmersiveTabBarEnabled &&
                                  settings.isUserInactive),
                          hideMiniPlayer:
                              hideMiniPlayerForSelection ||
                              isCoverFlowImmersive,
                          rightDrawerWidth: (isDesktop &&
                                  !isSmallWin &&
                                  ref.watch(rightQueueDrawerProvider))
                              ? kRightQueueDrawerWidth
                              : 0.0,
                          additionalBottomOffset:
                              (((isRootSelectionMode && _currentIndex == 0) ||
                                      (isPlaylistSelectionMode &&
                                          _currentIndex == 2) ||
                                      (isQueueSelectionMode &&
                                          _currentIndex == 3))
                                  ? 80.0
                                  : 0.0),
                        ),
                    ],
                  ),
                  bottomNavigationBar: null,
                ),
              ),
            ),
        );

    return mainAppWidget;
  }

  Widget _buildMobilePlaybackCollapseButton(BuildContext context) {
    if (Platform.isIOS) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 36,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 0.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _collapsePlayback,
                child: const Center(
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: IconButton(
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Colors.white,
          size: 26,
        ),
        tooltip: Localizations.maybeLocaleOf(context)?.languageCode == 'zh'
            ? '收起播放页'
            : 'Collapse Playback',
        onPressed: _collapsePlayback,
      ),
    );
  }
}

/// 左侧导航栏单行条目的布局描述（高度 + 内容），用于逐行累加计算胶囊指示器的 Y 偏移
class _RailRow {
  const _RailRow({required this.height, required this.child});

  final double height;
  final Widget child;
}

class _SlidingNavigationRail extends StatefulWidget {
  final double width;
  final bool extended;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Color backgroundColor;
  final Color indicatorColor;
  final bool isPlayback;
  final bool isSettingsActive;
  final bool isLibraryExpanded;
  final int librarySubIndex;
  final ValueChanged<int> onLibrarySubDestinationSelected;

  const _SlidingNavigationRail({
    required this.width,
    required this.extended,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.backgroundColor,
    required this.indicatorColor,
    required this.isPlayback,
    required this.isSettingsActive,
    required this.isLibraryExpanded,
    required this.librarySubIndex,
    required this.onLibrarySubDestinationSelected,
  });

  @override
  State<_SlidingNavigationRail> createState() => _SlidingNavigationRailState();
}

class _SlidingNavigationRailState extends State<_SlidingNavigationRail> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    final destinations = [
      (
        index: 0,
        label: l10n.file,
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
      ),
      (
        index: 1,
        label: l10n.play,
        icon: Icons.play_circle_outline,
        selectedIcon: Icons.play_circle,
      ),
      (
        index: 2,
        label: l10n.list,
        icon: Icons.playlist_play_outlined,
        selectedIcon: Icons.playlist_play,
      ),
      (
        index: 3,
        label: l10n.queueTab,
        icon: Icons.queue_music_outlined,
        selectedIcon: Icons.queue_music,
      ),
      (
        index: 4,
        label: l10n.share,
        icon: Icons.share_outlined,
        selectedIcon: Icons.share,
      ),
      (
        index: 5,
        label: l10n.settings,
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
      ),
    ];

    // 媒体库（index 2）的二级入口，顺序与 libraryActiveTabIndexProvider 一致
    final librarySubDestinations = [
      (
        label: l10n.playlist,
        icon: Icons.queue_music_rounded,
        selectedIcon: Icons.queue_music_rounded,
      ),
      (
        label: l10n.recentlyPlayed,
        icon: Icons.history_rounded,
        selectedIcon: Icons.history_rounded,
      ),
      (
        label: l10n.mostPlayed,
        icon: Icons.local_fire_department_rounded,
        selectedIcon: Icons.local_fire_department_rounded,
      ),
      (
        label: l10n.recentlyAdded,
        icon: Icons.auto_awesome_rounded,
        selectedIcon: Icons.auto_awesome_rounded,
      ),
      (
        label: l10n.albums,
        icon: Icons.album_rounded,
        selectedIcon: Icons.album_rounded,
      ),
      (
        label: l10n.artists,
        icon: Icons.mic_external_on_rounded,
        selectedIcon: Icons.mic_external_on_rounded,
      ),
    ];

    const double itemHeight = 48.0;
    const double subItemHeight = 44.0;

    final double leadingHeight = Platform.isIOS ? 56.0 : 32.0;
    final double topInset =
        math.max(leadingHeight, MediaQuery.paddingOf(context).top);

    final activeColor = widget.isPlayback
        ? Colors.white
        : theme.colorScheme.primary;
    final inactiveColor = widget.isPlayback
        ? Colors.white.withValues(alpha: 0.80)
        : theme.colorScheme.onSurfaceVariant;

    final int activeMainIndex = widget.selectedIndex.clamp(
      0,
      destinations.length - 1,
    );
    final int activeSubIndex = widget.librarySubIndex.clamp(
      0,
      librarySubDestinations.length - 1,
    );

    // 设置页固定钉在左下角，其余条目（含媒体库展开的二级入口）放进可滚动区
    final rows = <_RailRow>[];
    int pillRow = -1;

    for (int i = 0; i < destinations.length - 1; i++) {
      final d = destinations[i];
      if (d.index == activeMainIndex && !widget.isSettingsActive) {
        pillRow = rows.length;
      }
      rows.add(
        _RailRow(
          height: itemHeight,
          child: _buildTile(
            icon: d.icon,
            selectedIcon: d.selectedIcon,
            label: d.label,
            isSelected: d.index == activeMainIndex && !widget.isSettingsActive,
            isSubItem: false,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            onTap: () => widget.onDestinationSelected(d.index),
          ),
        ),
      );

      if (d.index == 2 && widget.isLibraryExpanded) {
        for (int s = 0; s < librarySubDestinations.length; s++) {
          final sub = librarySubDestinations[s];
          if (d.index == activeMainIndex &&
              !widget.isSettingsActive &&
              s == activeSubIndex) {
            pillRow = rows.length;
          }
          rows.add(
            _RailRow(
              height: subItemHeight,
              child: _buildTile(
                icon: sub.icon,
                selectedIcon: sub.selectedIcon,
                label: sub.label,
                isSelected:
                    d.index == activeMainIndex &&
                    !widget.isSettingsActive &&
                    s == activeSubIndex,
                isSubItem: true,
                activeColor: activeColor,
                inactiveColor: inactiveColor,
                onTap: () => widget.onLibrarySubDestinationSelected(s),
              ),
            ),
          );
        }
      }
    }

    double offsetOf(int rowIndex) {
      double offset = 0.0;
      for (int i = 0; i < rowIndex && i < rows.length; i++) {
        offset += rows[i].height;
      }
      return offset;
    }

    final double contentHeight = offsetOf(rows.length);
    final bool showPill = pillRow >= 0;
    final double pillWidth = widget.extended ? widget.width - 16.0 : 56.0;
    final double pillLeft = widget.extended ? 8.0 : (widget.width - pillWidth) / 2.0;
    final double pillHeight = showPill
        ? math.max(32.0, rows[pillRow].height - 8.0)
        : 32.0;
    final double pillTop = showPill
        ? offsetOf(pillRow) + (rows[pillRow].height - pillHeight) / 2.0
        : 0.0;

    return Container(
      width: widget.width,
      color: widget.backgroundColor,
      child: Column(
        children: [
          SizedBox(height: topInset),

          // 可滚动区：窗口高度不足时（媒体库展开后条目变多）可上下滚动
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SizedBox(
                  width: widget.width,
                  height: contentHeight,
                  child: Stack(
                    children: [
                      // 1. 纵向平移滑动的胶囊指示器
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        left: pillLeft,
                        top: pillTop,
                        width: pillWidth,
                        height: pillHeight,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            opacity: showPill ? 1.0 : 0.0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: widget.indicatorColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // 2. 各条目按累加偏移定位，胶囊可精确对齐任意分组中的条目
                      for (int i = 0; i < rows.length; i++)
                        Positioned(
                          top: offsetOf(i),
                          left: 0,
                          right: 0,
                          height: rows[i].height,
                          child: rows[i].child,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 分割线：把常驻的设置入口与上方的页面导航区分开
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Container(
              height: 0.5,
              color: theme.dividerColor.withValues(alpha: 0.35),
            ),
          ),

          // 设置页常驻左下角，不随上方条目滚动
          SizedBox(
            height: itemHeight,
            child: _buildTile(
              icon: destinations.last.icon,
              selectedIcon: destinations.last.selectedIcon,
              label: destinations.last.label,
              isSelected: widget.isSettingsActive,
              isSubItem: false,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              onTap: () => widget.onDestinationSelected(destinations.last.index),
            ),
          ),
          SizedBox(
            height: math.max(10.0, MediaQuery.paddingOf(context).bottom),
          ),
        ],
      ),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    required bool isSelected,
    required bool isSubItem,
    required Color activeColor,
    required Color inactiveColor,
    required VoidCallback onTap,
  }) {
    final Color color = isSelected ? activeColor : inactiveColor;
    final double iconSize = isSubItem ? 19.0 : 22.0;

    final Widget content;
    if (widget.extended) {
      content = Padding(
        padding: EdgeInsets.only(left: isSubItem ? 30.0 : 16.0, right: 12.0),
        child: Row(
          children: [
            Icon(isSelected ? selectedIcon : icon, size: iconSize, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isSubItem ? 13.0 : 14.0,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      content = Center(
        child: Icon(isSelected ? selectedIcon : icon, size: iconSize, color: color),
      );
    }

    Widget tile = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: SizedBox.expand(child: content),
      ),
    );

    tile = MouseRegion(cursor: SystemMouseCursors.click, child: tile);

    // 展开态已有文字标签，无需再依赖悬浮提示
    if (!widget.extended) {
      tile = AppTooltip(message: label, child: tile);
    }
    return tile;
  }
}
