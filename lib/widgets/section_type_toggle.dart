import 'package:flutter/material.dart';

enum SectionItemType { songs, albums }

class SectionTypeToggle extends StatelessWidget {
  const SectionTypeToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.songsLabel,
    required this.albumsLabel,
    this.compact = false,
  });

  final SectionItemType selected;
  final ValueChanged<SectionItemType> onChanged;
  final String songsLabel;
  final String albumsLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(compact ? 2.5 : 3.5),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPill(
            context,
            type: SectionItemType.songs,
            label: songsLabel,
            icon: Icons.music_note_rounded,
            isSelected: selected == SectionItemType.songs,
          ),
          SizedBox(width: compact ? 2 : 4),
          _buildPill(
            context,
            type: SectionItemType.albums,
            label: albumsLabel,
            icon: Icons.album_rounded,
            isSelected: selected == SectionItemType.albums,
          ),
        ],
      ),
    );
  }

  Widget _buildPill(
    BuildContext context, {
    required SectionItemType type,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgColor = isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant;
    const borderRadius = BorderRadius.all(Radius.circular(100));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(type),
        borderRadius: borderRadius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 4 : 7,
          ),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            borderRadius: borderRadius,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.28),
                      blurRadius: 6,
                      offset: const Offset(0, 1.5),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: compact ? 14 : 16,
                color: fgColor,
              ),
              SizedBox(width: compact ? 4 : 6),
              Text(
                label,
                style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)?.copyWith(
                  color: fgColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
