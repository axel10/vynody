import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:provider/provider.dart' as legacy_provider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'l10n/app_localizations.dart';
import 'pages/main_layout.dart';
import 'player/audio_riverpod.dart';
import 'player/audio_service.dart';
import 'player/lyrics_riverpod.dart';
import 'player/playlist_service.dart';
import 'player/scanner_service.dart';
import 'player/settings_service.dart';
import 'package:smtc_windows/smtc_windows.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 处理从外部（如双击、命令行）打开的文件列表
/// [args] 是外部传入的路径参数列表
void handleFileOpen(List<String> args) {
  if (args.isEmpty) return;
  final context = navigatorKey.currentContext; // 获取全局导航上下文以访问 Provider
  if (context == null) return;

  final audio = legacy_provider.Provider.of<AudioService>(
    context,
    listen: false,
  );
  // 支持的音频格式列表
  final List<String> audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  for (var arg in args) {
    // 处理路径中可能的双引号和两端空格
    final path = arg.replaceAll('"', '').trim();
    if (path.isEmpty) continue;

    // 检查文件是否存在
    if (File(path).existsSync()) {
      final ext = p.extension(path).toLowerCase();
      // 如果是支持的音频文件
      if (audioExtensions.contains(ext)) {
        // 将文件添加到播放队列并开始播放
        // append: true 表示将其添加到队列末尾并切换到该歌曲播放
        audio.playFile(path, p.basename(path), append: true);

        // 自动跳转到播放详情界面（索引为1的 Tab）
        navigateToMainTab(context, index: 1);

        // 逻辑：匹配到第一个支持的文件即处理并跳出，避免一次打开大量文件导致界面混乱
        break;
      }
    }
  }
}

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await WindowsSingleInstance.ensureSingleInstance(
      args,
      "custom_identifier",
      onSecondWindow: (args) {
        handleFileOpen(args);
      },
    );
  }

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

  if (Platform.isWindows) {
    await SMTCWindows.initialize();
  }

  final settingsService = await SettingsService.init();

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWithValue(settingsService),
      ],
      child: _LegacyProviderBridge(
        settingsService: settingsService,
        child: MyApp(args: args),
      ),
    ),
  );
}

class _LegacyProviderBridge extends ConsumerStatefulWidget {
  const _LegacyProviderBridge({
    required this.settingsService,
    required this.child,
  });

  final SettingsService settingsService;
  final Widget child;

  @override
  ConsumerState<_LegacyProviderBridge> createState() =>
      _LegacyProviderBridgeState();
}

class _LegacyProviderBridgeState extends ConsumerState<_LegacyProviderBridge> {
  AudioService? _attachedAudio;
  bool _attachScheduled = false;

  void _scheduleLyricsBridge(AudioService audio) {
    if (_attachScheduled || identical(_attachedAudio, audio)) {
      return;
    }

    _attachScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachScheduled = false;
      if (!mounted) return;

      audio.attachLyricsControllerAccess(
        readController: () => ref.read(lyricsControllerProvider.notifier),
        readState: () => ref.read(lyricsControllerProvider),
      );
      _attachedAudio = audio;
    });
  }

  @override
  Widget build(BuildContext context) {
    final audio = ref.read(audioServiceProvider);
    _scheduleLyricsBridge(audio);

    return legacy_provider.MultiProvider(
      providers: [
        legacy_provider.ChangeNotifierProvider<AudioService>.value(
          value: audio,
        ),
        legacy_provider.ChangeNotifierProxyProvider<AudioService, ScannerService>(
          create: (_) => ScannerService(),
          update: (_, audio, scanner) {
            scanner!.setPlayerController(audio.playbackController);
            audio.setScannerService(scanner);
            return scanner;
          },
        ),
        legacy_provider.ChangeNotifierProvider(create: (_) => PlaylistService()),
        legacy_provider.ChangeNotifierProvider.value(
          value: widget.settingsService,
        ),
      ],
      child: widget.child,
    );
  }
}

class MyApp extends StatelessWidget {
  final List<String> args;
  const MyApp({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    const fontFallbacks = [
      'SourceHanSansCN',
      'MiSans',
      'Meiryo',
      'Yu Gothic',
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
        fontFamily: 'SourceHanSansCN',
        fontFamilyFallback: fontFallbacks,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'SourceHanSansCN',
        fontFamilyFallback: fontFallbacks,
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('zh')],
      home: MainLayout(args: args),
      navigatorKey: navigatorKey,
    );
  }
}
