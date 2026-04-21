import 'dart:async';
import 'dart:io';
import 'package:audio_core/audio_core.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:oktoast/oktoast.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:worker_manager/worker_manager.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_single_instance/windows_single_instance.dart';
import 'l10n/app_localizations.dart';
import 'pages/main_layout.dart';
import 'player/audio_riverpod.dart';
import 'player/music_file_utils.dart';
import 'player/settings_service.dart';
import 'package:smtc_windows/smtc_windows.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// 处理从外部（如双击、命令行）打开的文件列表
/// [args] 是外部传入的路径参数列表
void handleFileOpen(List<String> args) {
  if (args.isEmpty) return;
  final context = navigatorKey.currentContext; // 获取全局导航上下文以访问 Provider
  if (context == null) return;

  final container = ProviderScope.containerOf(context);
  final audio = container.read(audioServiceProvider);

  AppLog.install();

  for (var arg in args) {
    // 处理路径中可能的双引号和两端空格
    final path = arg.replaceAll('"', '').trim();
    if (path.isEmpty) continue;

    // 检查文件是否存在
    if (File(path).existsSync()) {
      // 如果是支持的音频文件
      if (MusicFileUtils.isMusicFilePath(path)) {
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
    sqfliteFfiInit();
  }

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
  unawaited(workerManager.init(isolatesCount: 8));

  runApp(
    ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(audioServiceWiringProvider);
          return MyApp(args: args);
        },
      ),
    ),
  );
}

class MyApp extends ConsumerWidget {
  final List<String> args;
  const MyApp({super.key, required this.args});

  static const Color appPrimaryColor = Color(0xFF39C5BB);

  static const fontFallbacks = [
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

  ThemeData _buildTheme(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: appPrimaryColor,
      brightness: brightness,
    ).copyWith(primary: appPrimaryColor);
    final isDark = brightness == Brightness.dark;
    final snackBarBackground = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final snackBarForeground = isDark ? Colors.white : Colors.black;

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      fontFamily: 'SourceHanSansCN',
      fontFamilyFallback: fontFallbacks,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: snackBarBackground,
        contentTextStyle: TextStyle(
          color: snackBarForeground,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: snackBarForeground,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 0,
      ),

      // 将焦点颜色设为透明
      // focusColor: Colors.transparent,
      // 将悬停颜色设为透明
      // hoverColor: Colors.transparent,
      // 顺便可以处理掉点击时的水波纹按下颜色
      // highlightColor: Colors.transparent,

    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsServiceProvider);
    return OKToast(
      child: MaterialApp(
        title: 'Pure Player',
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        themeMode: settings.themeMode,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: MainLayout(args: args),
        navigatorKey: navigatorKey,
      ),
    );
  }
}
