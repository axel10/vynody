import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ScanToastState {
  const ScanToastState({
    required this.fileName,
    required this.discoveredLabelText,
    required this.preprocessedLabelText,
    required this.completedLabelText,
  });

  final String fileName;
  final String discoveredLabelText;
  final String preprocessedLabelText;
  final String completedLabelText;
}

class ScanProgressToast extends StatelessWidget {
  const ScanProgressToast({
    super.key,
    required this.label,
    required this.stateListenable,
    this.onClose,
  });

  final String label;
  final ValueListenable<ScanToastState?> stateListenable;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1F1F1F) : Colors.white;
    final onSurface = isDark ? Colors.white : Colors.black;
    final accent = theme.colorScheme.primary;

    return ValueListenableBuilder<ScanToastState?>(
      valueListenable: stateListenable,
      builder: (context, state, _) {
        final fileName = state?.fileName ?? '';
        final discoveredLabel = state?.discoveredLabelText ?? '';
        final preprocessedLabel = state?.preprocessedLabelText ?? '';
        final completedLabel = state?.completedLabelText ?? '';
        final summaryText = [
          discoveredLabel,
          preprocessedLabel,
          completedLabel,
        ].where((text) => text.isNotEmpty).join(' · ');

        return Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.14),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: null,
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                    backgroundColor: onSurface.withValues(alpha: 0.12),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: onSurface,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        summaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: onSurface.withValues(alpha: 0.8),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onClose != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    splashRadius: 16,
                    color: onSurface.withValues(alpha: 0.6),
                    onPressed: onClose,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
