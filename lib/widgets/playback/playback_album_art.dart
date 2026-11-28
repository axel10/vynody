import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/utils/app_snack_bar.dart';
import 'package:vynody/utils/artwork_export_helper.dart';
import 'package:vynody/widgets/cover_carousel.dart';
import 'package:vynody/widgets/app_context_menu.dart';
import '../../l10n/app_localizations.dart';

class PlaybackAlbumArt extends ConsumerWidget {
  final double currentSize;
  final double? cacheWidthSize;
  final Rect? endRect;
  final bool isLandscape;
  final bool isNext;
  final VoidCallback? onCoverTap;
  final void Function(Uint8List? artworkBytes, String? sourcePath)?
      onCarouselAnimationComplete;

  const PlaybackAlbumArt({
    super.key,
    required this.currentSize,
    this.cacheWidthSize,
    this.endRect,
    this.isLandscape = false,
    this.isNext = true,
    this.onCoverTap,
    this.onCarouselAnimationComplete,
  });

  Future<void> _showCoverContextMenu(
    BuildContext context,
    WidgetRef ref,
    Offset globalPosition,
    MusicFile? currentMusic,
  ) async {
    if (currentMusic == null) return;

    final l10n = AppLocalizations.of(context)!;
    final audioService = ref.read(audioServiceProvider);
    final bytes =
        currentMusic.artworkBytes ??
        audioService.getCachedArtwork(currentMusic.path);
    final String? path = currentMusic.artworkPath ?? currentMusic.thumbnailPath;
    final bool hasCover =
        (bytes != null && bytes.isNotEmpty) ||
        (path != null && File(path).existsSync());

    final selected = await AppContextMenu.show<String>(
      context: context,
      position: globalPosition,
      items: [
        buildContextMenuItem<String>(
          value: 'copy_cover',
          enabled: hasCover,
          label: l10n.copyCover,
          icon: Icons.image_outlined,
          context: context,
        ),
        buildContextMenuItem<String>(
          value: 'export_cover',
          enabled: hasCover,
          label: l10n.exportArtwork,
          icon: Icons.file_download_outlined,
          context: context,
        ),
      ],
    );

    if (!context.mounted || selected == null) return;

    if (selected == 'copy_cover') {
      try {
        final resolvedBytes = await ArtworkExportHelper.resolveCoverBytes(
          bytes: bytes,
          filePath: path,
        );
        if (resolvedBytes != null) {
          await Pasteboard.writeImage(resolvedBytes);
          if (context.mounted) {
            AppSnackBar.show(
              context,
              ref,
              SnackBar(content: Text(l10n.copyCoverSuccess)),
            );
          }
        } else if (context.mounted) {
          AppSnackBar.show(
            context,
            ref,
            SnackBar(content: Text(l10n.copyCoverFailed)),
          );
        }
      } catch (e) {
        debugPrint('Failed to copy cover to clipboard: $e');
        if (context.mounted) {
          AppSnackBar.show(
            context,
            ref,
            SnackBar(content: Text(l10n.copyCoverFailed)),
          );
        }
      }
    } else if (selected == 'export_cover') {
      try {
        final resolvedBytes = await ArtworkExportHelper.resolveCoverBytes(
          bytes: bytes,
          filePath: path,
        );
        if (resolvedBytes == null) {
          if (context.mounted) {
            AppSnackBar.show(
              context,
              ref,
              SnackBar(content: Text(l10n.exportArtworkFailed)),
            );
          }
          return;
        }
        final title = currentMusic.title?.trim().isNotEmpty == true
            ? currentMusic.title!.trim()
            : currentMusic.displayName;
        final artist = currentMusic.artist?.trim();
        final savedPath = await ArtworkExportHelper.exportCoverBytes(
          bytes: resolvedBytes,
          artist: artist,
          title: title,
        );
        if (savedPath != null && context.mounted) {
          AppSnackBar.show(
            context,
            ref,
            SnackBar(content: Text(l10n.exportArtworkSuccess)),
          );
        }
      } catch (e) {
        debugPrint('Failed to export cover to file: $e');
        if (context.mounted) {
          AppSnackBar.show(
            context,
            ref,
            SnackBar(content: Text(l10n.exportArtworkFailed)),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlist = ref.watch(audioPlaybackQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    if (playlist.isEmpty || currentIndex < 0 || currentIndex >= playlist.length) {
      return Center(
        child: Container(
          width: currentSize * 0.8,
          height: currentSize * 0.8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(
              math.min(24.0, currentSize * 0.2),
            ),
            color: Colors.black87,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 40,
                spreadRadius: 0,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(Icons.music_note, size: 80, color: Colors.white54),
        ),
      );
    }

    final cover = Material(
      type: MaterialType.transparency,
      child: ExcludeSemantics(
        child: CoverCarousel(
          playlist: playlist,
          currentIndex: currentIndex,
          audioService: ref.read(audioServiceProvider),
          isLandscape: isLandscape,
          isNext: isNext,
          displaySize: currentSize,
          cacheWidthSize: cacheWidthSize,
          endRect: endRect,
          onPageChanged: (page) {
            final audio = ref.read(audioServiceProvider);
            if (page >= 0 && page < playlist.length && page != currentIndex) {
              audio.playAtIndex(page);
            }
          },
          onAnimationComplete: onCarouselAnimationComplete,
        ),
      ),
    );

    final currentMusic = ref.watch(audioCurrentMusicProvider);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCoverTap,
      onSecondaryTapDown: (details) {
        _showCoverContextMenu(
          context,
          ref,
          details.globalPosition,
          currentMusic,
        );
      },
      onLongPressStart: (details) {
        _showCoverContextMenu(
          context,
          ref,
          details.globalPosition,
          currentMusic,
        );
      },
      child: cover,
    );
  }
}
