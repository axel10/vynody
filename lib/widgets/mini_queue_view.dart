import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibe_flow/player/audio/audio_riverpod.dart';
import 'package:vibe_flow/models/music_file.dart';
import '../l10n/app_localizations.dart';

class MiniQueueView extends ConsumerWidget {
  const MiniQueueView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(audioPlaybackQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final audioService = ref.read(audioServiceProvider);
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? Colors.black.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.35),
        border: Border(
          top: BorderSide(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
            width: 1.0,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 12.0, bottom: 6.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${l10n.queue} (${queue.length})',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                if (queue.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(l10n.clearQueue),
                          content: Text(l10n.confirmClearQueue),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(l10n.cancel),
                            ),
                            TextButton(
                              onPressed: () {
                                audioService.clearPlaylist();
                                Navigator.pop(context);
                              },
                              child: Text(l10n.clearQueue),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Text(
                      l10n.clearQueue,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 0.5),
          Expanded(
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      l10n.queueEmpty,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: queue.length,
                    padding: const EdgeInsets.only(bottom: 16.0),
                    itemBuilder: (context, index) {
                      final song = queue[index];
                      final isCurrent = index == currentIndex;

                      return _MiniQueueTile(
                        song: song,
                        isCurrent: isCurrent,
                        onTap: () {
                          audioService.playAtIndex(index);
                        },
                        onRemove: () {
                          audioService.removeFromPlaylist(index);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _MiniQueueTile extends StatefulWidget {
  final MusicFile song;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _MiniQueueTile({
    required this.song,
    required this.isCurrent,
    required this.onTap,
    required this.onRemove,
  });

  @override
  State<_MiniQueueTile> createState() => _MiniQueueTileState();
}

class _MiniQueueTileState extends State<_MiniQueueTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                if (widget.isCurrent) ...[
                  Icon(
                    Icons.volume_up_rounded,
                    color: primaryColor,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.song.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: widget.isCurrent ? primaryColor : theme.colorScheme.onSurface,
                          fontWeight: widget.isCurrent ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.song.artist ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: widget.isCurrent
                              ? primaryColor.withValues(alpha: 0.7)
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (_isHovered)
                  IconButton(
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(28, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: theme.colorScheme.error.withValues(alpha: 0.8),
                    ),
                    onPressed: widget.onRemove,
                  )
                else
                  Text(
                    _formatDuration(widget.song.durationMillis),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: widget.isCurrent
                          ? primaryColor.withValues(alpha: 0.6)
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(int? durationMs) {
    if (durationMs == null) return '';
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
