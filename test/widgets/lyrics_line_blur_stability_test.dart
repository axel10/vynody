import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/lyric_line.dart';
import 'package:vynody/models/music_lyric.dart';
import 'package:vynody/models/music_lyric_translation.dart';
import 'package:vynody/player/lyrics/lyrics_controller_state.dart';
import 'package:vynody/widgets/lyrics_panel_views.dart';

/// 焦点模式下每行都会按 `|index - activeIndex|` 算模糊值。跳行时：
/// - 新当前行的模糊值从正数动画到 0
/// - 上一行的模糊值从 0 动画到正数
///
/// 只要模糊包装层在「0」这一步切换了 widget 类型（ImageFiltered ↔ 裸 child），
/// 整行子树就会被重建，行内 AppleLyricTranslationFadeIn 丢 State 重播淡入。
/// 这条测试把「模糊值归零也不能换层」钉住。
void main() {
  testWidgets('跳行让本行模糊值归零时不重建行内子树', (tester) async {
    const int lineCount = 8;
    final lines = List<LyricLine>.generate(
      lineCount,
      (i) => LyricLine(
        timestamp: Duration(seconds: i * 3),
        text: 'line $i',
        isTimed: true,
      ),
    );
    final translatedLines = List<String>.generate(lineCount, (i) => '译$i');
    final lyrics = MusicLyric(
      syncedLines: lines,
      translations: <String, MusicLyricTranslation>{
        'zh-cn': MusicLyricTranslation(
          languageCode: 'zh-cn',
          translatedText: translatedLines.join('\n'),
          translatedLines: translatedLines,
        ),
      },
    );

    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    Widget host(int activeIndex) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: LyricsPanelTimedLyricsView(
              lyrics: lyrics,
              lyricsState: const LyricsControllerState(
                lyricsTranslationLanguageCode: 'zh-cn',
              ),
              displayLines: lines,
              lineHeights: List<double>.filled(lineCount, 60),
              hasTimedLyrics: true,
              activeIndex: activeIndex,
              lyricsFontScale: 1.0,
              lyricsFontFamily: '',
              latinFontFamily: '',
              cjkFontFamily: '',
              showTranslation: true,
              showWordByWord: false,
              textColor: Colors.white,
              secondaryTextColor: Colors.white70,
              scrollController: scrollController,
              scrollBehavior: const MaterialScrollBehavior(),
              onContextMenu: (_) {},
              bottomSpacerHeight: 120,
              bottomTabBarHeight: 0,
              bottomReserveBase: 120,
              bottomReserveDelta: 0,
              isFocusMode: true,
              scrollDelta: 0,
              scrollTriggerTime: 0,
              isEnteringFocusMode: false,
              firstVisibleIndex: 0,
              isSmallWin: false,
              maxWidth: 400,
              isGenerating: false,
              isTranslating: true,
              isTranslationAppearing: false,
              isTransitioning: false,
              isLowMidEnd: false,
            ),
          ),
        ),
      );
    }

    Finder fadeOf(int index) => find.byWidgetPredicate(
      (widget) => widget is AppleLyricTranslationFadeIn && widget.index == index,
    );

    // activeIndex = 1：第 2 行是「非当前行」，模糊值 > 0
    await tester.pumpWidget(host(1));
    await tester.pump(const Duration(milliseconds: 600));
    final State before = tester.state(fadeOf(2));
    expect(before, isNotNull);

    // 跳到第 2 行：本行模糊值从正数动画到 0，必须跨过 0 也不换层
    await tester.pumpWidget(host(2));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    final State after = tester.state(fadeOf(2));
    expect(
      identical(before, after),
      isTrue,
      reason: '模糊值归零时不能重建行内子树，否则译文淡入会重播',
    );
  });
}
