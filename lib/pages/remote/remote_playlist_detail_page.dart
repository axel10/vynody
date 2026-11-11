import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oktoast/oktoast.dart';

import '../../models/music_file.dart';
import '../../player/metadata/metadata_database.dart';
import '../../player/audio/audio_riverpod.dart';
import '../../player/audio/playback_source.dart';
import '../../player/remote/remote_server_models.dart';
import '../../player/remote/remote_server_riverpod.dart';
import '../../player/remote/clients/remote_media_library_client.dart';
import '../../player/remote/proxy/remote_media_resolver.dart';
import '../../player/remote/services/remote_download_service.dart';
import '../../player/platform/right_queue_drawer_controller.dart';
import '../../widgets/remote_artwork_widget.dart';
import '../../player/remote/remote_library_navigation.dart';
import '../../l10n/app_localizations.dart';
import '../../dialogs/remote_track_load_progress_dialog.dart';
import '../../utils/app_snack_bar.dart';
import '../../utils/remote_context_menu_utils.dart';
import '../../utils/remote_download_feedback.dart';
import '../../widgets/library_selection_scope.dart';
import '../../widgets/playback_ui_tuning.dart';
import '../../widgets/remote_page_shell.dart';
import 'remote_download_manager_page.dart';
import 'widgets/remote_song_selection_panel.dart';
import '../../widgets/app_top_nav_bar.dart';
import '../../widgets/folder_layout_utils.dart';
import '../../widgets/folder_zoom_gesture_layer.dart';
import '../../widgets/song_zoom_item.dart';
import '../../widgets/zoom_reorder_ui.dart';
import '../../widgets/drag/drag_cover.dart';
import '../../widgets/drag/drag_payload.dart';
import '../../widgets/drag/drag_preview_card.dart';
import '../../utils/drop_data_utils.dart';

/// Standalone Full-Page for Remote Playlist Detail
class RemotePlaylistDetailPage extends ConsumerWidget {
  final RemoteServer server;
  final String password;
  final String playlistId;
  final String playlistName;
  final String? coverArtId;
  final int? songCount;
  final int? duration;
  final bool isStarred;
  final String? highlightedSongPath;
  final VoidCallback? onPlaylistModified;
  final VoidCallback? onGoBack;

  const RemotePlaylistDetailPage({
    super.key,
    required this.server,
    required this.password,
    required this.playlistId,
    required this.playlistName,
    this.coverArtId,
    this.songCount,
    this.duration,
    this.isStarred = false,
    this.highlightedSongPath,
    this.onPlaylistModified,
    this.onGoBack,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RemotePlaylistDetailContent(
      server: server,
      password: password,
      playlistId: playlistId,
      playlistName: playlistName,
      coverArtId: coverArtId,
      songCount: songCount,
      duration: duration,
      isStarred: isStarred,
      highlightedSongPath: highlightedSongPath,
      onPlaylistModified: onPlaylistModified,
      onGoBack: onGoBack,
      onDeleted: () {
        if (onGoBack != null) {
          onGoBack!();
        } else {
          Navigator.of(context).maybePop();
        }
      },
    );
  }
}

/// Content Widget for Remote Playlist Detail
class RemotePlaylistDetailContent extends ConsumerStatefulWidget {
  final RemoteServer server;
  final String password;
  final String playlistId;
  final String playlistName;
  final String? coverArtId;
  final int? songCount;
  final int? duration;
  final bool isStarred;
  final String? highlightedSongPath;
  final VoidCallback? onPlaylistModified;
  final VoidCallback? onDeleted;
  final VoidCallback? onGoBack;

  const RemotePlaylistDetailContent({
    super.key,
    required this.server,
    required this.password,
    required this.playlistId,
    required this.playlistName,
    this.coverArtId,
    this.songCount,
    this.duration,
    this.isStarred = false,
    this.highlightedSongPath,
    this.onPlaylistModified,
    this.onDeleted,
    this.onGoBack,
  });

  @override
  ConsumerState<RemotePlaylistDetailContent> createState() =>
      _RemotePlaylistDetailContentState();
}

class _RemotePlaylistDetailContentState
    extends ConsumerState<RemotePlaylistDetailContent>
    with
        SelectionStateMixin<RemotePlaylistDetailContent, String>,
        SongSelectionMixin<RemotePlaylistDetailContent> {
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _playlistData;
  List<MusicFile> _tracks = [];
  late String _currentName;
  final ScrollController _scrollController = ScrollController();
  final Set<String> _starredSongIds = {};
  String? _highlightedSongPath;
  Timer? _highlightTimer;
  bool _isRevalidating = false;
  final ZoomReorderController _reorderController = ZoomReorderController();

  void _handleBack() {
    if (widget.onGoBack != null) {
      widget.onGoBack!();
    } else if (widget.onDeleted != null) {
      widget.onDeleted!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  bool _tracksEqual(List<MusicFile> a, List<MusicFile> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].path != b[i].path) return false;
    }
    return true;
  }

