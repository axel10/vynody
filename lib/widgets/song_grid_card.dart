import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../models/music_file.dart';
import '../l10n/app_localizations.dart';
import '../utils/time_format_utils.dart';
import '../widgets/song_thumbnail.dart';
import '../widgets/playing_equalizer_icon.dart';
import '../player/audio/audio_riverpod.dart';
import 'remote_media_badge.dart';
import 'draggable_song_item.dart';
import 'library_selection_scope.dart';

/// Borderless song card for grid layouts, matching [AlbumGridCard] and
/// [FolderGridCard] so every grid in the app shares one typography rhythm.
class SongGridCard extends ConsumerWidget {
  const SongGridCard({
    super.key,
    required this.song,
    required this.isCurrent,
    required this.isPlaying,
    this.isSelected,
    this.isSelectionMode,
    this.selectedPaths,
    this.isHighlighted = false,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
  });

  final MusicFile song;
  final bool isCurrent;
  final bool isPlaying;
  final bool? isSelected;
  final bool? isSelectionMode;
  final Iterable<String>? selectedPaths;
  final bool isHighlighted;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(TapDownDetails)? onSecondaryTapDown;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final isWide = MediaQuery.of(context).size.width >= 780;

    final isGlobalSelectionActive = ref.watch(
      librarySelectionStateProvider.select(
        (s) => s.isActive && s.scope != LibrarySelectionScope.none,
      ),
    );
    final isGlobalSongSelected = isGlobalSelectionActive
        ? ref.watch(
            librarySelectionStateProvider.select(
              (s) => s.selectedKeys.contains(song.path),
            ),
          )
        : false;

    final effectiveSelectionMode = isSelectionMode ?? isGlobalSelectionActive;
    final effectiveSelected = isSelected ??
        selectedPaths?.contains(song.path) ??
        isGlobalSongSelected;

    VoidCallback? effectiveOnTap = onTap;
    if (effectiveOnTap == null && effectiveSelectionMode) {
      effectiveOnTap = () {
        ref.read(librarySelectionStateProvider.notifier).toggle(song.path);
      };
    }

    final metadata = ref.watch(
      scannerServiceProvider.select((s) => s.metadataMap[song.path]),
    );

    // Resolve metadata (artist and album)
    final artist = metadata?.artist ?? song.artist ?? l10n.unknownArtist;
    final album = metadata?.album ?? song.album ?? l10n.unknownAlbum;
    final artistAlbumText = '$artist - $album';

    // Format duration and file format
    final durationStr = (metadata?.duration ?? song.durationMillis).toFormattedDuration();
    final ext = p.extension(song.path).replaceAll('.', '').toUpperCase();
    final formatStr = ext.isNotEmpty ? ext : 'UNKNOWN';

    final isDark = theme.brightness == Brightness.dark;
    final capsuleBgColor = isDark
        ? Colors.black.withValues(alpha: 0.6)
        : Colors.white.withValues(alpha: 0.75);
    final capsuleTextColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black.withValues(alpha: 0.9);

    final titleColor = isCurrent ? theme.colorScheme.primary : null;
    final coverRadius = BorderRadius.circular(12);

    final coverStack = ClipRRect(
      borderRadius: coverRadius,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: Hero(
                tag: 'song-cover-${song.path}',
                child: RemoteMediaBadge.wrapCover(
                  child: SongThumbnail.fromSong(
                    song,
                    size: 200,
                    width: double.infinity,
                    height: double.infinity,
                    // Hero flights are painted outside the card's clip, so the
                    // artwork itself must carry the cover's corner radius.
                    borderRadius: coverRadius,
                  ),
                  song: song,
                  title: song.displayName,
                  top: 8,
                  right: 8,
                ),
              ),
            ),
            if (isHighlighted)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: coverRadius,
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            if (effectiveSelectionMode)
              Positioned.fill(
                child: Container(
                  color: effectiveSelected
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                      : Colors.black26,
                ),
              ),
            if (effectiveSelectionMode)
              Positioned(
                top: 8,
                left: 8,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: effectiveSelected,
                    onChanged: (_) => effectiveOnTap?.call(),
                    fillColor: WidgetStateProperty.all(Colors.white),
                    checkColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            // Format / duration capsule in the bottom-left corner
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: capsuleBgColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '$formatStr • $durationStr',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: capsuleTextColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final card = MouseRegion(
      cursor: effectiveOnTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: effectiveOnTap,
        onLongPress: onLongPress,
        onSecondaryTapDown: onSecondaryTapDown,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            coverStack,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          PlayingEqualizerIcon(
                            color: theme.colorScheme.primary,
                            size: 16,
                            isPlaying: isPlaying,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            song.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (isPortrait
                                    ? theme.textTheme.titleSmall
                                    : theme.textTheme.titleMedium)
                                ?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: isWide ? 14.5 : 14.0,
                              color: titleColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artistAlbumText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (isPortrait
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.bodyMedium)
                          ?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return DraggableSongItem(
      song: song,
      enabled: true,
      isSelected: effectiveSelected,
      isSelectionMode: effectiveSelectionMode,
      selectedPaths: selectedPaths,
      child: card,
    );
  }
}
