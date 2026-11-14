import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/widgets/detail_content_scaffold.dart';

Widget _wrapWithApp(Widget child, {Size size = const Size(1200, 800)}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('zh'),
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('DetailContentScaffold renders loading and error states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrapWithApp(
        DetailContentScaffold(
          isLoading: true,
          headerBuilder: (_, _) => const SizedBox.shrink(),
          bodySliversBuilder: (_, _, _) => const [],
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      _wrapWithApp(
        DetailContentScaffold(
          errorWidget: const Text('Load failed'),
          headerBuilder: (_, _) => const SizedBox.shrink(),
          bodySliversBuilder: (_, _, _) => const [],
        ),
      ),
    );
    expect(find.text('Load failed'), findsOneWidget);
  });

  testWidgets('DetailHeader switches layout between portrait and landscape', (
    tester,
  ) async {
    Widget buildHeader() => DetailContentScaffold(
          headerBuilder: (_, _) => DetailHeader(
            avatarBuilder: (size) => SizedBox.square(dimension: size),
            title: 'Test Artist',
            subtitles: const [DetailHeaderSubtitle('10 songs')],
            onPlayAll: () {},
            onShufflePlay: () {},
            extraPortraitActions: const [Icon(Icons.download_rounded)],
            extraLandscapeActions: const [Icon(Icons.download_rounded)],
            searchToggle: DetailSearchToggleButton(
              isOpen: false,
              onPressed: () {},
            ),
          ),
          bodySliversBuilder: (_, _, _) => const [],
        );

    // Portrait: FilledButton + OutlinedButton
    await tester.pumpWidget(_wrapWithApp(buildHeader(), size: const Size(390, 844)));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    // Landscape: Row header without portrait chevron
    await tester.pumpWidget(_wrapWithApp(buildHeader(), size: const Size(1200, 800)));
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);

    final playIconSize = tester.widget<Icon>(find.byIcon(Icons.play_arrow)).size;
    final shuffleButtonSize = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.shuffle),
        matching: find.byType(IconButton),
      ),
    );
    final searchButtonSize = tester.getSize(
      find.ancestor(
        of: find.byIcon(Icons.search_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(searchButtonSize, equals(shuffleButtonSize));
    expect(
      tester.widget<Icon>(find.byIcon(Icons.search_rounded)).size,
      equals(playIconSize),
    );
    expect(
      tester.widget<Icon>(find.byIcon(Icons.search_rounded)).size,
      equals(tester.widget<Icon>(find.byIcon(Icons.shuffle)).size),
    );
  });

  testWidgets('DetailEmptyPane and DetailNoMatchView render expected UI', (
    tester,
  ) async {
    var cleared = false;
    await tester.pumpWidget(
      _wrapWithApp(
        Column(
          children: [
            const DetailEmptyPane(
              icon: Icon(Icons.mic),
              label: 'No Artist Selected',
            ),
            DetailNoMatchView(
              message: 'No match',
              onClear: () => cleared = true,
            ),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.text('No Artist Selected'), findsOneWidget);
    expect(find.text('No match'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear_rounded));
    expect(cleared, isTrue);
  });
}
