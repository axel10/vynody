import 'package:flutter/material.dart';

enum SectionItemType { songs, albums }

class SectionTypeToggle extends StatelessWidget {
  const SectionTypeToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.songsLabel,
    required this.albumsLabel,
  });

  final SectionItemType selected;
  final ValueChanged<SectionItemType> onChanged;
  final String songsLabel;
  final String albumsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPill(
            context,
            type: SectionItemType.songs,
            label: songsLabel,
            isSelected: selected == SectionItemType.songs,
          ),
          _buildPill(
            context,
            type: SectionItemType.albums,
            label: albumsLabel,
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
    required bool isSelected,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => onChanged(type),
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
