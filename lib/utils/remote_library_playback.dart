import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dialogs/remote_track_load_progress_dialog.dart';
import '../models/music_file.dart';
import '../player/audio/audio_riverpod.dart';
import '../player/audio/playback_source.dart';
import '../player/remote/clients/remote_media_library_client.dart';
import '../player/remote/remote_server_models.dart';
import '../player/remote/services/remote_track_load_progress.dart';
import 'remote_context_menu_utils.dart';

/// 远程媒体库分类 tab 上的「播放全部 / 随机播放」覆盖的条目类型。
///
/// 与本地分类页对齐：专辑 tab 播的是「当前列出的这些专辑里的歌」，艺术家 tab
/// 是这些艺术家的歌，流派 tab 是这个流派的歌，歌单 tab 是这些歌单里的歌。
/// 因此开着「只看收藏」时，播的自然只剩收藏条目的曲目。
enum RemoteLibraryEntityKind { album, artist, genre, playlist }

/// 把一组远程条目展开成曲目并开始播放。
///
/// 分类 tab 的条目（专辑 / 艺术家 / 歌单 / 流派）都不带曲目列表，只能逐条回源
/// 取。条目多时请求会成串发出，所以全程挂 [runWithRemoteTrackLoadProgress]
/// 的进度浮层（可取消）；用户取消或一条歌都没取到时不打断当前播放。
Future<void> playRemoteLibraryEntities({
  required BuildContext context,
  required WidgetRef ref,
  required RemoteServer server,
  required String password,
  required RemoteLibraryEntityKind kind,
  required List<Map<String, dynamic>> entities,
  required String sourceId,
  required String sourceName,
  bool shuffle = false,
}) async {
  if (entities.isEmpty) return;

  final client = RemoteMediaLibraryClient.create(
    server: server,
    password: password,
  );

  final songs = await runWithRemoteTrackLoadProgress<List<MusicFile>>(
    context: context,
    task: () async {
      final progress = remoteTrackLoadProgress;
      final collected = <MusicFile>[];

      // 分母只对「条目自带 songCount」的类型有意义（专辑 / 流派 / 歌单）；
      // 艺术家得先拿专辑列表才知道，交给 fetchSubsonicArtistTracks 自己累加，
      // 这里不掺和，免得两处各写一次 total / loaded 互相覆盖。
      final countedByEntity = kind != RemoteLibraryEntityKind.artist;
      if (countedByEntity) {
        final estimated = entities.fold<int>(0, (sum, entity) {
          final count = entity['songCount'];
          return sum + (count is int && count > 0 ? count : 0);
        });
        progress.setTotal(estimated);
      }

      for (final entity in entities) {
        progress.throwIfCancelled();
        final id = (entity['id'] ?? entity['name'] ?? '').toString();
        if (id.isEmpty) continue;
        final batch = await _fetchEntitySongs(
          client: client,
          server: server,
          kind: kind,
          id: id,
        );
        if (batch.isEmpty) continue;
        collected.addAll(batch);
        if (countedByEntity) progress.advance(batch.length);
      }
      return collected;
    },
  );

  // null = 用户在进度浮层里点了取消。
  if (songs == null || songs.isEmpty) return;
  if (!context.mounted) return;

  final queue = List<MusicFile>.from(songs);
  if (shuffle) queue.shuffle();

  await ref.read(audioServiceProvider).playPlaylist(
    queue,
    source: PlaybackSource(
      type: _sourceTypeOf(kind),
      id: sourceId,
      name: sourceName,
    ),
  );
}

PlaybackSourceType _sourceTypeOf(RemoteLibraryEntityKind kind) {
  switch (kind) {
    case RemoteLibraryEntityKind.album:
      return PlaybackSourceType.album;
    case RemoteLibraryEntityKind.artist:
      return PlaybackSourceType.artist;
    case RemoteLibraryEntityKind.genre:
      return PlaybackSourceType.genre;
    case RemoteLibraryEntityKind.playlist:
      return PlaybackSourceType.playlist;
  }
}

Future<List<MusicFile>> _fetchEntitySongs({
  required RemoteMediaLibraryClient client,
  required RemoteServer server,
  required RemoteLibraryEntityKind kind,
  required String id,
}) async {
  switch (kind) {
    case RemoteLibraryEntityKind.album:
      return fetchSubsonicAlbumTracks(client, server, id);
    case RemoteLibraryEntityKind.artist:
      return fetchSubsonicArtistTracks(client, server, id);
    case RemoteLibraryEntityKind.playlist:
      return fetchSubsonicPlaylistTracks(client, server, id);
    case RemoteLibraryEntityKind.genre:
      return _fetchGenreTracks(client, id);
  }
}

/// 拉取某流派名下的全部曲目。
///
/// 分页终止条件与 `RemoteGenreDetailPage._fetchAllSongs` 同口径：返回空、
/// 不足一页、或去重后没有新增（服务端没按 offset 推进）。
Future<List<MusicFile>> _fetchGenreTracks(
  RemoteMediaLibraryClient client,
  String genreId,
) async {
  const pageSize = 500;
  final seenIds = <String>{};
  final tracks = <MusicFile>[];
  var offset = 0;

  try {
    for (var page = 0; page < 20; page++) {
      final batch = await client.getSongsByGenre(
        genreId,
        count: pageSize,
        offset: offset,
      );
      if (batch.isEmpty) break;

      var added = 0;
      for (final raw in batch) {
        final id = (raw['id'] ?? '').toString();
        if (id.isNotEmpty && !seenIds.add(id)) continue;
        tracks.add(client.buildMusicFile(raw));
        added++;
      }
      offset += batch.length;
      if (added == 0 || batch.length < pageSize) break;
    }
  } catch (_) {}
  return tracks;
}
