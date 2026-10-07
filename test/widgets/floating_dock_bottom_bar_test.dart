import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/floating_dock_bottom_bar.dart';

class _MockAudioService extends Fake implements AudioService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsService settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    settings = SettingsService(prefs);
  });

  Widget buildTestWidget({
    required Size screenSize,
    required EdgeInsets padding,
    TargetPlatform platform = TargetPlatform.iOS,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settings),
        audioServiceProvider.overrideWith((ref) => _MockAudioService()),
        audioCurrentMusicProvider.overrideWith((ref) => null as MusicFile?),
        audioIsPlayingProvider.overrideWith((ref) => false),
        audioIsBufferingProvider.overrideWith((ref) => false),
        audioProgressProvider.overrideWith((ref) => 0.0),
        audioPositionProvider.overrideWith((ref) => Duration.zero),
        audioDurationProvider.overrideWith((ref) => Duration.zero),
      ],
      child: MaterialApp(
        theme: ThemeData(platform: platform),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: MediaQuery(
          data: MediaQueryData(
            size: screenSize,
            padding: padding,
          ),
          child: Stack(
            children: [
              FloatingDockBottomBar(
                currentIndex: 0,
                onDestinationSelected: (_) {},
                isPlayback: false,
                isHidden: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('FloatingDockBottomBar on iPhone uses bottomPadding - 14 (20pt)',
      (tester) async {
    // iPhone 15: width 393, height 852, bottomPadding 34
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestWidget(
        screenSize: const Size(393, 852),
        padding: const EdgeInsets.only(bottom: 34.0),
        platform: TargetPlatform.iOS,
      ),
    );
    await tester.pumpAndSettle();

    final animatedPositionedFinder = find.byType(AnimatedPositioned);
    expect(animatedPositionedFinder, findsOneWidget);
    final animatedPositioned =
        tester.widget<AnimatedPositioned>(animatedPositionedFinder);
    expect(animatedPositioned.bottom, 20.0);
  });

  testWidgets('FloatingDockBottomBar on iPad uses bottomPadding + 8 (28pt)',
      (tester) async {
    // iPad portrait: width 810, height 1080, bottomPadding 20
    tester.view.physicalSize = const Size(810, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestWidget(
        screenSize: const Size(810, 1080),
        padding: const EdgeInsets.only(bottom: 20.0),
        platform: TargetPlatform.iOS,
      ),
    );
    await tester.pumpAndSettle();

    final animatedPositionedFinder = find.byType(AnimatedPositioned);
    expect(animatedPositionedFinder, findsOneWidget);
    final animatedPositioned =
        tester.widget<AnimatedPositioned>(animatedPositionedFinder);
    expect(animatedPositioned.bottom, 28.0);
  });

  testWidgets(
      'FloatingDockBottomBar on iPad with 0 padding falls back to 28pt',
      (tester) async {
    tester.view.physicalSize = const Size(810, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestWidget(
        screenSize: const Size(810, 1080),
        padding: EdgeInsets.zero,
        platform: TargetPlatform.iOS,
      ),
    );
    await tester.pumpAndSettle();

    final animatedPositionedFinder = find.byType(AnimatedPositioned);
    expect(animatedPositionedFinder, findsOneWidget);
    final animatedPositioned =
        tester.widget<AnimatedPositioned>(animatedPositionedFinder);
    expect(animatedPositioned.bottom, 28.0);
  });
}
