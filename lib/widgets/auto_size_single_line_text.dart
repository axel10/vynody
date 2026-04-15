import 'dart:math' as math;

import 'package:flutter/material.dart';

class AutoSizeSingleLineText extends StatelessWidget {
  const AutoSizeSingleLineText(
    this.text, {
    super.key,
    required this.textAlign,
    this.maxLines = 1,
  });

  final String text;
  final TextAlign textAlign;
  final int maxLines;

  static const double _minScaleFactor = 0.82;
  static const double _absoluteMinFontSize = 12.0;
  static const double _fontSizeStep = 0.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final style = DefaultTextStyle.of(context).style;
        final baseFontSize = style.fontSize ?? 14.0;
        final targetFontSize = _resolveFontSize(
          context: context,
          text: text,
          style: style,
          maxWidth: constraints.maxWidth,
          baseFontSize: baseFontSize,
        );

        return Text(
          text,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          softWrap: maxLines > 1,
          style: style.copyWith(fontSize: targetFontSize),
        );
      },
    );
  }

  double _resolveFontSize({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required double maxWidth,
    required double baseFontSize,
  }) {
    if (!maxWidth.isFinite || maxWidth <= 0) {
      return baseFontSize;
    }

    final minFontSize = math.max(
      baseFontSize * _minScaleFactor,
      _absoluteMinFontSize,
    );

    if (_fits(
      context: context,
      text: text,
      style: style,
      fontSize: baseFontSize,
      maxWidth: maxWidth,
    )) {
      return baseFontSize;
    }

    for (
      double fontSize = baseFontSize - _fontSizeStep;
      fontSize >= minFontSize;
      fontSize -= _fontSizeStep
    ) {
      if (_fits(
        context: context,
        text: text,
        style: style,
        fontSize: fontSize,
        maxWidth: maxWidth,
      )) {
        return fontSize;
      }
    }

    return minFontSize;
  }

  bool _fits({
    required BuildContext context,
    required String text,
    required TextStyle style,
    required double fontSize,
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: fontSize),
      ),
      textDirection: Directionality.of(context),
      maxLines: maxLines,
      ellipsis: '…',
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    return !painter.didExceedMaxLines;
  }
}
