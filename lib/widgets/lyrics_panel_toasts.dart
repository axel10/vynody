import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class LyricsStatusToast extends StatelessWidget {
  const LyricsStatusToast({
    super.key,
    required this.modelLabel,
    required this.statusLabel,
    required this.accentColor,
  });

  final String modelLabel;
  final String statusLabel;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final onSurface = isDark ? Colors.white : Colors.black;
    final colorScheme = theme.colorScheme;
    final (providerLabel, modelNameLabel) = _splitModelLabel(modelLabel);

    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? (constraints.maxWidth - 32).clamp(0.0, 380.0).toDouble()
              : 380.0;

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.14,
                      ),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            value: null,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              accentColor.withValues(alpha: 0.9),
                            ),
                            backgroundColor: onSurface.withValues(alpha: 0.12),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            statusLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: onSurface,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (providerLabel.isNotEmpty ||
                        modelNameLabel.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _InfoPill(
                            label: l10n?.providerLabel ?? 'Provider',
                            value: providerLabel,
                            accentColor: accentColor,
                            theme: theme,
                            surface: colorScheme.surfaceContainerHighest,
                          ),
                          _InfoPill(
                            label: l10n?.modelLabel ?? 'Model',
                            value: modelNameLabel,
                            accentColor: accentColor,
                            theme: theme,
                            surface: colorScheme.surfaceContainerHighest,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  (String, String) _splitModelLabel(String label) {
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      return ('', '');
    }

    final delimiterIndex = trimmed.indexOf(' · ');
    if (delimiterIndex < 0) {
      return (trimmed, '');
    }

    return (
      trimmed.substring(0, delimiterIndex).trim(),
      trimmed.substring(delimiterIndex + 3).trim(),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.label,
    required this.value,
    required this.accentColor,
    required this.theme,
    required this.surface,
  });

  final String label;
  final String value;
  final Color accentColor;
  final ThemeData theme;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isNotEmpty ? value : (l10n?.unspecified ?? 'Not specified'),
            softWrap: true,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

class LyricsSeekToast extends StatelessWidget {
  const LyricsSeekToast({
    super.key,
    required this.stateListenable,
    required this.accentColor,
  });

  final ValueNotifier<({Duration target, String timeLabel})> stateListenable;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final onSurface = isDark ? Colors.white : Colors.black;

    return Material(
      color: Colors.transparent,
      child: ValueListenableBuilder<({Duration target, String timeLabel})>(
        valueListenable: stateListenable,
        builder: (context, state, _) {
          return Container(
            constraints: const BoxConstraints(maxWidth: 240),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withValues(alpha: 0.24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: accentColor),
                const SizedBox(width: 10),
                Text(
                  state.timeLabel,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
