import 'dart:typed_data';

import 'package:audio_core/audio_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/playback_page.dart';
import 'package:vynody/player/audio/app_playback_mode.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/player/audio/audio_snapshot.dart';
import 'package:vynody/player/settings/settings_service.dart';
import 'package:vynody/widgets/cover_carousel.dart';
import 'package:vynody/widgets/floating_dock_bottom_bar.dart';
import 'package:vynody/widgets/mini_player_widgets.dart';
import 'package:vynody/widgets/mini_player_wrapper.dart';
import 'package:vynody/widgets/playback/playback_album_art.dart';
import 'package:vynody/widgets/playback/playback_cover_flight.dart';

// 1x1 transparent PNG bytes so Image.memory decodes deterministically in tests.
final Uint8List _kTinyPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

MusicFile _buildSong() => MusicFile(
      id: 1,
      name: 'flight_song.flac',
      path: '/music/flight_song.flac',
      title: 'Flight Song',
      artist: 'Flight Artist',
      album: 'Flight Album',
      artworkBytes: _kTinyPng,
      artworkWidth: 1000,
      artworkHeight: 1000,
    );

AudioSnapshot _buildSnapshot({required bool isLyricsActive}) {
  final song = _buildSong();
  return AudioSnapshot(
    isPlaying: true,
    isBuffering: false,
    isTransitioning: false,
    isLastActionNext: true,
    currentMusic: song,
    playbackQueue: <MusicFile>[song],
    currentIndex: 0,
    position: const Duration(seconds: 12),
    duration: const Duration(seconds: 240),
    volume: 80.0,
    isMuted: false,
    isRandomMode: false,
    isShuffleRandomMode: false,
    playbackMode: AppPlaybackMode.queue,
    equalizerConfig: EqualizerConfig(
      enabled: false,
      bandCount: 10,
      preampDb: 0.0,
      bassBoostDb: 0.0,
      bassBoostFrequencyHz: 80.0,
      bassBoostQ: 1.0,
      bandGainsDb: Float32List(10),
    ),
    currentVisualizerOptions: const VisualizerOptimizationOptions(
      frequencyGroups: 100,
    ),
    historyCursor: null,
    deckCursor: null,
    isVisualizerEnabled: false,
    dynamicStartColor: null,
    dynamicEndColor: null,
    isLyricsActive: isLyricsActive,
    sleepTimerRemaining: null,
    sleepTimerDuration: null,
    playbackSpeed: 1.0,
  );
}

class _TestFlightAudioService extends AudioService {
  _TestFlightAudioService({bool initialLyrics = false})
      : _lyricsActive = initialLyrics;

  bool _lyricsActive;
  final MusicFile _song = _buildSong();

  @override
  AudioSnapshot build() => _buildSnapshot(isLyricsActive: _lyricsActive);

  @override
  MusicFile? get currentMusic => _song;

  @override
  List<MusicFile> get queue => <MusicFile>[_song];

  @override
  List<MusicFile> get playbackQueue => <MusicFile>[_song];

  @override
  int get currentIndex => 0;

  @override
  bool get isBuffering => false;

  @override
  bool get isLyricsActive => _lyricsActive;

  @override
  void setLyricsActive(bool active) {
    _lyricsActive = active;
  }

  @override
  Uint8List? getCachedArtwork(String? path) => _kTinyPng;

  @override
  void setCachedArtwork(
    String path,
    Uint8List bytes, {
    String? thumbnailPath,
  }) {}

  @override
  Future<void> completeHeroTransition({String? priorityPath}) async {}

  @override
  void applyVisualizerSettings({Orientation? orientation}) {}
}

Rect _transformedGlobalRectOf(WidgetTester tester, Finder finder) {
  final renderBox = tester.renderObject<RenderBox>(finder);
  final size = renderBox.size;
  final matrix = renderBox.getTransformTo(null);
  return MatrixUtils.transformRect(matrix, Offset.zero & size);
}