  Future<void> _deleteSelectedSongs() async {
    final selectedIndices = <int>[];
    for (int i = 0; i < _tracks.length; i++) {
      if (isSongSelected(_tracks[i].path)) {
        selectedIndices.add(i);
      }
    }
    if (selectedIndices.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final client = RemoteMediaLibraryClient.create(
      server: widget.server,
      password: widget.password,
    );
    final success = await client.updatePlaylist(
      playlistId: widget.playlistId,
      songIndexesToRemove: selectedIndices,
    );
    if (success) {
      setState(() {
        final sortedIndices = List<int>.from(selectedIndices)
          ..sort((a, b) => b.compareTo(a));
        for (final idx in sortedIndices) {
          if (idx >= 0 && idx < _tracks.length) {
            _tracks.removeAt(idx);
          }
        }
      });
      cancelSongSelection();
      final activeSession = ref.read(activeRemoteSessionProvider);
      if (activeSession != null &&
          activeSession.server.id == widget.server.id &&
          _playlistData != null) {
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromePlaylistDetail(
              playlistId: widget.playlistId,
              playlistData: _playlistData!,
              tracks: _tracks,
              starredSongIds: _starredSongIds,
            );
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromePlaylistSummary(
              widget.playlistId,
              songCount: _tracks.length,
            );
      }
      widget.onPlaylistModified?.call();
      showToast(l10n.deletedSongs(selectedIndices.length));
    } else {
      showToast(l10n.removeTrackFailed);
    }
  }

  bool get _isStarredView =>
      widget.isStarred || widget.playlistId == 'starred_songs';

  @override
  void initState() {
    super.initState();
    _currentName = widget.playlistName;
    if (widget.highlightedSongPath != null) {
      _highlightedSongPath = widget.highlightedSongPath;
    }
    _loadPlaylistDetails();
  }

  @override
  void didUpdateWidget(RemotePlaylistDetailContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playlistId != widget.playlistId ||
        oldWidget.isStarred != widget.isStarred ||
        oldWidget.server.id != widget.server.id) {
      _currentName = widget.playlistName;
      _loadPlaylistDetails();
    }
    if (widget.highlightedSongPath != null &&
        widget.highlightedSongPath != oldWidget.highlightedSongPath) {
      _scrollToTrack(widget.highlightedSongPath!);
    }
  }

