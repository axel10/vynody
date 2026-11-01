import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/library_zoom_popover.dart';

void main() {
  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  tearDown(() {
    // 兜底：正常路径由测试体内的 finally 复位，这里防止断言失败后残留。
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> pumpCard(WidgetTester tester, TargetPlatform platform) async {
    debugDefaultTargetPlatformOverride = platform;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsServiceProvider.overrideWith((ref) => settings)],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: LibraryZoomPopoverCard(scope: LibraryZoomScope.song),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('档位提示的修饰键跟随平台：macOS 用 ⌘，其余用 Ctrl', (tester) async {
    // flutter_test 会在测试体结束时就校验 foundation 的调试变量已复位，
    // 必须在体内 finally 清掉，放到 tearDown 已经太晚。
    try {
      // macOS 上 ⌘ 与 Ctrl 在判定里都认，但提示只写更顺手的 ⌘。
      await pumpCard(tester, TargetPlatform.macOS);
      expect(find.textContaining('⌘'), findsOneWidget);
      expect(find.textContaining('Ctrl'), findsNothing);

      await pumpCard(tester, TargetPlatform.windows);
      expect(find.textContaining('Ctrl'), findsOneWidget);
      expect(find.textContaining('⌘'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
