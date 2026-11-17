import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/folder_header_banner.dart';

void main() {
  Widget buildHarness({
    required Size size,
    required Widget child,
  }) {
    return ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Scaffold(
            body: SingleChildScrollView(
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'portrait banner shows icon-only unified capsule buttons left-aligned',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildHarness(
          size: const Size(400, 800),
          child: FolderHeaderBanner(
            title: 'Music',
            subtitle: 'Library',
            songsCount: 12,
            totalDuration: const Duration(minutes: 42),
            coverWidget: const SizedBox(width: 100, height: 100),
            actionButtons: [
              FolderPlayActionButtons(
                totalSongsCount: 12,
                onPlayAll: () {},
                onShufflePlay: () {},
              ),
            ],
            onSearch: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Play All and Shuffle labels must not be shown in portrait banner.
      expect(find.text('播放全部'), findsNothing);
      expect(find.text('随机播放'), findsNothing);

      // All three icons must exist and share the 20dp icon size.
      final playIconFinder = find.byIcon(Icons.play_arrow_rounded);
      final shuffleIconFinder = find.byIcon(Icons.shuffle_rounded);
      final searchIconFinder = find.byIcon(Icons.search_rounded);
      expect(playIconFinder, findsOneWidget);
      expect(shuffleIconFinder, findsOneWidget);
      expect(searchIconFinder, findsOneWidget);

      expect(tester.widget<Icon>(playIconFinder).size, 20.0);
      expect(tester.widget<Icon>(shuffleIconFinder).size, 20.0);
      expect(tester.widget<Icon>(searchIconFinder).size, 20.0);

      // All three buttons must have the same 48x32 capsule dimensions.
      final playButtonRect = tester.getRect(
        find.ancestor(of: playIconFinder, matching: find.byType(FilledButton)),
      );
      final shuffleButtonRect = tester.getRect(
        find.ancestor(of: shuffleIconFinder, matching: find.byType(FilledButton)),
      );
      final searchButtonRect = tester.getRect(
        find.ancestor(of: searchIconFinder, matching: find.byType(IconButton)),
      );

      expect(playButtonRect.size, const Size(48, 32));
      expect(shuffleButtonRect.size, const Size(48, 32));
      expect(searchButtonRect.size, const Size(48, 32));

      // Buttons must be left-aligned with 8px spacing (search not pushed to right edge).
      expect(playButtonRect.left, 16.0);
      expect(shuffleButtonRect.left - playButtonRect.right, 8.0);
      expect(searchButtonRect.left - shuffleButtonRect.right, 8.0);
    },
  );

  testWidgets(
    'landscape banner keeps text labels on play all and shuffle buttons',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        buildHarness(
          size: const Size(900, 500),
          child: FolderHeaderBanner(
            title: 'Music',
            subtitle: 'Library',
            songsCount: 12,
            totalDuration: const Duration(minutes: 42),
            coverWidget: const SizedBox(width: 100, height: 100),
            actionButtons: [
              FolderPlayActionButtons(
                totalSongsCount: 12,
                onPlayAll: () {},
                onShufflePlay: () {},
              ),
            ],
            onSearch: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('播放全部'), findsOneWidget);
      expect(find.text('随机播放'), findsOneWidget);
    },
  );
}
