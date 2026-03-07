import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:metadata_god/metadata_god.dart';
import 'package:provider/provider.dart';
import 'player/audio_service.dart';
import 'player/scanner_service.dart';
import 'pages/folder_page.dart';
import 'pages/playback_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux) {
    MetadataGod.initialize();
  }
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioService()),
        ChangeNotifierProvider(create: (_) => ScannerService()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

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
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [const FoldersPage(), const PlaybackPage()];

    return ListenableProvider<PageController>.value(
      value: _pageController,
      child: Scaffold(
        extendBody: true,
        body: PageView(
          controller: _pageController,
          onPageChanged: _onPageChanged,
          children: pages,
        ),
        bottomNavigationBar: NavigationBar(
          height: 60,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          selectedIndex: _currentIndex,
          backgroundColor: _currentIndex == 1 ? Colors.transparent : null,
          elevation: 0,
          indicatorColor: _currentIndex == 1 ? Colors.transparent : null,
          onDestinationSelected: _onDestinationSelected,
          destinations: [
            NavigationDestination(
              icon: Icon(
                Icons.folder_outlined,
                color: _currentIndex == 1 ? Colors.white70 : null,
              ),
              selectedIcon: Icon(
                Icons.folder,
                color: _currentIndex == 1 ? Colors.white : null,
              ),
              label: '文件',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.play_circle_outline,
                color: _currentIndex == 1 ? Colors.white70 : null,
              ),
              selectedIcon: Icon(
                Icons.play_circle,
                color: _currentIndex == 1 ? Colors.white : null,
              ),
              label: '播放',
            ),
          ],
        ),
      ),
    );
  }
}
