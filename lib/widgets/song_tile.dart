import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:vibe_flow/models/music_file.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/widgets/song_thumbnail.dart';
import 'package:vibe_flow/l10n/app_localizations.dart';

class SongTile extends ConsumerWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.isCurrent,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.dragHandle,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.onMorePressed,
  });

  final MusicFile song;
  final bool isCurrent;
  final bool isSelected;
  final bool isSelectionMode;
  final Widget? dragHandle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails details)? onSecondaryTapDown;
  final void Function(BuildContext context)? onMorePressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final scanner = ref.watch(scannerServiceProvider);
    
    final isMissing = song.isMissing;
    
    // Resolve metadata (artist and album)
    final metadata = scanner.metadataMap[song.path];
    final artist = metadata?.artist ?? song.artist ?? l10n.unknownArtist;
    final album = metadata?.album ?? song.album ?? l10n.unknownAlbum;
    final artistAlbumText = '$artist - $album';

    // Format duration and file format
    final durationStr = _formatDuration(metadata?.duration ?? song.durationMillis);
    final ext = p.extension(song.path).replaceAll('.', '').toUpperCase();
    final formatStr = ext.isNotEmpty ? ext : 'UNKNOWN';
    final durationFormatText = '$durationStr | $formatStr';

    // Build leading widget (thumbnail + selection checkbox)
    final leadingWidget = SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: isMissing
                ? 0.35
                : isSelectionMode
                    ? (isSelected ? 0.5 : 0.7)
                    : 1.0,
            child: SongThumbnail(
              path: song.path,
              id: song.id,
              size: 40.0,
            ),
          ),
          if (isSelectionMode)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onTap?.call(),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    // Build trailing widget (more button or drag handle)
    Widget? trailingWidget;
    if (isSelectionMode) {
      trailingWidget = dragHandle;
    } else {
      trailingWidget = Builder(
        builder: (buttonContext) {
          return IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: onMorePressed != null
                ? () => onMorePressed!(buttonContext)
                : null,
          );
        },
      );
    }

    // Colors
    final textColor = isMissing
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : isCurrent
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapDown: onSecondaryTapDown,
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
        selected: isSelectionMode && isSelected,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        leading: leadingWidget,
        title: Row(
          children: [
            if (isCurrent && !isMissing) ...[
              Icon(
                Icons.volume_up_rounded,
                color: theme.colorScheme.primary,
                size: 16,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                song.displayName,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: textColor,
                  fontWeight: isCurrent && !isMissing ? FontWeight.bold : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 2),
            Text(
              artistAlbumText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                color: isMissing
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)
                    : theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              durationFormatText,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: isMissing
                    ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              maxLines: 1,
            ),
          ],
        ),
        isThreeLine: true,
        trailing: trailingWidget,
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return '--:--';
    final duration = Duration(milliseconds: durationMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
