import 'package:flutter/material.dart';
import 'package:vynody/player/settings/settings_service.dart';

class LyricsProviderIcon extends StatelessWidget {
  const LyricsProviderIcon({
    super.key,
    required this.provider,
    this.size = 36.0,
    this.padding,
  });

  final LyricsAiProvider provider;
  final double size;
  final double? padding;

  @override
  Widget build(BuildContext context) {
    if (provider == LyricsAiProvider.custom) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: size >= 30 ? 0.05 : 0.1),
              blurRadius: size >= 30 ? 3.0 : 2.0,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Icon(
          Icons.dns_outlined,
          color: Colors.grey.shade700,
          size: size * 0.6,
        ),
      );
    }

    final String iconPath = switch (provider) {
      LyricsAiProvider.googleAiStudio => 'assets/icons/lyrics/google.png',
      LyricsAiProvider.openRouter => 'assets/icons/lyrics/openrouter.png',
      LyricsAiProvider.doubao => 'assets/icons/lyrics/doubao.png',
      LyricsAiProvider.deepseek => 'assets/icons/lyrics/deepseek.png',
      LyricsAiProvider.custom => '',
    };

    final double effectivePadding = padding ?? (size * 5.0 / 36.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: size >= 30 ? 0.05 : 0.1),
            blurRadius: size >= 30 ? 3.0 : 2.0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      padding: EdgeInsets.all(effectivePadding),
      child: Image.asset(
        iconPath,
        fit: BoxFit.contain,
      ),
    );
  }
}
