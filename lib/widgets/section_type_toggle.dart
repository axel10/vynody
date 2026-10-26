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
    this.fullWidth = false,
  });

  final SectionItemType selected;
  final ValueChanged<SectionItemType> onChanged;
  final String songsLabel;
  final String albumsLabel;
  final bool compact;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: fullWidth ? double.infinity : null,
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
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _buildItem(
            context,
            type: SectionItemType.songs,
            label: songsLabel,
            icon: Icons.music_note_rounded,
            isSelected: selected == SectionItemType.songs,
          ),
          SizedBox(width: compact ? 2 : 4),
          _buildItem(
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

  Widget _buildItem(
    BuildContext context, {
    required SectionItemType type,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    final pill = _buildPill(
      context,
      type: type,
      label: label,
      icon: icon,
      isSelected: isSelected,
    );
    if (fullWidth) {
      return Expanded(child: pill);
    }
    return pill;
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
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: compact ? 14 : 16,
                color: fgColor,
              ),
              SizedBox(width: compact ? 4 : 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (compact ? theme.textTheme.labelSmall : theme.textTheme.labelMedium)?.copyWith(
                    color: fgColor,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
