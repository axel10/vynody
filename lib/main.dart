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

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return const DefaultTabController(length: 2, child: _MainLayoutContent());
  }
}

class _MainLayoutContent extends StatefulWidget {
  const _MainLayoutContent();

  @override
  State<_MainLayoutContent> createState() => _MainLayoutContentState();
}

class _MainLayoutContentState extends State<_MainLayoutContent> {
  TabController? _tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newController = DefaultTabController.of(context);
    if (_tabController != newController) {
      _tabController?.removeListener(_handleTabSelection);
      _tabController = newController;
      _tabController?.addListener(_handleTabSelection);
    }
  }

  void _handleTabSelection() {
    if (_tabController!.indexIsChanging ||
        _tabController!.index != _tabController!.previousIndex) {
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabSelection);
    super.dispose();
  }

  final List<Widget> _pages = [const FoldersPage(), const PlaybackPage()];

  @override
  Widget build(BuildContext context) {
    final currentIndex = _tabController?.index ?? 0;

    return Scaffold(
      extendBody: true,
      body: TabBarView(children: _pages),
      bottomNavigationBar: NavigationBar(
        height: 60,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: currentIndex,
        backgroundColor: currentIndex == 1 ? Colors.transparent : null,
        elevation: 0,
        indicatorColor: currentIndex == 1 ? Colors.transparent : null,
        onDestinationSelected: (index) {
          _tabController?.animateTo(index);
        },
        destinations: [
          NavigationDestination(
            icon: Icon(
              Icons.folder_outlined,
              color: currentIndex == 1 ? Colors.white70 : null,
            ),
            selectedIcon: Icon(
              Icons.folder,
              color: currentIndex == 1 ? Colors.white : null,
            ),
            label: '文件',
          ),
          NavigationDestination(
            icon: Icon(
              Icons.play_circle_outline,
              color: currentIndex == 1 ? Colors.white70 : null,
            ),
            selectedIcon: Icon(
              Icons.play_circle,
              color: currentIndex == 1 ? Colors.white : null,
            ),
            label: '播放',
          ),
        ],
      ),
    );
  }
}
