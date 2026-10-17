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
      'FloatingDockScrollHelper accumulates scroll distance, updates progress, and collapses at threshold',
      (tester) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    final helper = FloatingDockScrollHelper(collapseScrollThreshold: 72.0);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    // Initial state
    expect(capturedRef.read(floatingDockCollapsedProvider), false);
    expect(capturedRef.read(floatingDockCollapseProgressProvider), 0.0);

    final metricsMid = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 50,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    // Scroll down halfway (36px out of 72px)
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsMid,
        context: capturedContext,
        scrollDelta: 36.0,
      ),
      capturedRef,
    );
    expect(
      capturedRef.read(floatingDockCollapseProgressProvider),
      closeTo(0.5, 0.01),
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);

    // Scroll end before reaching threshold resets progress
    helper.handleScrollNotification(
      ScrollEndNotification(
        metrics: metricsMid,
        context: capturedContext,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapseProgressProvider), 0.0);

    // Scroll reaches threshold (72px) -> triggers collapse
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsMid,
        context: capturedContext,
        scrollDelta: 72.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), true);
    expect(capturedRef.read(floatingDockCollapseProgressProvider), 0.0);

    // Return to top (< 20px) unfolds dock
    final metricsTop = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 10,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsTop,
        context: capturedContext,
        scrollDelta: -50.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);
  });

  testWidgets(
      'FloatingDockScrollHelper expands when upward scroll reaches expandScrollThreshold',
      (tester) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    final helper = FloatingDockScrollHelper(
      collapseScrollThreshold: 72.0,
      expandScrollThreshold: 72.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 200,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    // 1. Manually set collapsed to true
    capturedRef.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // 2. Upward scroll exceeding 72px expands dock
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metrics,
        context: capturedContext,
        scrollDelta: -75.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);
  });

  testWidgets(
      'FloatingDockScrollHelper resets upward accumulated distance on gesture end so micro drags do not expand prematurely',
      (tester) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    final helper = FloatingDockScrollHelper(
      collapseScrollThreshold: 72.0,
      expandScrollThreshold: 72.0,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    final metrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 300,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    capturedRef.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // 1. Small drag of 30px (< 72px)
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metrics,
        context: capturedContext,
        scrollDelta: -30.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // Gesture ends: resets accumulated distance
    helper.handleScrollNotification(
      ScrollEndNotification(
        metrics: metrics,
        context: capturedContext,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // 2. Another small drag of 30px: should NOT expand because previous 30px was cleared
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metrics,
        context: capturedContext,
        scrollDelta: -30.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // 3. A drag of 80px (>= 72px) without interruption: expands dock
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metrics,
        context: capturedContext,
        scrollDelta: -80.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);
  });

  testWidgets(
      'FloatingDockScrollHelper automatically expands dock when scrolling near bottom',
      (tester) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    final helper = FloatingDockScrollHelper();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    // 1. Manually set collapsed to true
    capturedRef.read(floatingDockCollapsedProvider.notifier).setCollapsed(true);
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // 2. Scroll near bottom (pixels >= maxScrollExtent - 20)
    final bottomMetrics = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 985,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: bottomMetrics,
        context: capturedContext,
        scrollDelta: 10.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);
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
      'FloatingDockScrollHelper supports mouse wheel step-by-step scrolling with debounce',
      (tester) async {
    late WidgetRef capturedRef;
    late BuildContext capturedContext;
    final helper = FloatingDockScrollHelper();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                capturedContext = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    final metricsMid = FixedScrollMetrics(
      minScrollExtent: 0,
      maxScrollExtent: 1000,
      pixels: 50,
      viewportDimension: 500,
      axisDirection: AxisDirection.down,
      devicePixelRatio: 1.0,
    );

    // 1. 模拟鼠标滚轮向下滚第 1 格 (30px)，紧跟 ScrollEndNotification
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsMid,
        context: capturedContext,
        scrollDelta: 30.0,
      ),
      capturedRef,
    );
    helper.handleScrollNotification(
      ScrollEndNotification(
        metrics: metricsMid,
        context: capturedContext,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);

    // 2. 模拟鼠标滚轮在防抖窗口期内继续向下滚第 2 格 (30px)，紧跟 ScrollEndNotification
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsMid,
        context: capturedContext,
        scrollDelta: 30.0,
      ),
      capturedRef,
    );
    helper.handleScrollNotification(
      ScrollEndNotification(
        metrics: metricsMid,
        context: capturedContext,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);

    // 3. 模拟滚第 3 格 (20px，总计 30+30+20 = 80px >= 72px) -> 触发收起
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsMid,
        context: capturedContext,
        scrollDelta: 20.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // 4. 收起状态下，模拟鼠标向上滚第 1 格 (-35px) 和 ScrollEndNotification
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsMid,
        context: capturedContext,
        scrollDelta: -35.0,
      ),
      capturedRef,
    );
    helper.handleScrollNotification(
      ScrollEndNotification(
        metrics: metricsMid,
        context: capturedContext,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), true);

    // 5. 向上滚第 2 格 (-40px，总计 35+40 = 75px >= 72px) -> 触发展开
    helper.handleScrollNotification(
      ScrollUpdateNotification(
        metrics: metricsMid,
        context: capturedContext,
        scrollDelta: -40.0,
      ),
      capturedRef,
    );
    expect(capturedRef.read(floatingDockCollapsedProvider), false);

    helper.dispose();
  });
}

