import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oktoast/oktoast.dart';
import 'package:vynody/dialogs/song_tag_edit_dialog.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';

Widget _wrapWithInsets(double bottomInset, Widget child) {
  return OKToast(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: bottomInset),
        ),
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: child,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'SongTagEditSheet keeps ListView and TextFields stable while moving Save button with viewInsets',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
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

      const sheet = SongTagEditSheet(song: song);

      await tester.pumpWidget(_wrapWithInsets(0, sheet));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      final initialListView = tester.widget<ListView>(find.byType(ListView));
      final initialListViewSize = tester.getSize(find.byType(ListView));
      final initialTitleField = tester.widget<TextField>(
        find.widgetWithText(TextField, '标题'),
      );
      final initialSaveBottom = tester
          .getRect(find.widgetWithText(FilledButton, '保存'))
          .bottom;

      // Simulate keyboard sliding up across frames: before settleDelay (120ms),
      // layout should remain completely untouched.
      await tester.pumpWidget(_wrapWithInsets(150, sheet));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pumpWidget(_wrapWithInsets(300, sheet));
      await tester.pump(const Duration(milliseconds: 16));

      final duringListView = tester.widget<ListView>(find.byType(ListView));
      final duringListViewSize = tester.getSize(find.byType(ListView));
      final duringTitleField = tester.widget<TextField>(
        find.widgetWithText(TextField, '标题'),
      );
      final duringSaveBottom = tester
          .getRect(find.widgetWithText(FilledButton, '保存'))
          .bottom;

      expect(identical(duringListView, initialListView), isTrue);
      expect(duringListViewSize, equals(initialListViewSize));
      expect(identical(duringTitleField, initialTitleField), isTrue);
      expect(duringSaveBottom, closeTo(initialSaveBottom, 0.1));

      // After settleDelay (120ms), layout updates once to accommodate keyboard.
      await tester.pump(const Duration(milliseconds: 150));

      final afterListViewSize = tester.getSize(find.byType(ListView));
      final afterSaveBottom = tester
          .getRect(find.widgetWithText(FilledButton, '保存'))
          .bottom;

      expect(afterListViewSize, equals(initialListViewSize));
      expect(afterSaveBottom, closeTo(initialSaveBottom - 300, 1.0));
    },
  );
}
