import 'package:flutter/material.dart';
import 'package:vynody/l10n/app_localizations.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/widgets/app_tooltip.dart';
import 'package:vynody/widgets/song_thumbnail.dart';

/// Unified song tile for Desktop Queue Drawer and Standalone Queue Window.
/// Supports both queue items and playlist items, with hover states,
/// selection mode, reorder handle, and duration / remove actions.
class QueueSongTile extends StatefulWidget {
  final MusicFile song;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final String? artistOverride;
  final String? albumOverride;
  final bool isSelected;
  final bool isSelectionMode;
  final String durationFormatted;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onToggleSelect;
  final ValueChanged<Offset> onSecondaryTap;
  final VoidCallback onRemove;
  final String? removeTooltip;
  final bool showDragHandle;
  final bool isPlaylistSong;

  const QueueSongTile({
    super.key,
    required this.song,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    this.artistOverride,
    this.albumOverride,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.durationFormatted,
    required this.onTap,
    this.onLongPress,
    this.onToggleSelect,
    required this.onSecondaryTap,
    required this.onRemove,
    this.removeTooltip,
    this.showDragHandle = true,
    this.isPlaylistSong = false,
  });

  @override
  State<QueueSongTile> createState() => _QueueSongTileState();
}

class _QueueSongTileState extends State<QueueSongTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final song = widget.song;

    final unknownArtistText = l10n?.unknownArtist ?? '未知艺术家';
    final artist = (widget.artistOverride ?? song.artist)?.trim();
    final album = (widget.albumOverride ?? song.album)?.trim();
    final displayArtist = (artist != null && artist.isNotEmpty) ? artist : unknownArtistText;
    final displayAlbum = (album != null && album.isNotEmpty) ? album : null;
    final subtitleText =
        displayAlbum != null ? '$displayArtist - $displayAlbum' : displayArtist;

    final itemColor = widget.isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : (widget.isCurrent
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.28)
            : (_isHovered
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
                : Colors.transparent));

    final defaultRemoveTooltip = widget.isPlaylistSong
        ? (l10n?.removeFromPlaylist ?? '从歌单移除')
        : (l10n?.removeFromQueue ?? '从队列移除');

    return Material(
      color: itemColor,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapUp: (details) => widget.onSecondaryTap(details.globalPosition),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor.withValues(alpha: 0.05),
                ),
                left: widget.isSelected
                    ? BorderSide(
                        color: theme.colorScheme.primary,
                        width: 3.0,
                      )
                    : BorderSide.none,
              ),
            ),
            child: Row(
              children: [
                if (widget.showDragHandle)
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: _isHovered ? 0.6 : 0.25,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Opacity(
                                opacity: widget.isSelectionMode
                                    ? (widget.isSelected ? 0.5 : 0.7)
                                    : 1.0,
                                child: SongThumbnail.fromSong(
                                  song,
                                  size: 36.0,
                                ),
                              ),
                              if (widget.isSelectionMode)
                                Positioned.fill(
                                  child: Align(
                                    alignment: Alignment.center,
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: Checkbox(
                                        value: widget.isSelected,
                                        onChanged: (_) => widget.onToggleSelect?.call(),
                                        fillColor: WidgetStateProperty.all(Colors.white),
                                        checkColor: Colors.black,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (widget.isCurrent) ...[
                                  Icon(
                                    widget.isPlaying
                                        ? Icons.volume_up_rounded
                                        : Icons.pause_rounded,
                                    size: 14,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    song.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: widget.isCurrent
                                          ? FontWeight.bold
                                          : (widget.isPlaylistSong ? FontWeight.w500 : FontWeight.normal),
                                      color: widget.isCurrent
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: widget.isPlaylistSong ? 11.5 : 11,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (_isHovered && !widget.isSelectionMode)
                  AppTooltip(
                    message: widget.removeTooltip ?? defaultRemoveTooltip,
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: widget.onRemove,
                      visualDensity: VisualDensity.compact,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else if ((song.durationMillis ?? 0) > 0 || widget.durationFormatted.isNotEmpty)
                  Text(
                    widget.durationFormatted,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
