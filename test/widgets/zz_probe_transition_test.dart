import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/widgets/artwork_fade.dart';
import 'package:vynody/widgets/default_cover_art.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

void main() {
  testWidgets('transition deferred no-cover fade in', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );

    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (ctx, __, ___) {
          final r = ModalRoute.of(ctx);
          debugPrint('PROBE pageBuilder route=${r.runtimeType} anim=${r?.animation?.status} value=${r?.animation?.value} dur=${r?.transitionDuration}');
          return const Scaffold(
          body: Center(
            child: SongThumbnail(path: '/music/no_cover_transition.mp3', size: 56),
          ),
        );
        },
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    debugPrint('phase1 icon=${find.byType(DefaultCoverArt).evaluate().length}');
    for (int i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 50));
      final n = find.byType(DefaultCoverArt).evaluate().length;
      if (n > 0) {
        debugPrint('icon appeared at iter $i');
        break;
      }
    }
    final scoped = find.descendant(of: find.byType(SongThumbnail), matching: find.byType(AnimatedOpacity));
    final f = tester.widget<AnimatedOpacity>(scoped.first);
    debugPrint('final icon=${find.byType(DefaultCoverArt).evaluate().length} opacity=${f.opacity} dur=${f.duration} kArtwork=$kArtworkFadeInDuration');
  });
}