  @override
  void dispose() {
    _reorderController.dispose();
    _highlightTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTrack(String songPath) {
    if (!mounted || _tracks.isEmpty) return;
    final index = _tracks.indexWhere((t) => t.path == songPath);
    if (index == -1) return;

    setState(() {
      _highlightedSongPath = songPath;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _highlightedSongPath = null;
        });
      }
    });

    if (_scrollController.hasClients) {
      const double headerHeight = 280.0;
      const double trackHeight = 60.0;
      final double itemOffset = headerHeight + index * trackHeight;
      final double viewportHeight =
          _scrollController.position.viewportDimension;
      double targetOffset =
          itemOffset - (viewportHeight / 2) + (trackHeight / 2);
      final maxScroll = _scrollController.position.maxScrollExtent;
      targetOffset = targetOffset.clamp(0.0, maxScroll);
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _loadPlaylistDetails({bool forceRefresh = false}) async {
    final session = ref.read(activeRemoteSessionProvider);
    final isSameServer =
        session != null && session.server.id == widget.server.id;

    if (!forceRefresh && isSameServer) {
      final cached = session.navidromePlaylistDetailsCache[widget.playlistId];
      if (cached != null) {
        setState(() {
          _playlistData = cached.playlistData;
          _currentName =
              cached.playlistData['name'] as String? ?? widget.playlistName;
          _tracks = cached.tracks;
          _starredSongIds
            ..clear()
            ..addAll(cached.starredSongIds);
          _isLoading = false;
          _error = null;
        });

        if (_highlightedSongPath != null) {
          final targetPath = _highlightedSongPath!;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTrack(targetPath);
          });
        }
        _revalidatePlaylistDetails();
        return;
      }
    }

    // Try reading from SQLite cache first for instant UI (SWR)
    if (!forceRefresh && _tracks.isEmpty) {
      try {
        final cacheCategory = _isStarredView
            ? 'starred_songs_detail'
            : 'playlist_detail_${widget.playlistId}';
        final cache = await MetadataDatabase().getRemoteLibraryCache(
          serverId: widget.server.id,
          category: cacheCategory,
        );
        if (cache != null && mounted) {
          final data = jsonDecode(cache.dataJson) as Map<String, dynamic>;
          final client = RemoteMediaLibraryClient.create(
            server: widget.server,
            password: widget.password,
          );
          final rawSongs =
              (data['songs'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .toList() ??
              [];
          final parsedTracks = rawSongs.map(client.buildMusicFile).toList();
          final starred =
              (data['starredIds'] as List?)?.map((e) => e.toString()).toSet() ??
              {};
          final plData = data['playlistData'] as Map<String, dynamic>?;

          if (parsedTracks.isNotEmpty || plData != null) {
            setState(() {
              _playlistData = plData;
              _currentName = plData?['name'] as String? ?? widget.playlistName;
              _tracks = parsedTracks;
              _starredSongIds
                ..clear()
                ..addAll(starred);
              _isLoading = false;
              _error = null;
            });

            if (_highlightedSongPath != null) {
              final targetPath = _highlightedSongPath!;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToTrack(targetPath);
              });
            }
            _revalidatePlaylistDetails();
            return;
          }
        }
      } catch (_) {}
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = RemoteMediaLibraryClient.create(
        server: widget.server,
        password: widget.password,
      );

      if (_isStarredView) {
        final songList = await client.getStarredSongs();
        final List<MusicFile> parsedTracks = [];
        final List<Map<String, dynamic>> rawSongs = [];
        final Set<String> starred = {};
        int totalDur = 0;

        for (final item in songList) {
          final song = client.buildMusicFile(item);
          parsedTracks.add(song);
          rawSongs.add(item);
          final trackId = item['id']?.toString() ?? song.id.toString();
          starred.add(trackId);
          if (item['duration'] is int) {
            totalDur += item['duration'] as int;
          }
        }

        if (!mounted) return;
        final data = {
          'name': widget.playlistName,
          'songCount': parsedTracks.length,
          'duration': totalDur,
        };
        setState(() {
          _playlistData = data;
          _currentName = widget.playlistName;
          _tracks = parsedTracks;
          _starredSongIds
            ..clear()
            ..addAll(starred);
          _isLoading = false;
        });

        final cachePayload = {
          'playlistData': data,
          'starredIds': starred.toList(),
          'songs': rawSongs,
        };
        unawaited(
          MetadataDatabase().saveRemoteLibraryCache(
            serverId: widget.server.id,
            category: 'starred_songs_detail',
            dataJson: jsonEncode(cachePayload),
            count: parsedTracks.length,
          ),
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final activeSession = ref.read(activeRemoteSessionProvider);
          if (activeSession != null &&
              activeSession.server.id == widget.server.id) {
            ref
                .read(activeRemoteSessionProvider.notifier)
                .updateNavidromePlaylistDetail(
                  playlistId: widget.playlistId,
                  playlistData: data,
                  tracks: parsedTracks,
                  starredSongIds: starred,
                );
            ref
                .read(activeRemoteSessionProvider.notifier)
                .updateNavidromePlaylistSummary(
                  widget.playlistId,
                  songCount: parsedTracks.length,
                  duration: totalDur,
                );
          }
        });
        return;
      }

      final pl = await client.getPlaylist(widget.playlistId);
      if (pl == null) {
        if (!mounted) return;
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _error = l10n.playlistNotFound;
          _isLoading = false;
        });
        return;
      }

      final songList = pl['entry'] as List?;
      final List<MusicFile> parsedTracks = [];
      final List<Map<String, dynamic>> rawSongs = [];
      final Set<String> starred = {};

      if (songList != null) {
        for (final item in songList) {
          if (item is Map<String, dynamic>) {
            final song = client.buildMusicFile(item);
            parsedTracks.add(song);
            rawSongs.add(item);
            if (item['starred'] != null) {
              final trackId = item['id']?.toString() ?? song.id.toString();
              starred.add(trackId);
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _playlistData = pl;
        _currentName = pl['name'] as String? ?? widget.playlistName;
        _tracks = parsedTracks;
        _starredSongIds
          ..clear()
          ..addAll(starred);
        _isLoading = false;
      });

      final cachePayload = {
        'playlistData': pl,
        'starredIds': starred.toList(),
        'songs': rawSongs,
      };
      unawaited(
        MetadataDatabase().saveRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'playlist_detail_${widget.playlistId}',
          dataJson: jsonEncode(cachePayload),
          count: parsedTracks.length,
        ),
      );

      if (_highlightedSongPath != null) {
        final targetPath = _highlightedSongPath!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToTrack(targetPath);
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final activeSession = ref.read(activeRemoteSessionProvider);
        if (activeSession != null &&
            activeSession.server.id == widget.server.id) {
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromePlaylistDetail(
                playlistId: widget.playlistId,
                playlistData: pl,
                tracks: parsedTracks,
                starredSongIds: starred,
              );
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromePlaylistSummary(
                widget.playlistId,
                name: pl['name'] as String? ?? widget.playlistName,
                songCount: parsedTracks.length,
                duration: pl['duration'] as int?,
              );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _revalidatePlaylistDetails() async {
    if (_isRevalidating || !mounted) return;
    _isRevalidating = true;
    try {
      final client = RemoteMediaLibraryClient.create(
        server: widget.server,
        password: widget.password,
      );

      if (_isStarredView) {
        final songList = await client.getStarredSongs();
        final List<MusicFile> parsedTracks = [];
        final Set<String> starred = {};
        int totalDur = 0;

        for (final item in songList) {
          final song = client.buildMusicFile(item);
          parsedTracks.add(song);
          final trackId = item['id']?.toString() ?? song.id.toString();
          starred.add(trackId);
          if (item['duration'] is int) {
            totalDur += item['duration'] as int;
          }
        }

        if (!mounted) return;
        final data = {
          'name': widget.playlistName,
          'songCount': parsedTracks.length,
          'duration': totalDur,
        };

        final tracksChanged = !_tracksEqual(_tracks, parsedTracks);
        final starredChanged =
            _starredSongIds.length != starred.length ||
            !_starredSongIds.containsAll(starred);

        if (tracksChanged || starredChanged) {
          if (!isSelectionMode) {
            setState(() {
              _playlistData = data;
              _tracks = parsedTracks;
              _starredSongIds
                ..clear()
                ..addAll(starred);
            });
          }
          final activeSession = ref.read(activeRemoteSessionProvider);
          if (activeSession != null &&
              activeSession.server.id == widget.server.id) {
            ref
                .read(activeRemoteSessionProvider.notifier)
                .updateNavidromePlaylistDetail(
                  playlistId: widget.playlistId,
                  playlistData: data,
                  tracks: parsedTracks,
                  starredSongIds: starred,
                );
            ref
                .read(activeRemoteSessionProvider.notifier)
                .updateNavidromePlaylistSummary(
                  widget.playlistId,
                  songCount: parsedTracks.length,
                  duration: totalDur,
                );
          }
          widget.onPlaylistModified?.call();
        }

        final cachePayload = {
          'playlistData': data,
          'starredIds': starred.toList(),
          'songs': songList.whereType<Map<String, dynamic>>().toList(),
        };
        unawaited(
          MetadataDatabase().saveRemoteLibraryCache(
            serverId: widget.server.id,
            category: 'starred_songs_detail',
            dataJson: jsonEncode(cachePayload),
            count: parsedTracks.length,
          ),
        );
        return;
      }

      final pl = await client.getPlaylist(widget.playlistId);
      if (pl == null || !mounted) return;

      final songList = pl['entry'] as List?;
      final List<MusicFile> parsedTracks = [];
      final List<Map<String, dynamic>> rawSongs = [];
      final Set<String> starred = {};

      if (songList != null) {
        for (final item in songList) {
          if (item is Map<String, dynamic>) {
            final song = client.buildMusicFile(item);
            parsedTracks.add(song);
            rawSongs.add(item);
            if (item['starred'] != null) {
              final trackId = item['id']?.toString() ?? song.id.toString();
              starred.add(trackId);
            }
          }
        }
      }

      if (!mounted) return;
      final newName = pl['name'] as String? ?? widget.playlistName;
      final tracksChanged = !_tracksEqual(_tracks, parsedTracks);
      final nameChanged = _currentName != newName;
      final starredChanged =
          _starredSongIds.length != starred.length ||
          !_starredSongIds.containsAll(starred);

      if (tracksChanged || nameChanged || starredChanged) {
        if (!isSelectionMode) {
          setState(() {
            _playlistData = pl;
            _currentName = newName;
            _tracks = parsedTracks;
            _starredSongIds
              ..clear()
              ..addAll(starred);
          });
        }
        final activeSession = ref.read(activeRemoteSessionProvider);
        if (activeSession != null &&
            activeSession.server.id == widget.server.id) {
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromePlaylistDetail(
                playlistId: widget.playlistId,
                playlistData: pl,
                tracks: parsedTracks,
                starredSongIds: starred,
              );
          ref
              .read(activeRemoteSessionProvider.notifier)
              .updateNavidromePlaylistSummary(
                widget.playlistId,
                name: newName,
                songCount: parsedTracks.length,
                duration: pl['duration'] as int?,
              );
        }
        widget.onPlaylistModified?.call();
      }

      final cachePayload = {
        'playlistData': pl,
        'starredIds': starred.toList(),
        'songs': rawSongs,
      };
      unawaited(
        MetadataDatabase().saveRemoteLibraryCache(
          serverId: widget.server.id,
          category: 'playlist_detail_${widget.playlistId}',
          dataJson: jsonEncode(cachePayload),
          count: parsedTracks.length,
        ),
      );
    } catch (_) {
      // Revalidation silently catches network errors
    } finally {
      _isRevalidating = false;
    }
  }

  Future<void> _playAll({bool shuffle = false}) async {
    if (_tracks.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final audioService = ref.read(audioServiceProvider);
    final playlist = List<MusicFile>.from(_tracks);
    if (shuffle) {
      playlist.shuffle();
    }
    await audioService.playPlaylist(
      playlist,
      source: PlaybackSource(
        type: PlaybackSourceType.playlist,
        id: 'remote-${widget.server.id}-${widget.playlistId}',
        name: _currentName,
      ),
    );
    showToast(l10n.playingTracksCount(_tracks.length));
  }

  Future<void> _downloadAll() async {
    if (_tracks.isEmpty) return;

    // null = 用户在进度浮层里点了取消，别再报「已加入 N 首」。
    final queued = await runWithRemoteTrackLoadProgress<bool>(
      context: context,
      immediate: true,
      task: () async {
        await ref
            .read(remoteDownloadTasksProvider.notifier)
            .enqueue(
              RemoteDownloadRequest(
                server: widget.server,
                password: widget.password,
                songs: _tracks,
                layout: RemoteDownloadLayout.playlist,
                collectionFolder: _currentName,
              ),
            );
        return true;
      },
    );
    if (queued != true) return;

    showRemoteDownloadQueuedFeedback(context, ref, _tracks.length);
  }

  Future<void> _removeTrackAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    final l10n = AppLocalizations.of(context)!;
    final songToRemove = _tracks[index];

    final client = RemoteMediaLibraryClient.create(
      server: widget.server,
      password: widget.password,
    );

    final success = await client.updatePlaylist(
      playlistId: widget.playlistId,
      songIndexesToRemove: [index],
    );

    if (success) {
      setState(() {
        _tracks.removeAt(index);
      });
      final activeSession = ref.read(activeRemoteSessionProvider);
      if (activeSession != null &&
          activeSession.server.id == widget.server.id &&
          _playlistData != null) {
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromePlaylistDetail(
              playlistId: widget.playlistId,
              playlistData: _playlistData!,
              tracks: _tracks,
              starredSongIds: _starredSongIds,
            );
        ref
            .read(activeRemoteSessionProvider.notifier)
            .updateNavidromePlaylistSummary(
              widget.playlistId,
              songCount: _tracks.length,
            );
      }
      widget.onPlaylistModified?.call();
      showToast(l10n.removedFromPlaylistSuccess(songToRemove.displayName));
    } else {
      showToast(l10n.removeTrackFailed);
    }
  }

  void _showRenameDialog() {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: _currentName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renamePlaylist),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.playlistName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && newName != _currentName) {
                final client = RemoteMediaLibraryClient.create(
                  server: widget.server,
                  password: widget.password,
                );
                final ok = await client.updatePlaylist(
                  playlistId: widget.playlistId,
                  name: newName,
                );
                if (ok && mounted) {
                  setState(() {
                    _currentName = newName;
                    if (_playlistData != null) {
                      _playlistData = Map<String, dynamic>.from(_playlistData!)
                        ..['name'] = newName;
                    }
                  });
                  final activeSession = ref.read(activeRemoteSessionProvider);
                  if (activeSession != null &&
                      activeSession.server.id == widget.server.id &&
                      _playlistData != null) {
                    ref
                        .read(activeRemoteSessionProvider.notifier)
                        .updateNavidromePlaylistDetail(
                          playlistId: widget.playlistId,
                          playlistData: _playlistData!,
                          tracks: _tracks,
                          starredSongIds: _starredSongIds,
                        );
                    ref
                        .read(activeRemoteSessionProvider.notifier)
                        .updateNavidromePlaylistSummary(
                          widget.playlistId,
                          name: newName,
                        );
                  }
                  widget.onPlaylistModified?.call();
                }
              }
              if (ctx.mounted) {
                Navigator.pop(ctx);
              }
            },
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deletePlaylist),
        content: Text(l10n.confirmDeletePlaylist(_currentName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final client = RemoteMediaLibraryClient.create(
                server: widget.server,
                password: widget.password,
              );
              final ok = await client.deletePlaylist(widget.playlistId);
              if (ok) {
                final activeSession = ref.read(activeRemoteSessionProvider);
                if (activeSession != null &&
                    activeSession.server.id == widget.server.id) {
                  ref
                      .read(activeRemoteSessionProvider.notifier)
                      .removeNavidromePlaylist(widget.playlistId);
                }
                showToast(l10n.playlistDeleted);
                widget.onPlaylistModified?.call();
                widget.onDeleted?.call();
              } else {
                if (mounted) {
                  final isZh = l10n.localeName.startsWith('zh');
                  final permHint =
                      widget.server.type == RemoteServerType.jellyfin
                      ? (isZh
                            ? '（请检查 Jellyfin 用户是否开启“允许删除媒体”权限）'
                            : ' (Please check Jellyfin "Allow media deletion" permission)')
                      : '';
                  AppSnackBar.show(
                    context,
                    ref,
                    SnackBar(
                      content: Text('${l10n.deletePlaylistFailed}$permHint'),
                    ),
                  );
                }
              }
            },
            child: Text(
              l10n.delete,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0 min';
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final currentMusic = ref.watch(audioCurrentMusicProvider);
    final isAudioPlaying = ref.watch(audioIsPlayingProvider);
    final settings = ref.watch(settingsServiceProvider);
    final zoomScale = settings.folderZoomScale;

    final size = MediaQuery.sizeOf(context);
    final isLandscape = ref.watch(isEffectiveLandscapeProvider(size));
    final isPortrait = !isLandscape;
    // 本页不是全屏路由：它挂在 `folder_page.dart` 的嵌套 Navigator 里，
    // 本身就在 rail 右侧的内容区内（与 `RemoteAlbumDetailPage` 同宿主）。
    // 再让位一次 rail 会多空出一整条 —— 本地歌单详情页是全屏 push，才需要自己让位。
    final double barHeight = AppTopNavBar.getBarHeight(context);

    final bottomOffset = MiniPlayerUiTuning.getListBottomPadding(
      context,
      hasPlayingMusic: currentMusic != null,
      isSelectionMode: isSelectionMode,
      selectionPanelHeight: 220.0,
    );
    final selectedSongs = getSelectedSongs(_tracks);
    final selectedSongPaths = selectedSongs.map((s) => s.path).toSet();
    final selectedIndices = <int>{
      for (int i = 0; i < _tracks.length; i++)
        if (selectedSongPaths.contains(_tracks[i].path)) i,
    };

    Widget scrollBody;
    if (_isLoading) {
      final isJellyfin = widget.server.type == RemoteServerType.jellyfin;
      final brandColor = isJellyfin ? const Color(0xFF9D65C9) : Colors.orange;
      final isZh = l10n.localeName.startsWith('zh');

      scrollBody = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(brandColor),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isZh ? '正在加载歌单曲目...' : 'Loading playlist tracks...',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    } else if (_error != null) {
      scrollBody = Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(l10n.errorWithMessage(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadPlaylistDetails,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    } else {
      final coverId = widget.coverArtId ?? _playlistData?['coverArt'] as String?;
      final count = _tracks.isNotEmpty ? _tracks.length : (widget.songCount ?? 0);
      final totalDuration =
          _playlistData?['duration'] as int? ?? widget.duration ?? 0;
      final comment = _playlistData?['comment'] as String?;
      final owner = _playlistData?['owner'] as String?;

      final double buttonHeight = isPortrait ? 44.0 : 32.0;
      final double iconSize = isPortrait ? 20.0 : 18.0;
      final double buttonSpacing = isPortrait ? 10.0 : 8.0;

      scrollBody = FolderZoomGestureLayer(
        reorderActive: _reorderController.reorderActive,
        zoomGesturesEnabled: !isSelectionMode,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.min(
              constraints.maxWidth,
              kFolderPageMaxWidth,
            );
            return FolderZoomSliverBuilder(
              zoomScale: snapFolderZoomScale(zoomScale),
              width: contentWidth,
              builder: (context, metrics) {
                final hPad = folderContentHorizontalPadding(
                  isPortrait: isPortrait,
                  gridMorph: metrics.gridMorph,
                );
                final gridWidth = contentWidth - 2 * hPad;

                return Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: kFolderPageMaxWidth,
                    ),
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        if (!isPortrait)
                          SliverToBoxAdapter(child: SizedBox(height: barHeight)),
                        // Header Section
                        SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: kFolderPageMaxWidth,
                              ),
                              child: Padding(
                                // 竖屏顶栏是浮在内容上的，横幅必须自己让位，
                                // 否则封面会被导航栏压住（横屏已经用占位块让过）。
                                padding: EdgeInsets.only(
                                  left: 16,
                                  right: 16,
                                  top: isPortrait ? barHeight + 8 : 20,
                                  bottom: 16,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    final isNarrow =
                                        isPortrait || constraints.maxWidth < 460;
                                    final double imageSize = isPortrait
                                        ? 220
                                        : (isNarrow ? 120 : 160);

                                    final coverWidget = ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Container(
                                        width: imageSize,
                                        height: imageSize,
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: 0.15,
                                              ),
                                              blurRadius: 16,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: coverId != null &&
                                                coverId.isNotEmpty
                                            ? RemoteArtworkWidget(
                                                server: widget.server,
                                                password: widget.password,
                                                coverArtId: coverId,
                                                size: imageSize,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              )
                                            : Icon(
                                                _isStarredView
                                                    ? Icons.favorite_rounded
                                                    : Icons
                                                        .playlist_play_rounded,
                                                size: imageSize * 0.45,
                                                color: _isStarredView
                                                    ? Colors.redAccent
                                                    : theme.colorScheme.primary,
                                              ),
                                      ),
                                    );

                                    final infoContent = Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _isStarredView
                                              ? l10n.starredSongs.toUpperCase()
                                              : l10n.playlist.toUpperCase(),
                                          style: theme.textTheme.labelLarge
                                              ?.copyWith(
                                            color: _isStarredView
                                                ? Colors.redAccent
                                                : theme.colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          _currentName,
                                          style: theme
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(
                                              l10n.trackCountShort(count),
                                              style: theme
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            if (totalDuration > 0) ...[
                                              Text(
                                                '•',
                                                style: TextStyle(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              Text(
                                                _formatDuration(totalDuration),
                                                style: theme
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                            if (owner != null &&
                                                owner.isNotEmpty) ...[
                                              Text(
                                                '•',
                                                style: TextStyle(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                              Text(
                                                owner,
                                                style: theme
                                                  .textTheme
                                                  .bodyMedium
                                                  ?.copyWith(
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (comment != null &&
                                            comment.trim().isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Text(
                                            comment.trim(),
                                            style: theme
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    );

                                    if (isPortrait) {
                                      // 竖屏与横屏统一左对齐：封面靠左、信息列靠左，
                                      // 不再走「整块居中但文字左对齐」那种歪着的排版。
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          coverWidget,
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            width: double.infinity,
                                            child: infoContent,
                                          ),
                                        ],
                                      );
                                    }

                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        coverWidget,
                                        const SizedBox(width: 20),
                                        Expanded(child: infoContent),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Action Buttons Bar
                        SliverToBoxAdapter(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: kFolderPageMaxWidth,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    FilledButton.icon(
                                      onPressed: _tracks.isNotEmpty
                                          ? () => _playAll()
                                          : null,
                                      icon: Icon(
                                        Icons.play_arrow_rounded,
                                        size: iconSize + 2,
                                      ),
                                      label: Text(
                                        l10n.playAll,
                                        style: TextStyle(
                                          fontWeight: isPortrait
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          fontSize: isPortrait ? 15 : 13,
                                        ),
                                      ),
                                      style: FilledButton.styleFrom(
                                        shape: const StadiumBorder(),
                                        padding: EdgeInsets.symmetric(
                                          horizontal: isPortrait ? 18 : 14,
                                        ),
                                        minimumSize: Size(0, buttonHeight),
                                        elevation: 0,
                                      ),
                                    ),
                                    SizedBox(width: buttonSpacing),
                                    IconButton.filledTonal(
                                      tooltip: l10n.shufflePlay,
                                      style: IconButton.styleFrom(
                                        foregroundColor: theme.colorScheme
                                            .onSecondaryContainer,
                                        backgroundColor: theme.colorScheme
                                            .surfaceContainerHighest,
                                        fixedSize:
                                            Size(buttonHeight, buttonHeight),
                                        minimumSize:
                                            Size(buttonHeight, buttonHeight),
                                        padding: EdgeInsets.zero,
                                        shape: const CircleBorder(),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: _tracks.isNotEmpty
                                          ? () => _playAll(shuffle: true)
                                          : null,
                                      icon: Icon(
                                        Icons.shuffle_rounded,
                                        size: iconSize,
                                      ),
                                    ),
                                    SizedBox(width: buttonSpacing),
                                    IconButton.filledTonal(
                                      tooltip: l10n.downloadAllTracks,
                                      style: IconButton.styleFrom(
                                        foregroundColor: theme.colorScheme
                                            .onSecondaryContainer,
                                        backgroundColor: theme.colorScheme
                                            .surfaceContainerHighest,
                                        fixedSize:
                                            Size(buttonHeight, buttonHeight),
                                        minimumSize:
                                            Size(buttonHeight, buttonHeight),
                                        padding: EdgeInsets.zero,
                                        shape: const CircleBorder(),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed:
                                          _tracks.isNotEmpty ? _downloadAll : null,
                                      icon: Icon(
                                        Icons.download_rounded,
                                        size: iconSize,
                                      ),
                                    ),
                                    SizedBox(width: buttonSpacing),
                                    PopupMenuButton<String>(
                                      tooltip: l10n.managePlaylists,
                                      iconSize: iconSize,
                                      style: IconButton.styleFrom(
                                        foregroundColor:
                                            theme.colorScheme.onSurfaceVariant,
                                        fixedSize:
                                            Size(buttonHeight, buttonHeight),
                                        minimumSize:
                                            Size(buttonHeight, buttonHeight),
                                        padding: EdgeInsets.zero,
                                        shape: const CircleBorder(),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        size: iconSize,
                                      ),
                                      onSelected: (value) {
                                        if (value == 'rename') {
                                          _showRenameDialog();
                                        } else if (value == 'delete') {
                                          _showDeleteDialog();
                                        } else if (value == 'refresh') {
                                          _loadPlaylistDetails();
                                        }
                                      },
                                      itemBuilder: (ctx) => [
                                        if (!_isStarredView)
                                          PopupMenuItem(
                                            value: 'rename',
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.edit_rounded,
                                                  size: 18,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(l10n.renamePlaylist),
                                              ],
                                            ),
                                          ),
                                        PopupMenuItem(
                                          value: 'refresh',
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.refresh_rounded,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 12),
                                              Text(l10n.refresh),
                                            ],
                                          ),
                                        ),
                                        if (!_isStarredView) ...[
                                          const PopupMenuDivider(),
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 18,
                                                  color: Colors.redAccent,
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  l10n.deletePlaylist,
                                                  style: const TextStyle(
                                                    color: Colors.redAccent,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SliverToBoxAdapter(
                          child: Divider(height: 1, indent: 16, endIndent: 16),
                        ),

                        // Songs List
                        if (_tracks.isEmpty)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.music_off_rounded,
                                      size: 56,
                                      color: theme.colorScheme.outlineVariant,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      l10n.emptyList,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: EdgeInsets.only(
                              left: hPad,
                              right: hPad,
                              top: isPortrait ? 8.0 : 16.0,
                              bottom: bottomOffset,
                            ),
                            sliver: ZoomReorderableSliverGrid(
                              metrics: metrics,
                              width: gridWidth,
                              itemCount: _tracks.length,
                              itemKeyBuilder: (index) =>
                                  ValueKey('${_tracks[index].path}_$index'),
                              controller: _reorderController,
                              selectedIndices: selectedIndices,
                              lockedIndices: _isStarredView
                                  ? {for (int i = 0; i < _tracks.length; i++) i}
                                  : const {},
                              showHandles: isSelectionMode,
                              handleChild: buildZoomReorderHandle(context),
                              previewBuilder: (context, _, count) =>
                                  buildZoomReorderPreview(
                                context,
                                icon: Icons.music_note_rounded,
                                count: count,
                              ),
                              directDragPreviewBuilder:
                                  (context, index, selectedIndices) {
                                final song = _tracks[index];
                                final count = selectedIndices.length;
                                final isBatch = count > 1;
                                return AppDraggablePreviewCard(
                                  title: song.displayName,
                                  subtitle: isBatch
                                      ? l10n.selectedSongs(count)
                                      : (song.artist?.isNotEmpty == true
                                          ? song.artist!
                                          : l10n.unknownArtist),
                                  imagePath: resolveDragCoverPath(
                                    thumbnailPath: song.thumbnailPath,
                                    artworkPath: song.artworkPath,
                                  ),
                                  defaultIcon: Icons.music_note_rounded,
                                  isBatch: isBatch,
                                  count: count,
                                );
                              },
                              itemDragItemBuilder:
                                  (index, pickedIndices, localData, [request]) {
                                if (request != null) {
                                  DropDataUtils.trackInternalDrag(request.session);
                                }
                                final song = _tracks[index];
                                final List<String> dragPaths;
                                if (isSelectionMode &&
                                    selectedIndices.contains(index)) {
                                  dragPaths = [
                                    for (final i in selectedIndices)
                                      _tracks[i].path,
                                  ];
                                } else {
                                  dragPaths = [song.path];
                                }
                                return SongPathsPayload(paths: dragPaths)
                                    .toDragItem();
                              },
                              onReorderAsync: _isStarredView
                                  ? null
                                  : (draggedIndices, insertIndex) async {
                                      final originalTracks =
                                          List<MusicFile>.of(_tracks);
                                      final reordered =
                                          ZoomReorderController.applyReorder(
                                        _tracks,
                                        draggedIndices,
                                        insertIndex,
                                      );
                                      setState(() {
                                        _tracks = reordered;
                                      });

                                      final orderedTrackIds = reordered
                                          .map((s) =>
                                              RemoteMediaResolver.extractTrackId(
                                                  s) ??
                                              (s.id?.toString() ?? ''))
                                          .where((id) => id.isNotEmpty)
                                          .toList();

                                      String? movedId;
                                      if (draggedIndices.length == 1) {
                                        final s = originalTracks[
                                            draggedIndices.first];
                                        movedId =
                                            RemoteMediaResolver.extractTrackId(
                                                    s) ??
                                                s.id?.toString();
                                      }

                                      final client =
                                          RemoteMediaLibraryClient.create(
                                        server: widget.server,
                                        password: widget.password,
                                      );

                                      final ok = await client.reorderPlaylist(
                                        playlistId: widget.playlistId,
                                        orderedSongIds: orderedTrackIds,
                                        playlistName: _currentName,
                                        movedSongId: movedId,
                                        newIndex: insertIndex,
                                      );

                                      if (!ok) {
                                        if (mounted) {
                                          setState(() {
                                            _tracks = originalTracks;
                                          });
                                          showToast(l10n.removeTrackFailed);
                                        }
                                        throw Exception(
                                            'Failed to update playlist order on server');
                                      }

                                      final activeSession = ref
                                          .read(activeRemoteSessionProvider);
                                      if (activeSession != null &&
                                          activeSession.server.id ==
                                              widget.server.id &&
                                          _playlistData != null) {
                                        ref
                                            .read(activeRemoteSessionProvider
                                                .notifier)
                                            .updateNavidromePlaylistDetail(
                                              playlistId: widget.playlistId,
                                              playlistData: _playlistData!,
                                              tracks: _tracks,
                                              starredSongIds: _starredSongIds,
                                            );
                                      }
                                      widget.onPlaylistModified?.call();
                                      return true;
                                    },
                              onReorder: _isStarredView ? (_, _) {} : null,
                              itemBuilder: (context, index) {
                                final song = _tracks[index];
                                final isCurrent =
                                    currentMusic?.path == song.path;
                                final isHighlighted =
                                    _highlightedSongPath == song.path;
                                final isSelected =
                                    isSongSelected(song.path);

                                return SongZoomItem(
                                  key: ValueKey('${song.path}_$index'),
                                  song: song,
                                  metrics: metrics,
                                  index: index,
                                  isCurrent: isCurrent,
                                  isPlaying: isAudioPlaying && isCurrent,
                                  isSelected: isSelected,
                                  isSelectionMode: isSelectionMode,
                                  selectedPaths: selectedSongPaths,
                                  isHighlighted: isHighlighted,
                                  enableDrag: false,
                                  onTap: () {
                                    if (isSelectionMode) {
                                      handleSongTap(
                                        index: index,
                                        songPath: song.path,
                                        allSongs: _tracks,
                                        onNormalTap: () =>
                                            toggleSongSelection(song.path),
                                      );
                                    } else {
                                      final audio =
                                          ref.read(audioServiceProvider);
                                      audio.playPlaylist(
                                        _tracks,
                                        initialIndex: index,
                                        source: PlaybackSource(
                                          type: PlaybackSourceType.playlist,
                                          id:
                                              'remote-${widget.server.id}-${widget.playlistId}',
                                          name: _currentName,
                                        ),
                                      );
                                    }
                                  },
                                  onLongPress: () {
                                    lastAnchorIndex = index;
                                    if (isSelectionMode) {
                                      toggleSongSelection(song.path);
                                    } else {
                                      enterSongSelectionMode(song.path);
                                    }
                                  },
                                  onSecondaryTapDown: (details) {
                                    if (!isSelectionMode) {
                                      showRemoteSongContextMenu(
                                        context: context,
                                        globalPosition:
                                            details.globalPosition,
                                        ref: ref,
                                        server: widget.server,
                                        password: widget.password,
                                        song: song,
                                        playlist: _tracks,
                                        onMultiSelect: () =>
                                            enterSongSelectionMode(song.path),
                                        downloadLayout:
                                            RemoteDownloadLayout.playlist,
                                        downloadCollectionFolder:
                                            _currentName,
                                        onRemoveFromPlaylist: () =>
                                            _removeTrackAt(index),
                                        onViewArtist: () {
                                          if (song.artist != null &&
                                              song.artist!.isNotEmpty) {
                                            RemoteLibraryNavUtils.openArtist(
                                              context,
                                              server: widget.server,
                                              password: widget.password,
                                              artistId: '',
                                              artistName: song.artist!,
                                            );
                                          }
                                        },
                                      );
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    return RemotePageShell(
      // 远程库已是一级 tab，外层不再 `Padding(left: railWidth)`：
      // 横屏时让位必须落在页面内部，否则整页被 Rail 压住左边缘。
      avoidRail: true,
      contentBuilder: (context) => scrollBody,
      navBarBuilder: (context, isHeaderVisible, isPastTop) => AppTopNavBar(
        title: _currentName,
        parentTitle: l10n.playlist,
        titleKey: ValueKey('remote_playlist_title_${widget.playlistId}'),
        isFloatingCapsule: isPastTop,
        contentMaxWidth: kFolderPageMaxWidth,
        onBack: _handleBack,
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: ref.watch(activeDownloadsCountProvider) > 0,
              label: Text('${ref.watch(activeDownloadsCountProvider)}'),
              child: const Icon(Icons.download_rounded, size: 20),
            ),
            tooltip: l10n.downloadManager,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(
                  builder: (_) => const RemoteDownloadManagerPage(),
                ),
              );
            },
          ),
        ],
      ),
      selectionPanel: (!_isLoading && _error == null)
          ? AnimatedSelectionPanel(
              isVisible: isSelectionMode,
              child: RemoteSongSelectionPanel(
                panelKey: const ValueKey('remote-playlist-selection-panel'),
                server: widget.server,
                password: widget.password,
                selectedSongs: selectedSongs,
                allSongs: _tracks,
                onToggleSelectAll: () => toggleSelectAllSongs(_tracks),
                onFetchSongs: () async => selectedSongs,
                onClearSelection: cancelSongSelection,
                onDelete: !_isStarredView ? _deleteSelectedSongs : null,
                deleteLabel: l10n.removeFromPlaylist,
                onStarredChanged: (starredIds) {
                  ref
                      .read(activeRemoteSessionProvider.notifier)
                      .updateNavidromeSongs(
                        starredSongIds: {
                          ...?ref
                              .read(activeRemoteSessionProvider)
                              ?.navidromeStarredSongIds,
                          ...starredIds,
                        },
                      );
                },
                onDownload: () async {
                  final sel = List<MusicFile>.from(selectedSongs);
                  if (sel.isEmpty) return;
                  await ref
                      .read(remoteDownloadTasksProvider.notifier)
                      .enqueue(
                        RemoteDownloadRequest(
                          server: widget.server,
                          password: widget.password,
                          songs: sel,
                          layout: RemoteDownloadLayout.playlist,
                          collectionFolder: _currentName,
                        ),
                      );
                  cancelSongSelection();
                  showRemoteDownloadQueuedFeedback(context, ref, sel.length);
                },
              ),
            )
          : null,
      popScopeCanPop: !isSelectionMode,
      onPopBlocked: () {
        if (!isSelectionMode) return;
        _reorderController.cancelDrag();
        cancelSongSelection();
      },
    );
  }
}

typedef NavidromePlaylistDetailPage = RemotePlaylistDetailPage;
typedef NavidromePlaylistDetailContent = RemotePlaylistDetailContent;
