import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/pro/pro_license_service.dart';
import 'package:vynody/widgets/dynamic_mesh_background.dart';

import 'helpers/mobile_screenshot_harness.dart';

void main() {
  testWidgets('动态流变 与 动态流变 v2 都能渲染', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);

    const music = MusicFile(
      path: '/demo/a.mp3',
      name: 'a.mp3',
      title: 'A',
      artist: 'B',
      album: 'C',
    );

    // 同色相 4 色，避免触发主色重算（那样会去读真实 AudioService）。
    const palette = <String, Color>{
      'mesh1': Color(0xFF101828),
      'mesh2': Color(0xFF101A2C),
      'mesh3': Color(0xFF121C30),
      'mesh4': Color(0xFF14203A),
    };

    // MeshFlowBackground 每帧解析封面纹理时会读 AudioService 的封面缓存
    // （`_resolveCoverBytes`），不挡住就会在测试里构造真实的 AudioService：
    // 没有 RustLib 时它的初始化链会抛未处理异常，把这条用例判失败。
    final visualizerStreamController = StreamController<FftFrame>.broadcast();
    addTearDown(visualizerStreamController.close);
    final audioService = MockAudioService(
      snapshot: AudioSnapshot(
        isPlaying: false,
        isTransitioning: false,
        isLastActionNext: null,
        currentMusic: music,
        position: Duration.zero,
        duration: Duration.zero,
        volume: 1.0,
        isMuted: false,
        playbackQueue: const [music],
        currentIndex: 0,
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
        isLyricsActive: false,
        sleepTimerRemaining: null,
        sleepTimerDuration: null,
      ),
      visualizerStream: visualizerStreamController.stream,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsServiceProvider.overrideWith((ref) => settings),
          isProUnlockedProvider.overrideWith((ref) => true),
          audioServiceProvider.overrideWith((ref) => audioService),
          audioCurrentMusicProvider.overrideWithValue(music),
          audioCurrentThemeColorsMapProvider.overrideWithValue(palette),
          audioDynamicStartColorProvider.overrideWithValue(
            const Color(0xFF101828),
          ),
          audioDynamicEndColorProvider.overrideWithValue(
            const Color(0xFF14203A),
          ),
        ],
        child: const MaterialApp(
          home: Stack(
            children: [DynamicMeshBackground(), MeshFlowBackground()],
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(DynamicMeshBackground), findsOneWidget);
    expect(find.byType(MeshFlowBackground), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
