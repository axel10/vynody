import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vynody/player/audio/audio_riverpod.dart';
import 'package:vynody/player/audio/audio_service.dart';
import 'package:vynody/models/music_file.dart';
import '../l10n/app_localizations.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/utils/song_context_menu_utils.dart';
import 'package:vynody/widgets/queue_file_drop_target.dart';

const Color _miniQueuePanelBackgroundColor = Color.fromARGB(132, 0, 0, 0);
const Color _miniQueuePanelBorderColor = Color(0x14FFFFFF);
const Color _miniQueueTitleColor = Colors.white;
const Color _miniQueueEmptyTextColor = Color(0x80FFFFFF);
const Color _miniQueuePrimaryTextColor = Colors.white;
const Color _miniQueueSecondaryTextColor = Color(0xA6FFFFFF);
const Color _miniQueueDurationTextColor = Color(0x99FFFFFF);
const Color _miniQueueHoverColor = Color(0x0DFFFFFF);
const Color _miniQueueSeparatorColor = Color(0x1FFFFFFF);
const Color _miniQueueRemoveIconColor = Color(0xCCFF6B6B);
const Color _miniQueueCurrentTrackColor = Colors.white;
const Color _miniQueueCurrentTrackSecondaryColor = Color(0xB3FFFFFF);
const Color _miniQueueCurrentTrackDurationColor = Color(0x99FFFFFF);

class MiniQueueView extends ConsumerStatefulWidget {
  const MiniQueueView({super.key});

  @override
  ConsumerState<MiniQueueView> createState() => _MiniQueueViewState();
}

class _MiniQueueViewState extends ConsumerState<MiniQueueView> {
  final Map<String, GlobalKey> _itemKeys = {};

  GlobalKey _itemKeyForSong(MusicFile song) {
    return _itemKeys.putIfAbsent(
      song.path,
      () => GlobalKey(debugLabel: 'mini-queue-${song.path}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(audioPlaybackQueueProvider);
    final currentIndex = ref.watch(audioCurrentIndexProvider);
    final audioService = ref.read(audioServiceProvider);
    final playlistService = ref.read(playlistServiceProvider);
    final l10n = AppLocalizations.of(context)!;

    return QueueFileDropTarget(
      enabled: true,
      displayQueue: queue,
      queueSongs: queue,
      itemKeyBuilder: (index, song) => _itemKeyForSong(song),
      showPreview: true,
      child: Container(
        decoration: BoxDecoration(
          color: _miniQueuePanelBackgroundColor,
          border: Border(
            top: BorderSide(color: _miniQueuePanelBorderColor, width: 1.0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                top: 12.0,
                bottom: 6.0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${l10n.queue} (${queue.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _miniQueueTitleColor,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 0.5,
              color: _miniQueueSeparatorColor,
            ),
            Expanded(
              child: queue.isEmpty
                  ? Center(
                      child: Text(
                        l10n.queueEmpty,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _miniQueueEmptyTextColor,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: queue.length,
                      padding: const EdgeInsets.only(bottom: 16.0),
                      itemBuilder: (context, index) {
                        final song = queue[index];
                        final isCurrent = index == currentIndex;

                        return KeyedSubtree(
                          key: _itemKeyForSong(song),
                          child: _MiniQueueTile(
                            song: song,
                            isCurrent: isCurrent,
                            playlistService: playlistService,
                            audioService: audioService,
                            onTap: () {
                              audioService.playAtIndex(index);
                            },
                            onRemove: () {
                              audioService.removeFromPlaylist(index);
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniQueueTile extends StatefulWidget {
  final MusicFile song;
  final bool isCurrent;
  final PlaylistService playlistService;
  final AudioService audioService;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _MiniQueueTile({
    required this.song,
    required this.isCurrent,
    required this.playlistService,
    required this.audioService,
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
    void showMenuAt(Offset globalPosition) {
      final songs = <MusicFile>[widget.song];
      showSongContextMenu(
        context,
        globalPosition,
        song: widget.song,
        songs: songs,
        mode: SongContextMenuMode.full,
        onAddToPlaylist: () => showAddSongsToPlaylistDialog(
          context,
          widget.playlistService,
          songs,
        ),
        onPlayNext: widget.isCurrent
            ? null
            : () {
                final queueIndex = widget.audioService.playbackQueue.indexWhere(
                  (queuedSong) => queuedSong.path == widget.song.path,
                );
                final currentIndex = widget.audioService.currentIndex;
                if (queueIndex < 0 || currentIndex < 0) return;
                final insertIndex = queueIndex < currentIndex
                    ? currentIndex
                    : currentIndex + 1;
                widget.audioService.moveQueueTrack(queueIndex, insertIndex);
              },
        onRemoveFromQueue: () {
          final queueIndex = widget.audioService.playbackQueue.indexWhere(
            (queuedSong) => queuedSong.path == widget.song.path,
          );
          if (queueIndex >= 0) {
            widget.audioService.removeFromPlaylist(queueIndex);
          }
        },
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) => showMenuAt(details.globalPosition),
        onLongPressStart: (details) => showMenuAt(details.globalPosition),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor: _miniQueueHoverColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Row(
                children: [
                  if (widget.isCurrent) ...[
                    Icon(
                      Icons.volume_up_rounded,
                      color: _miniQueueCurrentTrackColor,
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: widget.isCurrent
                                    ? _miniQueueCurrentTrackColor
                                    : _miniQueuePrimaryTextColor,
                                fontWeight: widget.isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 13,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.song.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: widget.isCurrent
                                    ? _miniQueueCurrentTrackSecondaryColor
                                    : _miniQueueSecondaryTextColor,
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
                        color: _miniQueueRemoveIconColor,
                      ),
                      onPressed: widget.onRemove,
                    )
                  else
                    Text(
                      _formatDuration(widget.song.durationMillis),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: widget.isCurrent
                            ? _miniQueueCurrentTrackDurationColor
                            : _miniQueueDurationTextColor,
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
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
