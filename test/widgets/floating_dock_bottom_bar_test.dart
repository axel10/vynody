import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'dart:typed_data';
import 'package:audio_core/audio_core.dart';
import 'package:vynody/widgets/animated_play_pause_button.dart';
import 'package:vynody/widgets/floating_dock_bottom_bar.dart';
import 'package:vynody/widgets/mini_player_widgets.dart';
import 'package:vynody/pages/main_layout_riverpod.dart';

class _MockAudioService extends Fake implements AudioService {
  @override
  Stream<FftFrame>? get miniPlayerFftStream => null;

  @override
  Uint8List? getCachedArtwork(String? path) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FloatingDockScrollHelper.traceEnabled = false;
  });

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
    MusicFile? currentMusic,
  }) {
    return ProviderScope(
      overrides: [
        settingsServiceProvider.overrideWith((ref) => settings),
        audioServiceProvider.overrideWith((ref) => _MockAudioService()),
        audioCurrentMusicProvider.overrideWith((ref) => currentMusic),
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

  testWidgets(
      'FloatingDockBottomBar mini player buttons on iPad use size 26/32 with 8pt padding',
      (tester) async {
    tester.view.physicalSize = const Size(810, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const testSong = MusicFile(
      path: '/test.mp3',
      name: 'Test Song',
      title: 'Test Song',
      artist: 'Test Artist',
    );

    await tester.pumpWidget(
      buildTestWidget(
        screenSize: const Size(810, 1080),
        padding: const EdgeInsets.only(bottom: 20.0),
        platform: TargetPlatform.iOS,
        currentMusic: testSong,
      ),
    );
    await tester.pumpAndSettle();

    final prevNextButtons = tester.widgetList<MiniControlButton>(
      find.byType(MiniControlButton),
    ).toList();
    expect(prevNextButtons.length, 2);
    for (final btn in prevNextButtons) {
      expect(btn.iconSize, 26.0);
      expect(btn.padding, const EdgeInsets.all(8.0));
    }

    final playPauseButton = tester.widget<AnimatedPlayPauseButton>(
      find.byType(AnimatedPlayPauseButton),
    );
    expect(playPauseButton.size, 32.0);
    expect(playPauseButton.padding, const EdgeInsets.all(8.0));

    final miniArtwork = tester.widget<MiniArtwork>(
      find.byType(MiniArtwork),
    );
    expect(miniArtwork.size, 42.0);
  });

  testWidgets(
      'FloatingDockBottomBar mini player buttons on iPhone use size 20/26 with 4pt padding',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const testSong = MusicFile(
      path: '/test.mp3',
      name: 'Test Song',
      title: 'Test Song',
      artist: 'Test Artist',
    );

    await tester.pumpWidget(
      buildTestWidget(
        screenSize: const Size(393, 852),
        padding: const EdgeInsets.only(bottom: 34.0),
        platform: TargetPlatform.iOS,
        currentMusic: testSong,
      ),
    );
    await tester.pumpAndSettle();

    final prevNextButtons = tester.widgetList<MiniControlButton>(
      find.byType(MiniControlButton),
    ).toList();
    expect(prevNextButtons.length, 2);
    for (final btn in prevNextButtons) {
      expect(btn.iconSize, 20.0);
      expect(btn.padding, const EdgeInsets.all(4.0));
    }

    final playPauseButton = tester.widget<AnimatedPlayPauseButton>(
      find.byType(AnimatedPlayPauseButton),
    );
    expect(playPauseButton.size, 26.0);
    expect(playPauseButton.padding, const EdgeInsets.all(4.0));
  });

  testWidgets(
      'FloatingDockBottomBar smoothly collapses and shows active tab icon to expand',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const testSong = MusicFile(
      path: '/test.mp3',
      name: 'Test Song',
      title: 'Test Song',
      artist: 'Test Artist',
    );

    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          audioServiceProvider.overrideWith((ref) => _MockAudioService()),
          audioCurrentMusicProvider.overrideWith((ref) => testSong),
          audioIsPlayingProvider.overrideWith((ref) => false),
          audioIsBufferingProvider.overrideWith((ref) => false),
          audioProgressProvider.overrideWith((ref) => 0.0),
          audioPositionProvider.overrideWith((ref) => Duration.zero),
          audioDurationProvider.overrideWith((ref) => Duration.zero),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Stack(
                  children: [
                    FloatingDockBottomBar(
                      currentIndex: 0,
                      onDestinationSelected: (_) {},
                      isPlayback: false,
                      isHidden: false,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认展开态：显示歌曲标题
    expect(find.text('Test Song'), findsOneWidget);

    // 触发收起
    capturedRef.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160)); // 中间过渡态
    await tester.pumpAndSettle(); // 完全收起

    // 收起态：最左侧包含当前 Tab 图标按钮（点击可展开）
    final expandIconFinder = find.byIcon(Icons.folder);
    expect(expandIconFinder, findsWidgets);

    // 验证收起态 Tab 按钮的点击区域尺寸（手机端至少 48x44）
    final inkWellFinder = find.ancestor(
      of: expandIconFinder.first,
      matching: find.byType(InkWell),
    );
    expect(inkWellFinder, findsOneWidget);
    final inkWellSize = tester.getSize(inkWellFinder);
    expect(inkWellSize.width, greaterThanOrEqualTo(48.0));
    expect(inkWellSize.height, greaterThanOrEqualTo(44.0));

    // 点击最左侧 Tab 图标展开
    await tester.tap(expandIconFinder.first);
    await tester.pumpAndSettle();

    // 展开后状态恢复
    expect(capturedRef.read(floatingDockCollapsedProvider), false);
  });

  testWidgets(
      'FloatingDockBottomBar collapses tabs by merging them into the capsule icon instead of sliding the row vertically',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const testSong = MusicFile(
      path: '/test.mp3',
      name: 'Test Song',
      title: 'Test Song',
      artist: 'Test Artist',
    );

    late WidgetRef capturedRef;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          audioServiceProvider.overrideWith((ref) => _MockAudioService()),
          audioCurrentMusicProvider.overrideWith((ref) => testSong),
          audioIsPlayingProvider.overrideWith((ref) => false),
          audioIsBufferingProvider.overrideWith((ref) => false),
          audioProgressProvider.overrideWith((ref) => 0.0),
          audioPositionProvider.overrideWith((ref) => Duration.zero),
          audioDurationProvider.overrideWith((ref) => Duration.zero),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Stack(
                  children: [
                    FloatingDockBottomBar(
                      currentIndex: 0,
                      onDestinationSelected: (_) {},
                      isPlayback: false,
                      isHidden: false,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final settingsFinder = find.byIcon(Icons.settings_outlined);
    final shareFinder = find.byIcon(Icons.share_outlined);
    expect(settingsFinder, findsOneWidget);
    expect(shareFinder, findsOneWidget);

    final expandedSettings = tester.getCenter(settingsFinder);
    final expandedShare = tester.getCenter(shareFinder);
    // 展开态：相邻图标各占一个槽位，横向相距一个槽宽
    expect(expandedSettings.dx - expandedShare.dx, greaterThan(40.0));

    capturedRef.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    await tester.pump(); // 启动折叠形变

    // 逐帧采样，直到这一行图标淡尽：不依赖具体曲线，只看轨迹形状
    Offset? lastVisible;
    var minGap = double.infinity;
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (!tester.any(settingsFinder)) break;
      lastVisible = tester.getCenter(settingsFinder);
      if (tester.any(shareFinder)) {
        final gap = (lastVisible.dx - tester.getCenter(shareFinder).dx).abs();
        if (gap < minGap) minGap = gap;
      }
    }
    expect(lastVisible, isNotNull);

    // 合流：最右的图标贴到了前面图标的位置上（旧实现的间距始终是一个槽宽）
    expect(minGap, lessThan(8.0));
    // 方向是「左移 + 上移」，而不是整行图标一起上下位移
    expect(lastVisible!.dx, lessThan(expandedSettings.dx - 40.0));
    expect(lastVisible.dy, lessThan(expandedSettings.dy - 8.0));

    await tester.pumpAndSettle();
    // 完全收起后这一行不再残留图标，落点就是收起态胶囊里的那个单图标
    expect(settingsFinder, findsNothing);
    expect(shareFinder, findsNothing);
    final capsuleFinder = find.byIcon(Icons.folder);
    expect(capsuleFinder, findsOneWidget);
    expect(
      (tester.getCenter(capsuleFinder).dx - lastVisible.dx).abs(),
      lessThan(6.0),
    );

    // 再展开：图标铺回各自槽位
    capturedRef
        .read(floatingDockCollapsedProvider.notifier)
        .setCollapsed(false);
    await tester.pumpAndSettle();
    final restoredSettings = tester.getCenter(
      find.byIcon(Icons.settings_outlined),
    );
    expect(restoredSettings.dx, closeTo(expandedSettings.dx, 1.0));
  });

  testWidgets(
      'FloatingDockBottomBar translates vertically and ignores pointer when scrolled past maxScrollOffset',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          audioServiceProvider.overrideWith((ref) => _MockAudioService()),
          audioCurrentMusicProvider.overrideWith((ref) => null),
          audioIsPlayingProvider.overrideWith((ref) => false),
          audioIsBufferingProvider.overrideWith((ref) => false),
          audioProgressProvider.overrideWith((ref) => 0.0),
          audioPositionProvider.overrideWith((ref) => Duration.zero),
          audioDurationProvider.overrideWith((ref) => Duration.zero),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Stack(
                  children: [
                    FloatingDockBottomBar(
                      currentIndex: 0,
                      onDestinationSelected: (_) {},
                      isPlayback: false,
                      isHidden: false,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Transform getDockTransform() {
      final animatedPositioned = tester.widget<AnimatedPositioned>(
        find.byType(AnimatedPositioned),
      );
      return animatedPositioned.child as Transform;
    }

    // 默认原位：Transform 的 offset 应该为 0
    expect(getDockTransform().transform.getTranslation().y, 0.0);

    // 模拟向下滚动产生了 80px 位移
    capturedRef.read(floatingDockScrollOffsetProvider.notifier).setOffset(80.0);
    await tester.pump();

    expect(getDockTransform().transform.getTranslation().y, 80.0);

    // 当位移达到或超过最大上限 maxScrollOffset 时，IgnorePointer 忽略触控
    capturedRef
        .read(floatingDockScrollOffsetProvider.notifier)
        .setOffset(FloatingDockScrollHelper.maxScrollOffset);
    await tester.pump();

    final ignorePointerFinder = find.descendant(
      of: find.byType(FloatingDockBottomBar),
      matching: find.byType(IgnorePointer),
    );
    final ignorePointer = tester.widget<IgnorePointer>(
      ignorePointerFinder.first,
    );
    expect(ignorePointer.ignoring, true);
  });


  testWidgets(
      'FloatingDockBottomBar scales down slightly when collapsePrepProgress increases',
      (tester) async {
    late WidgetRef capturedRef;
    const testSong = MusicFile(
      path: '/test.mp3',
      name: 'Test Song',
      title: 'Test Song',
      artist: 'Test Artist',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          audioServiceProvider.overrideWith((ref) => _MockAudioService()),
          audioCurrentMusicProvider.overrideWith((ref) => testSong),
          audioIsPlayingProvider.overrideWith((ref) => false),
          audioIsBufferingProvider.overrideWith((ref) => false),
          audioProgressProvider.overrideWith((ref) => 0.0),
          audioPositionProvider.overrideWith((ref) => Duration.zero),
          audioDurationProvider.overrideWith((ref) => Duration.zero),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return Stack(
                  children: [
                    FloatingDockBottomBar(
                      currentIndex: 0,
                      onDestinationSelected: (_) {},
                      isPlayback: false,
                      isHidden: false,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Find AnimatedScale widget
    final animatedScaleFinder = find.byType(AnimatedScale);
    expect(animatedScaleFinder, findsOneWidget);
    AnimatedScale scaleWidget = tester.widget(animatedScaleFinder);
    expect(scaleWidget.scale, 1.0);

    // Simulate progress 1.0
    capturedRef
        .read(floatingDockCollapseProgressProvider.notifier)
        .setProgress(1.0);
    await tester.pump();
    scaleWidget = tester.widget(animatedScaleFinder);
    expect(scaleWidget.scale, closeTo(0.95, 0.001));
  });

  testWidgets(
      'FloatingDockBottomBar contains 5 tabs without a redundant Play tab',
      (tester) async {
    await tester.pumpWidget(
      buildTestWidget(
        screenSize: const Size(393, 852),
        padding: const EdgeInsets.only(bottom: 34),
      ),
    );
    await tester.pumpAndSettle();

    // Verify 5 primary navigation tabs exist
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byIcon(Icons.playlist_play_outlined), findsOneWidget);
    expect(find.byIcon(Icons.queue_music_outlined), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    // Verify play_circle_outline (the removed Play tab) is not in the dock tabs
    expect(find.byIcon(Icons.play_circle_outline), findsNothing);
    expect(find.byIcon(Icons.play_circle), findsNothing);
  });
}

