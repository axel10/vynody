import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';

Widget _wrap(Widget child) {
  return OKToast(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: Scaffold(
        body: SizedBox(height: 1600, width: 600, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('SongTagEditSheet populates genre and year fields', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const song = MusicFile(
      path: '/local/music/test.mp3',
      name: 'test.mp3',
      title: 'Song Title',
      artist: 'Track Artist',
      album: 'Album Title',
      trackNumber: 3,
      year: 2019,
      genres: ['Rock', 'Pop'],
      durationMillis: 180000,
    );

    await tester.pumpWidget(_wrap(const SongTagEditSheet(song: song)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('流派'), findsOneWidget);
    expect(find.text('年份'), findsOneWidget);
    expect(find.text('Rock, Pop'), findsOneWidget);
    expect(find.text('2019'), findsOneWidget);
  });

  testWidgets('SongTagEditSheet rejects a non integer year', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const song = MusicFile(
      path: '/local/music/test.mp3',
      name: 'test.mp3',
      title: 'Song Title',
      artist: 'Track Artist',
      album: 'Album Title',
      durationMillis: 180000,
    );

    await tester.pumpWidget(_wrap(const SongTagEditSheet(song: song)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final yearField = find.widgetWithText(TextField, '年份');
    expect(yearField, findsOneWidget);
    await tester.enterText(yearField, '20x9');
    await tester.pump();

    await tester.tap(find.text('保存到 App'));
    await tester.pump();

    expect(find.text('年份必须是整数'), findsOneWidget);
  });
}
