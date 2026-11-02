import 'package:audio_core/audio_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// 暂停后频谱必须「平滑落下 → 落到底停表」，不能定格后继续 60Hz 空转。
///
/// 回归背景：`VisualizerOutputStream` 的 render 定时器过去只看有没有订阅者，
/// 与播放状态无关。暂停后照样每 tick 取采样、emit 一帧，订阅方（列表行的
/// 小图标、迷你播放器频谱）于是不断标脏 → 调度下一帧，DevTools 里表现为
/// 「暂停了还在满帧渲染」，同时白烧 FFT 聚合。
void main() {
  const groups = 8;

  VisualizerOutputStream buildOutput(List<double> Function() source) {
    return VisualizerOutputStream(
      config: const VisualizerOutputConfig(
        id: 'test',
        frequencyGroups: groups,
        targetFrameRate: 100,
        options: VisualizerOptimizationOptions(
          frequencyGroups: groups,
          targetFrameRate: 100,
          // 调大 gravity 让下落在一两百毫秒内走完，避免测试等太久。
          gravityCoefficient: 10,
          smoothingCoefficient: 0,
          groupContrastExponent: 1,
          logarithmicScale: 1,
          overallMultiplier: 1,
        ),
      ),
      fftSourceProvider: source,
      sourceAlreadyGrouped: false,
    );
  }

  double peak(List<double> values) =>
      values.fold<double>(0, (m, v) => v.abs() > m ? v.abs() : m);

  test('暂停后频谱平滑落到底并停表，恢复播放能重新起表', () async {
    var rawBins = List<double>.filled(groups, 1.0);
    final output = buildOutput(() => rawBins);

    final frames = <List<double>>[];
    final subscription = output.fftStream.listen(
      (frame) => frames.add(frame.values),
    );

    // --- 播放态：有能量 ---
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(frames, isNotEmpty, reason: '播放态应当推帧');
    final playingPeak = peak(frames.last);
    expect(playingPeak, greaterThan(0.05), reason: '播放态频谱应有能量');

    // --- 暂停：不管源还给不给数据，都只走衰减 ---
    rawBins = List<double>.filled(groups, 0.0);
    output.setPlaying(false);
    final countAtPause = frames.length;
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final afterPause = frames.sublist(countAtPause);
    expect(afterPause, isNotEmpty, reason: '暂停后要先落下，而不是直接定格');

    // 单调下落：任何一帧的峰值都不应高过前一帧。
    for (var i = 1; i < afterPause.length; i++) {
      expect(
        peak(afterPause[i]),
        lessThanOrEqualTo(peak(afterPause[i - 1]) + 1e-9),
        reason: '第 $i 帧出现了上升，说明暂停后仍在吸收真实采样',
      );
    }
    expect(peak(afterPause.last), lessThanOrEqualTo(1e-3), reason: '应当落到底');

    // --- 落到底之后必须停表 ---
    final countAfterSilence = frames.length;
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(
      frames.length,
      countAfterSilence,
      reason: '静止后不应继续推帧，否则 UI 会被 60Hz 定时器一直拖着出帧',
    );

    // --- 恢复播放：定时器要能重新起来 ---
    rawBins = List<double>.filled(groups, 1.0);
    output.setPlaying(true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(
      frames.length,
      greaterThan(countAfterSilence),
      reason: '恢复播放后应当重新推帧',
    );
    expect(peak(frames.last), greaterThan(0.05), reason: '恢复后频谱应重新有能量');

    await subscription.cancel();
    output.dispose();
  });

  test('FftProcessor.decayTowardsSilence 只按 gravity 衰减，不吸收采样', () {
    final processor = FftProcessor(
      fftSize: 1024,
      options: const VisualizerOptimizationOptions(
        frequencyGroups: groups,
        gravityCoefficient: 10,
        smoothingCoefficient: 0,
      ),
    );

    processor.processAnalysis(
      List<double>.filled(groups, 1.0),
      1 / 100,
      sourceAlreadyGrouped: true,
    );
    processor.processRender(10000, 10000);
    expect(processor.isSilent, isFalse);
    final before = processor.latestOptimizedFft.toList();

    processor.decayTowardsSilence(1 / 100);
    processor.processRender(10000, 10000);
    final after = processor.latestOptimizedFft.toList();

    for (var i = 0; i < groups; i++) {
      expect(after[i], lessThan(before[i]), reason: '第 $i 个频段没有下落');
    }
    expect(after.every((v) => v >= 0), isTrue, reason: '不应衰减成负值');
  });
}
