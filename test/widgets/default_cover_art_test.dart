import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/default_cover_art.dart';

void main() {
  testWidgets('DefaultCoverArt renders album icon correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: DefaultCoverArt.album(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.album_rounded), findsOneWidget);
  });

  testWidgets('DefaultCoverArt renders folder icon correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: DefaultCoverArt.folder(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.folder_rounded), findsOneWidget);
  });

  testWidgets('DefaultCoverArt renders song icon correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: DefaultCoverArt.song(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
  });

  testWidgets('DefaultCoverArt renders systemFolder icon correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: DefaultCoverArt.systemFolder(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.library_music_rounded), findsOneWidget);
  });

  testWidgets('DefaultCoverArt renders cloudFolder icon correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: DefaultCoverArt.cloudFolder(),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.cloud_queue_rounded), findsOneWidget);
  });

  testWidgets('DefaultCoverArt respects explicit iconSize and customIcon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DefaultCoverArt(
            type: CoverArtType.folder,
            iconSize: 32,
            customIcon: Icons.folder_open_rounded,
          ),
        ),
      ),
    );

    final iconFinder = find.byIcon(Icons.folder_open_rounded);
    expect(iconFinder, findsOneWidget);
    final iconWidget = tester.widget<Icon>(iconFinder);
    expect(iconWidget.size, 32);
  });
}
