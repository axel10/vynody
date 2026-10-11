import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/pages/main_layout.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/settings/settings_service.dart';

void main() {
  late SettingsService settingsService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settingsService = SettingsService(prefs);
  });

  Widget buildRail({
    int selectedIndex = 2,
    int librarySubIndex = -1,
    bool isLibraryExpanded = true,
    bool extended = true,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settingsService),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SlidingNavigationRail(
            width: 240,
            extended: extended,
            selectedIndex: selectedIndex,
            onDestinationSelected: (_) {},
            backgroundColor: Colors.transparent,
            indicatorColor: Colors.red,
            isPlayback: false,
            isSettingsActive: false,
            isLibraryExpanded: isLibraryExpanded,
            librarySubIndex: librarySubIndex,
            onLibrarySubDestinationSelected: (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('When librarySubIndex is -1, playlist is not selected', (tester) async {
    await tester.pumpWidget(buildRail(librarySubIndex: -1));
    await tester.pumpAndSettle();

    // Verify 媒体库 and sub-items are rendered
    expect(find.text('媒体库'), findsNWidgets(2));
    expect(find.text('播放列表'), findsOneWidget);

    // Edit button should not be visible when not hovered
    expect(find.text('编辑'), findsNothing);
    expect(find.text('完成'), findsNothing);
  });

  testWidgets('Hovering 媒体库 shows 编辑 button, clicking it enters edit mode with checkboxes',
      (tester) async {
    await tester.pumpWidget(buildRail(librarySubIndex: -1));
    await tester.pumpAndSettle();

    // Simulate mouse hover over 媒体库 section header row
    final libraryTileFinder = find.text('媒体库').last;
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    await gesture.moveTo(tester.getCenter(libraryTileFinder));
    await tester.pumpAndSettle();

    // Now 编辑 should be visible
    expect(find.text('编辑'), findsOneWidget);

    // Click 编辑
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    // Now 完成 should be visible
    expect(find.text('完成'), findsOneWidget);

    // Checkboxes should be displayed for each sub item (7 check icons since all visible by default)
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(7));

    // Toggle (uncheck) "播放列表"
    await tester.tap(find.text('播放列表'));
    await tester.pumpAndSettle();

    // Now 播放列表 is unchecked (6 check icons remaining)
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(6));
    expect(settingsService.isLibraryTabVisible('playlist'), isFalse);

    // Click 完成 to exit edit mode
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    // Edit mode exited
    expect(find.text('完成'), findsNothing);

    // 播放列表 should no longer be displayed!
    expect(find.text('播放列表'), findsNothing);

    // Other checked items (e.g. 专辑, 艺术家) are still displayed
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('艺术家'), findsOneWidget);
  });

  testWidgets('Library sub-items remain expanded when non-library tab is selected', (tester) async {
    // When selectedIndex is 0 (文件) or 1 (播放)
    await tester.pumpWidget(buildRail(selectedIndex: 0));
    await tester.pumpAndSettle();

    // Verify 媒体库 standalone entry, 媒体库 section header, and sub-items are still displayed
    expect(find.text('媒体库'), findsNWidgets(2));
    expect(find.text('播放列表'), findsOneWidget);
    expect(find.text('专辑'), findsOneWidget);
    expect(find.text('艺术家'), findsOneWidget);
  });
}

