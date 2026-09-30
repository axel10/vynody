import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';

class AppSnackBar {
  static void show(
    BuildContext context,
    WidgetRef? ref,
    SnackBar snackBar, {
    double? offset,
    Duration duration = const Duration(seconds: 3),
  }) {
    // Dismiss any active messenger snackbars if any were hanging around
    try {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (_) {}

    final effectiveDuration = snackBar.duration != const Duration(milliseconds: 4000)
        ? snackBar.duration
        : duration;

    final action = snackBar.action;
    final content = snackBar.content;

    // If there is an action, display a rich floating toast capsule with the action button
    if (action != null) {
      showToastWidget(
        Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            decoration: BoxDecoration(
              color: snackBar.backgroundColor ?? const Color(0xEB1C1D22),
              borderRadius: BorderRadius.circular(18.0),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16.0,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFF2F2F5),
                      height: 1.3,
                      letterSpacing: 0.15,
                    ),
                    child: content,
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {
                    dismissAllToast();
                    action.onPressed();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.0,
                    ),
                    child: Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: action.textColor ??
                            Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        context: context,
        duration: effectiveDuration,
        handleTouch: true,
      );
      return;
    }

    // If content is plain Text, use global styled showToast
    if (content is Text) {
      final text = content.data ?? content.textSpan?.toPlainText() ?? '';
      if (text.isNotEmpty) {
        showToast(
          text,
          duration: effectiveDuration,
          context: context,
        );
        return;
      }
    }

    // Otherwise render widget inside toast widget
    showToastWidget(
      Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 11.0),
          decoration: BoxDecoration(
            color: snackBar.backgroundColor ?? const Color(0xEB1C1D22),
            borderRadius: BorderRadius.circular(18.0),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16.0,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFFF2F2F5),
              height: 1.3,
              letterSpacing: 0.15,
            ),
            child: content,
          ),
        ),
      ),
      context: context,
      duration: effectiveDuration,
    );
  }
}

