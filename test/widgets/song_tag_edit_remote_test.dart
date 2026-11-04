import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';

void main() {
  testWidgets('SongTagEditSheet disables save button for remote song', (
    WidgetTester tester,
  ) async {
    const remoteSong = MusicFile(
      path: 'subsonic://server1/track123',
      name: 'Remote Song',
      title: 'Remote Song',
      artist: 'Remote Artist',
      album: 'Remote Album',
      durationMillis: 180000,
    );

    await tester.pumpWidget(
      const OKToast(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: Scaffold(
            body: SizedBox(
              height: 800,
              width: 400,
              child: SongTagEditSheet(song: remoteSong),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final filledButtons = tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
    // 只有一个保存按钮：写不写回由格式决定，不再让用户选。
    expect(filledButtons.length, 1);
    expect(filledButtons.single.onPressed, isNull);
  });

  testWidgets('SongTagEditSheet enables save button for local song', (
    WidgetTester tester,
  ) async {
    const localSong = MusicFile(
      path: '/local/music/test.mp3',
      name: 'test.mp3',
      title: 'Local Song',
      artist: 'Local Artist',
      album: 'Local Album',
      durationMillis: 180000,
    );

    await tester.pumpWidget(
      const OKToast(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: Scaffold(
            body: SizedBox(
              height: 800,
              width: 400,
              child: SongTagEditSheet(song: localSong),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final filledButtons = tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
    expect(filledButtons.length, 1);
    expect(filledButtons.single.onPressed, isNotNull);
  });

  testWidgets('写不了的文件同样只有一个可用按钮，并说明只能保存到 App', (
    WidgetTester tester,
  ) async {
    // TagLib 没有 ADTS 解析器，写不了；以前这条只能点「保存到 App」，
    // 现在按钮收敛成一个，格式判断交给 isMetadataWritable。
    const rawAacSong = MusicFile(
      path: '/local/music/test.aac',
      name: 'test.aac',
      title: 'Raw AAC',
      artist: 'Local Artist',
      album: 'Local Album',
      durationMillis: 180000,
    );

    // 提示位于表单底部，弹窗内容是懒构建的，视口不够高就根本不会建出来。
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const OKToast(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: Scaffold(
            body: SizedBox(
              height: 1600,
              width: 600,
              child: SongTagEditSheet(song: rawAacSong),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final filledButtons = tester.widgetList<FilledButton>(find.byType(FilledButton)).toList();
    expect(filledButtons.length, 1);
    expect(filledButtons.single.onPressed, isNotNull);
    expect(
      find.text('当前文件格式不支持写回源文件，只能保存到 App。'),
      findsOneWidget,
    );
  });

  testWidgets('SongTagEditSheet displays and populates album artist field', (
    WidgetTester tester,
  ) async {
    const song = MusicFile(
      path: '/local/music/test.mp3',
      name: 'test.mp3',
      title: 'Song Title',
      artist: 'Track Artist',
      albumArtist: 'Main Album Artist',
      album: 'Album Title',
      durationMillis: 180000,
    );

    await tester.pumpWidget(
      const OKToast(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('zh'),
          home: Scaffold(
            body: SizedBox(
              height: 800,
              width: 400,
              child: SongTagEditSheet(song: song),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('专辑艺术家'), findsOneWidget);
    expect(find.text('Main Album Artist'), findsOneWidget);
  });
}
