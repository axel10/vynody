import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'player/audio_service.dart';
import 'player/scanner_service.dart';
import 'player/playlist_service.dart';
import 'player/settings_service.dart';
import 'pages/folder_page.dart';
import 'pages/playback_page.dart';
import 'pages/playlist_page.dart';
import 'pages/settings_page.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 720),
      minimumSize: Size(400, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Pure Player',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    MetadataGod.initialize();
  }

  final settingsService = await SettingsService.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ScannerService()),
        ChangeNotifierProvider(create: (_) => PlaylistService()),
        ChangeNotifierProvider.value(value: settingsService),
      ],
      child: MyApp(args: args),
    ),
  );
}

class MyApp extends StatelessWidget {
  final List<String> args;
  const MyApp({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    const fontFallbacks = [
      'MiSans',
      'HarmonyOS Sans SC',
      'OPPOSans',
      'VivoSans',
      'OnePlus Sans',
      'SamsungOne',
      'PingFang SC',
      'Heiti SC',
      'Microsoft YaHei',
      'sans-serif',
    ];

    return MaterialApp(
      title: 'Pure Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'MiSans',
        fontFamilyFallback: fontFallbacks,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamilyFallback: fontFallbacks,
      ),
      home: MainLayout(args: args),
    );
  }
}

class MainLayout extends StatefulWidget {
  final List<String> args;
  const MainLayout({super.key, required this.args});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);

    // Handle command line arguments on Windows
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleArgs();
      });
    }
  }

  Future<void> _handleArgs() async {
    final args = widget.args;
    // On Windows, the first argument is often the executable itself,
    // but when opening a file, it might be the second.
    // However, Flutter's Platform.executableArguments might behave differently.
    // Actually, WindowManager or another package might be better for "open with",
    // but let's try reading args directly.

    final audio = context.read<AudioService>();
    final List<String> audioExtensions = [
      '.mp3',
      '.m4a',
      '.wav',
      '.flac',
      '.ogg',
    ];

    for (var arg in args) {
      if (File(arg).existsSync()) {
        final ext = p.extension(arg).toLowerCase();
        if (audioExtensions.contains(ext)) {
          audio.playFile(arg, p.basename(arg));
          _onDestinationSelected(1); // Go to playback page
          break; // Only play the first one for now as per requirement "playlist only contain that music file"
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (mounted) {
      setState(() {
        _currentIndex = index;
      });
    }
  }

  void _onDestinationSelected(int index) {
    if (index == 3) {
      _showMoreMenu();
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showMoreMenu() {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        size.width,
        offset.dy + size.height - 100, // Positioned near bottom
        0,
        0,
      ),
      items: [
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(leading: Icon(Icons.settings), title: Text('设置')),
        ),
      ],
    ).then((value) {
      if (value == 'settings') {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsPage()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    final List<Widget> pages = [
      Padding(
        padding: EdgeInsets.only(top: isDesktop ? 32 : 0),
        child: const FoldersPage(),
      ),
      const PlaybackPage(),
      Padding(
        padding: EdgeInsets.only(top: isDesktop ? 32 : 0),
        child: const PlaylistPage(),
      ),
    ];

    final bool isPlayback = _currentIndex == 1;

    return ListenableProvider<PageController>.value(
      value: _pageController,
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              children: pages,
            ),
            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
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
                              : Theme.of(context).brightness,
                          backgroundColor: Colors.transparent,
                          title: const SizedBox(),
                        ),
                      ),
                    ),
                  ],
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
          child: NavigationBar(
            height: 60,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            selectedIndex: _currentIndex,
            backgroundColor: isPlayback ? Colors.transparent : null,
            elevation: 0,
            indicatorColor: isPlayback ? Colors.transparent : null,
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
                label: '文件',
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
                label: '播放',
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
                label: '列表',
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
            ],
          ),
        ),
      ),
    );
  }
}
