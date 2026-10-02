import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/waveform_progress_bar.dart';

void main() {
  testWidgets('WaveformProgressBar renders and handles drag with inertia', (
    WidgetTester tester,
  ) async {
    double currentProgress = 0.5;
    double? seekedProgress;
    double? scrubbedProgress;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 80,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return WaveformProgressBar(
                      waveform: List.generate(100, (i) => 0.5),
                      progress: currentProgress,
                      duration: const Duration(seconds: 200),
                      isPlaying: false,
                      isScrolling: true,
                      barWidth: 6.0,
                      barGap: 4.0,
                      onScrubbing: (val) {
                        scrubbedProgress = val;
                      },
                      onSeek: (val) {
                        seekedProgress = val;
                        setState(() {
                          currentProgress = val;
                        });
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(WaveformProgressBar), findsOneWidget);

    // Fling gesture to simulate drag and release with velocity
    await tester.fling(
      find.byType(WaveformProgressBar),
      const Offset(-100, 0), // Swipe left -> progress should increase
      1000, // 1000 px/s velocity
    );

    // After fling started, inertia simulation runs over time
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrubbedProgress, isNotNull);
    expect(scrubbedProgress!, greaterThan(0.5));

    // Let inertia animation finish completely
    await tester.pumpAndSettle();

    expect(seekedProgress, isNotNull);
    expect(seekedProgress!, greaterThan(0.5));
  });

  testWidgets('WaveformProgressBar stops inertia on tap down', (
    WidgetTester tester,
  ) async {
    double currentProgress = 0.5;
    double? seekedProgress;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                height: 80,
                child: WaveformProgressBar(
                  waveform: List.generate(100, (i) => 0.5),
                  progress: currentProgress,
                  duration: const Duration(seconds: 200),
                  isPlaying: false,
                  isScrolling: true,
                  barWidth: 6.0,
                  barGap: 4.0,
                  onScrubbing: (_) {},
                  onSeek: (val) {
                    seekedProgress = val;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // Fling to start inertia
    await tester.fling(
      find.byType(WaveformProgressBar),
      const Offset(-100, 0),
      1000,
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Tap to interrupt inertia
    await tester.tap(find.byType(WaveformProgressBar));
    await tester.pumpAndSettle();

    expect(seekedProgress, isNotNull);
    expect(seekedProgress!, greaterThan(0.5));
  });
}
