import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/models/music_lyric.dart';
import 'package:vynody/models/music_lyric_translation.dart';
import 'package:vynody/widgets/lyrics_panel_views.dart';

/// 面板行内译文必须画 `effectiveTranslationLanguage` 指的那一条。
///
/// 这条测试守的是一次真实事故：视图自己从 `state.lyricsTranslationLanguageCode`
/// （全局默认目标语言）重新推导展示语言，于是「右键切了韩语、面板还是英语」——
/// 全局默认是 en 且 en 有内容时，`getEffectiveTranslationLanguage` 必然返回 en，
/// 逐曲选择被彻底绕过。现在语言只由调用方用唯一入口算好再传，视图不再自行推导。
void main() {
  MusicLyric buildLyrics() {
    final lines = List<LyricLine>.generate(
      3,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 3),
        text: 'line $i',
        isTimed: true,
      ),
    );
    return MusicLyric(
      syncedLines: lines,
      translations: <String, MusicLyricTranslation>{
        'en': MusicLyricTranslation(
          languageCode: 'en',
          translatedText: 'english 0\nenglish 1\nenglish 2',
          translatedLines: const ['english 0', 'english 1', 'english 2'],
        ),
        'ko': MusicLyricTranslation(
          languageCode: 'ko',
          translatedText: 'korean 0\nkorean 1\nkorean 2',
          translatedLines: const ['korean 0', 'korean 1', 'korean 2'],
        ),
      },
    );
  }

  Widget host({
    required MusicLyric lyrics,
    required String effectiveTranslationLanguage,
  }) {
    final lines = lyrics.syncedLines;
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 600,
          child: LyricsPanelTimedLyricsView(
            lyrics: lyrics,
            effectiveTranslationLanguage: effectiveTranslationLanguage,
            displayLines: lines,
            lineHeights: List<double>.filled(lines.length, 60),
            hasTimedLyrics: true,
            activeIndex: 0,
            lyricsFontScale: 1.0,
            lyricsFontFamily: '',
            latinFontFamily: '',
            cjkFontFamily: '',
            showTranslation: true,
            showWordByWord: false,
            textColor: Colors.white,
            secondaryTextColor: Colors.white70,
            scrollController: ScrollController(),
            scrollBehavior: const MaterialScrollBehavior(),
            onContextMenu: (_) {},
            bottomSpacerHeight: 0,
            bottomTabBarHeight: 0,
            bottomReserveBase: 0,
            bottomReserveDelta: 0,
            isFocusMode: false,
            scrollDelta: 0,
            scrollTriggerTime: 0,
            isEnteringFocusMode: false,
            firstVisibleIndex: 0,
            isSmallWin: false,
            maxWidth: 400,
            isGenerating: false,
            isTranslating: false,
            isTranslationAppearing: false,
            isTransitioning: false,
            isLowMidEnd: false,
          ),
        ),
      ),
    );
  }

  testWidgets('传入韩语时画韩语译文，且不残留英语', (tester) async {
    final lyrics = buildLyrics();

    await tester.pumpWidget(
      host(lyrics: lyrics, effectiveTranslationLanguage: 'ko'),
    );
    await tester.pumpAndSettle();

    expect(find.text('korean 0'), findsOneWidget);
    expect(find.text('korean 2'), findsOneWidget);
    expect(find.text('english 0'), findsNothing);

    // 切到英语：同一棵子树改成英语，韩语不许残留。
    await tester.pumpWidget(
      host(lyrics: lyrics, effectiveTranslationLanguage: 'en'),
    );
    await tester.pumpAndSettle();

    expect(find.text('english 0'), findsOneWidget);
    expect(find.text('korean 0'), findsNothing);
  });
}
