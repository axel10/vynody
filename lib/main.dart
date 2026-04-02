import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'l10n/app_localizations.dart';
import 'pages/main_layout.dart';
import 'player/audio_service.dart';
import 'player/playlist_service.dart';
import 'player/scanner_service.dart';
import 'player/settings_service.dart';
import 'package:smtc_windows/smtc_windows.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void handleFileOpen(List<String> args) {
  if (args.isEmpty) return;
  final context = navigatorKey.currentContext;
  if (context == null) return;

  final audio = context.read<AudioService>();
  final List<String> audioExtensions = [
    '.mp3',
    '.m4a',
    '.wav',
    '.flac',
    '.ogg',
  ];

  for (var arg in args) {
    final path = arg.replaceAll('"', '').trim();
    if (path.isEmpty) continue;
    if (File(path).existsSync()) {
      final ext = p.extension(path).toLowerCase();
      if (audioExtensions.contains(ext)) {
        audio.playFile(path, p.basename(path), append: true);
        navigateToMainTab(context, index: 1);
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
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AudioService(settingsService)),
        ChangeNotifierProxyProvider<AudioService, ScannerService>(
          create: (_) => ScannerService(),
          update: (_, audio, scanner) {
            scanner!.setPlayerController(audio.playbackController);
            audio.setScannerService(scanner);
            return scanner;
          },
        ),
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