void _expectRectClose(Rect actual, Rect expected, {double epsilon = 0.05}) {
  expect(actual.left, closeTo(expected.left, epsilon));
  expect(actual.top, closeTo(expected.top, epsilon));
  expect(actual.width, closeTo(expected.width, epsilon));
  expect(actual.height, closeTo(expected.height, epsilon));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackCoverFlightGeometry unit tests', () {
    test('maps endRect exactly onto startRect at progress=0 and identity at progress=1', () {
      const startRect = Rect.fromLTWH(28.0, 712.0, 36.0, 36.0);
      const endRect = Rect.fromLTWH(32.0, 64.0, 336.0, 336.0);

      final atZero = PlaybackCoverFlightGeometry.computeCoverFlightTransform(
        startRect: startRect,
        startBorderRadius: 6.0,
        endRect: endRect,
        endBorderRadius: 24.0,
        progress: 0.0,
      );
      // Applying transform around endRect.topLeft maps (0,0,endW,endH) + endRect.topLeft -> startRect.
      final mappedAtZero = MatrixUtils.transformRect(
        atZero.transform,
        Offset.zero & endRect.size,
      ).shift(endRect.topLeft);
      _expectRectClose(mappedAtZero, startRect, epsilon: 1e-6);
      // Visual radius after scaling = localBorderRadius * scale == 6.0.
      expect(atZero.localBorderRadius * atZero.scale, closeTo(6.0, 1e-6));

      final atMid = PlaybackCoverFlightGeometry.computeCoverFlightTransform(
        startRect: startRect,
        startBorderRadius: 6.0,
        endRect: endRect,
        endBorderRadius: 24.0,
        progress: 0.5,
      );
      final mappedAtMid = MatrixUtils.transformRect(
        atMid.transform,
        Offset.zero & endRect.size,
      ).shift(endRect.topLeft);
      _expectRectClose(
        mappedAtMid,
        Rect.lerp(startRect, endRect, 0.5)!,
        epsilon: 1e-6,
      );
      expect(atMid.localBorderRadius * atMid.scale, closeTo(15.0, 1e-6));

      final atOne = PlaybackCoverFlightGeometry.computeCoverFlightTransform(
        startRect: startRect,
        startBorderRadius: 6.0,
        endRect: endRect,
        endBorderRadius: 24.0,
        progress: 1.0,
      );
      expect(atOne.transform, Matrix4.identity());
      expect(atOne.localBorderRadius, 24.0);
      expect(atOne.scale, 1.0);
    });

    test('interpolates non-square cover BoxFit.cover to BoxFit.contain smoothly', () {
      expect(
        PlaybackCoverFlightGeometry.computeBoxFitCoverToContainScale(
          artworkWidth: 1000,
          artworkHeight: 1000,
          progress: 0.0,
        ),
        1.0,
      );
      expect(
        PlaybackCoverFlightGeometry.computeBoxFitCoverToContainScale(
          artworkWidth: 1600,
          artworkHeight: 900,
          progress: 0.0,
        ),
        closeTo(16.0 / 9.0, 1e-6),
      );
      expect(
        PlaybackCoverFlightGeometry.computeBoxFitCoverToContainScale(
          artworkWidth: 1600,
          artworkHeight: 900,
          progress: 1.0,
        ),
        1.0,
      );
    });
  });

  group('PlaybackCoverFlightController anchor filtering & PlaybackPage FLIP alignment', () {
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'hasShownCoverTapLyricTip': true,
        'hasShownLyricsMenuTip': true,
      });
      final prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
    });

    testWidgets('skips Offstage anchors in inactive IndexedStack tabs and hides source during flight', (tester) async {
      final audio = _TestFlightAudioService();
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => audio),
          audioServiceStateProvider.overrideWith(() => audio),
          settingsServiceProvider.overrideWith((ref) => settings),
          audioSnapshotProvider.overrideWith(
            (ref) => _buildSnapshot(isLyricsActive: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(400, 840);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = container.read(playbackCoverFlightControllerProvider);
      controller.updateProgress(0.0, isSmallWindow: false);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Stack(
                children: [
                  IndexedStack(
                    index: 0,
                    children: const [
                      SizedBox.expand(),
                      // Inactive IndexedStack branch at (100, 100) must be ignored!
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: EdgeInsets.only(left: 100, top: 100),
                          child: MiniArtwork(size: 36, borderRadius: 6),
                        ),
                      ),
                    ],
                  ),
                  // Visible Dock MiniArtwork at (28, 760)
                  const Positioned(
                    left: 28,
                    top: 760,
                    child: MiniArtwork(size: 36, borderRadius: 6),
                  ),
                  // Offscreen hidden MiniArtwork below bottom edge (top: 920 >= 840) must be ignored!
                  const Positioned(
                    left: 50,
                    top: 920,
                    child: MiniArtwork(size: 36, borderRadius: 6),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      controller.captureOriginIfNeeded();
      expect(controller.originNotifier.value, isNotNull);
      _expectRectClose(
        controller.originNotifier.value!.rect,
        const Rect.fromLTWH(28, 760, 36, 36),
      );
      expect(controller.hideSourceArtworkNotifier.value, isFalse);

      controller.updateProgress(0.35, isSmallWindow: false);
      await tester.pump();
      expect(controller.hideSourceArtworkNotifier.value, isTrue);

      controller.updateProgress(
        0.0,
        isSmallWindow: false,
        isDrawerOpen: true,
      );
      await tester.pump();
      expect(controller.originNotifier.value, isNotNull);
      expect(controller.hideSourceArtworkNotifier.value, isFalse);

      controller.updateProgress(0.0, isSmallWindow: false);
      await tester.pump();
      expect(controller.hideSourceArtworkNotifier.value, isFalse);
      expect(controller.originNotifier.value, isNull);
    });

    for (final (:label, :surfaceSize, :isLyricsMode, :miniPos) in <({
      String label,
      Size surfaceSize,
      bool isLyricsMode,
      Offset miniPos,
    })>[
      (
        label: 'Portrait Normal',
        surfaceSize: const Size(390, 844),
        isLyricsMode: false,
        miniPos: const Offset(28, 742),
      ),
      (
        label: 'Portrait Lyrics',
        surfaceSize: const Size(390, 844),
        isLyricsMode: true,
        miniPos: const Offset(28, 742),
      ),
      (
        label: 'Landscape Normal',
        surfaceSize: const Size(1180, 760),
        isLyricsMode: false,
        miniPos: const Offset(480, 692),
      ),
      (
        label: 'Landscape Lyrics',
        surfaceSize: const Size(1180, 760),
        isLyricsMode: true,
        miniPos: const Offset(480, 692),
      ),
    ]) {
      testWidgets(
        'CoverCarousel flies seamlessly without jumps from MiniArtwork to final slot in $label',
        (tester) async {
          final audio = _TestFlightAudioService(initialLyrics: isLyricsMode);
          final container = ProviderContainer(
            overrides: [
              audioServiceProvider.overrideWith((ref) => audio),
              audioServiceStateProvider.overrideWith(() => audio),
              settingsServiceProvider.overrideWith((ref) => settings),
              audioSnapshotProvider.overrideWith(
                (ref) => _buildSnapshot(isLyricsActive: isLyricsMode),
              ),
            ],
          );
          addTearDown(container.dispose);

          await tester.binding.setSurfaceSize(surfaceSize);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          final flightController = container.read(
            playbackCoverFlightControllerProvider,
          );
          flightController.updateProgress(
            0.0,
            isSmallWindow: false,
            screenHeight: surfaceSize.height,
          );

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                localizationsDelegates:
                    AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                builder: (context, child) {
                  return MediaQuery(
                    data: MediaQueryData(
                      size: surfaceSize,
                      padding: const EdgeInsets.only(top: 44.0, bottom: 24.0),
                    ),
                    child: child!,
                  );
                },
                home: Scaffold(
                  resizeToAvoidBottomInset: false,
                  extendBody: true,
                  body: Stack(
                    children: [
                      Positioned(
                        left: miniPos.dx,
                        top: miniPos.dy,
                        child: const MiniArtwork(size: 36, borderRadius: 6),
                      ),
                      Positioned.fill(
                        child: ClipRect(
                          child: ValueListenableBuilder<double>(
                            valueListenable: flightController.progressNotifier,
                            child: const PlaybackPage(isMouseActive: false),
                            builder: (context, _, pageChild) {
                              return Transform.translate(
                                offset: Offset(
                                  0.0,
                                  flightController.currentSheetOffsetY,
                                ),
                                child: pageChild,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          // First measure the resting target rect at progress = 1.0 (sheetOffsetY = 0).
          flightController.updateProgress(
            1.0,
            isSmallWindow: false,
            screenHeight: surfaceSize.height,
          );
          await tester.pump();

          final carouselFinder = find.byType(CoverCarousel);
          expect(carouselFinder, findsOneWidget);
          expect(find.byType(PlaybackAlbumArt), findsOneWidget);
          final Rect restingCarouselRect = _transformedGlobalRectOf(
            tester,
            carouselFinder,
          );
          expect(restingCarouselRect.width, greaterThan(60.0));

          // Capture MiniArtwork origin and test start (p=0.001), midpoint (p=0.5), and end (p=1.0)
          // WHILE PlaybackPage itself is sliding up from y = screenHeight to y = 0!
          flightController.updateProgress(
            0.0,
            isSmallWindow: false,
            screenHeight: surfaceSize.height,
          );
          await tester.pump();
          flightController.captureOriginIfNeeded();

          final Rect expectedStartRect = Rect.fromLTWH(
            miniPos.dx,
            miniPos.dy,
            36.0,
            36.0,
          );
          _expectRectClose(
            flightController.originNotifier.value!.rect,
            expectedStartRect,
          );

          // Near liftoff (p = 0.001): page is near y = screenHeight, cover is at MiniArtwork!
          flightController.updateProgress(
            0.001,
            isSmallWindow: false,
            screenHeight: surfaceSize.height,
          );
          await tester.pump();
          expect(
            tester.getTopLeft(find.byType(PlaybackPage)).dy,
            closeTo(surfaceSize.height * 0.999, 0.5),
          );
          final Rect rectAtStart = _transformedGlobalRectOf(
            tester,
            carouselFinder,
          );
          _expectRectClose(
            rectAtStart,
            Rect.lerp(expectedStartRect, restingCarouselRect, 0.001)!,
          );

          // Mid-flight (p = 0.5): page is halfway up (y = 0.5 * screenHeight), cover is at midpoint!
          flightController.updateProgress(
            0.5,
            isSmallWindow: false,
            screenHeight: surfaceSize.height,
          );
          await tester.pump();
          expect(
            tester.getTopLeft(find.byType(PlaybackPage)).dy,
            closeTo(surfaceSize.height * 0.5, 0.5),
          );
          final Rect rectAtMid = _transformedGlobalRectOf(
            tester,
            carouselFinder,
          );
          _expectRectClose(
            rectAtMid,
            Rect.lerp(expectedStartRect, restingCarouselRect, 0.5)!,
          );

          // Settled (p = 1.0): page at y = 0, cover at exact resting rect with zero jump!
          flightController.updateProgress(
            1.0,
            isSmallWindow: false,
            screenHeight: surfaceSize.height,
          );
          await tester.pump();
          expect(tester.getTopLeft(find.byType(PlaybackPage)).dy, closeTo(0.0, 0.05));
          final Rect rectAtEnd = _transformedGlobalRectOf(
            tester,
            carouselFinder,
          );
          _expectRectClose(rectAtEnd, restingCarouselRect);

          // Flush PlaybackPage warmup & dispose inactivity timers cleanly.
          await tester.pump(const Duration(seconds: 1));
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 4));
        },
      );
    }

    testWidgets('interactive downward drag smoothly drives flight progress and cover rect toward MiniArtwork', (tester) async {
      final audio = _TestFlightAudioService(initialLyrics: false);
      final container = ProviderContainer(
        overrides: [
          audioServiceProvider.overrideWith((ref) => audio),
          audioServiceStateProvider.overrideWith(() => audio),
          settingsServiceProvider.overrideWith((ref) => settings),
          audioSnapshotProvider.overrideWith(
            (ref) => _buildSnapshot(isLyricsActive: false),
          ),
        ],
      );
      addTearDown(container.dispose);

      const surfaceSize = Size(390, 844);
      tester.view.physicalSize = surfaceSize;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.binding.setSurfaceSize(surfaceSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final flightController = container.read(
        playbackCoverFlightControllerProvider,
      );
      double simulatedControllerValue = 1.0;
      flightController.updateProgress(
        1.0,
        isSmallWindow: false,
        screenHeight: surfaceSize.height,
      );
      flightController.bindInteractiveDragCallbacks(
        onDragStart: () {
          flightController.refreshOriginFromLiveAnchor();
        },
        onDragUpdate: (deltaDy, screenHeight) {
          simulatedControllerValue =
              (simulatedControllerValue - deltaDy / screenHeight).clamp(
                0.0,
                1.0,
              );
          flightController.updateProgress(
            simulatedControllerValue,
            isSmallWindow: false,
            screenHeight: screenHeight,
          );
        },
        onDragEnd: (_) {},
        onDragCancel: () {},
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Stack(
                children: [
                  const Positioned(
                    left: 28,
                    top: 742,
                    child: MiniArtwork(size: 36, borderRadius: 6),
                  ),
                  Positioned.fill(
                    child: ClipRect(
                      child: ValueListenableBuilder<double>(
                        valueListenable: flightController.progressNotifier,
                        child: const PlaybackPage(isMouseActive: false),
                        builder: (context, _, pageChild) {
                          return Transform.translate(
                            offset: Offset(
                              0.0,
                              flightController.currentSheetOffsetY,
                            ),
                            child: pageChild,
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      final carouselFinder = find.byType(CoverCarousel);
      final Rect restingRect = _transformedGlobalRectOf(tester, carouselFinder);

      flightController.startInteractiveDrag();
      flightController.updateInteractiveDrag(150.0, surfaceSize.height);
      await tester.pump();

      expect(
        tester.getTopLeft(find.byType(PlaybackPage)).dy,
        closeTo(150.0, 0.5),
      );
      expect(flightController.progressNotifier.value, lessThan(1.0));
      expect(flightController.progressNotifier.value, greaterThan(0.5));
      final Rect draggedRect = _transformedGlobalRectOf(tester, carouselFinder);
      expect(draggedRect.width, lessThan(restingRect.width));
      expect(draggedRect.top, greaterThan(restingRect.top));

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
      'FloatingDockBottomBar and MiniPlayerWrapper preserve StackParentData across all flight states',
      (tester) async {
        final audio = _TestFlightAudioService(initialLyrics: false);
        final container = ProviderContainer(
          overrides: [
            audioServiceProvider.overrideWith((ref) => audio),
            audioServiceStateProvider.overrideWith(() => audio),
            settingsServiceProvider.overrideWith((ref) => settings),
            audioSnapshotProvider.overrideWith(
              (ref) => _buildSnapshot(isLyricsActive: false),
            ),
          ],
        );
        addTearDown(container.dispose);

        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final flightController = container.read(
          playbackCoverFlightControllerProvider,
        );
        flightController.bindInteractiveDragCallbacks(
          onDragStart: () {},
          onDragUpdate: (_, _) {},
          onDragEnd: (_) {},
          onDragCancel: () {},
        );
        flightController.updateProgress(0.0, isSmallWindow: false);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Stack(
                  children: [
                    const Positioned.fill(
                      child: MiniPlayerWrapper(child: SizedBox.expand()),
                    ),
                    FloatingDockBottomBar(
                      currentIndex: 0,
                      onDestinationSelected: (_) {},
                      isPlayback: false,
                      isHidden: false,
                    ),
                    FloatingDockBottomBar(
                      currentIndex: 0,
                      onDestinationSelected: (_) {},
                      isPlayback: true,
                      isHidden: false,
                      hideMiniPlayer: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);

        for (final p in <double>[0.0, 0.25, 0.6, 1.0, 0.5, 0.0]) {
          flightController.updateProgress(p, isSmallWindow: false);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      },
    );
  });
}
