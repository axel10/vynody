import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/models/music_folder.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/utils/search_selection_utils.dart';

MusicFile _song(String path) => MusicFile(path: path, name: path);

AlbumSummary _album(String id, List<MusicFile> songs) => AlbumSummary(
  id: id,
  title: 'Album $id',
  artist: 'Artist',
  songs: songs,
  representativeSong: songs.first,
  totalDurationMillis: 0,
);

ArtistSummary _artist(String queryKey, List<MusicFile> songs) => ArtistSummary(
  queryKey: queryKey,
  name: 'Artist $queryKey',
  songs: songs,
  representativeSong: songs.first,
  songCount: songs.length,
);

Playlist _playlist(String id, List<MusicFile> songs) =>
    Playlist(id: id, name: 'Playlist $id', songs: songs);

/// 搜索结果的文件夹是空壳，`allSongs` 恒空，歌曲要靠注入的加载函数补。
Future<List<MusicFile>> _noFolderSongs(MusicFolder folder) async => const [];

void main() {
  group('selection keys', () {
    test('不同类型前缀不互相撞车', () {
      final keys = <String>{
        songSelectionKey('x'),
        folderSelectionKey('x'),
        albumSelectionKey('x'),
        artistSelectionKey('x'),
        playlistSelectionKey('x'),
      };
      expect(keys, hasLength(5));
      expect(songSelectionKey('x'), 'song:x');
      expect(folderSelectionKey('x'), 'folder:x');
    });

    test('键去掉首尾空白，避免同一路径两种写法各占一条', () {
      expect(songSelectionKey('  /a/b.mp3 '), songSelectionKey('/a/b.mp3'));
    });
  });

  group('SearchEntry', () {
    test('工厂按类型生成键', () {
      expect(SearchEntry.song(_song('/a.mp3')).key, 'song:/a.mp3');
      expect(
        SearchEntry.folder(MusicFolder(path: '/music', name: 'music')).key,
        'folder:/music',
      );
      expect(SearchEntry.album(_album('1', [_song('/a.mp3')])).key, 'album:1');
      expect(
        SearchEntry.artist(_artist('k', [_song('/a.mp3')])).key,
        'artist:k',
      );
      expect(
        SearchEntry.playlist(_playlist('p', [_song('/a.mp3')])).key,
        'playlist:p',
      );
    });
  });

  group('expandSearchEntries', () {
    test('集合按全部歌曲展开，单曲取自身', () async {
      final a = _song('/a.mp3');
      final b = _song('/b.mp3');
      final c = _song('/c.mp3');

      final songs = await expandSearchEntries([
        SearchEntry.album(_album('1', [a, b])),
        SearchEntry.song(c),
      ], _noFolderSongs);

      expect(songs.map((s) => s.path), ['/a.mp3', '/b.mp3', '/c.mp3']);
    });

    test('艺术家与歌单同样按集合展开', () async {
      final a = _song('/a.mp3');
      final b = _song('/b.mp3');
      final c = _song('/c.mp3');

      final songs = await expandSearchEntries([
        SearchEntry.artist(_artist('k', [a, b])),
        SearchEntry.playlist(_playlist('p', [c])),
      ], _noFolderSongs);

      expect(songs.map((s) => s.path), ['/a.mp3', '/b.mp3', '/c.mp3']);
    });

    test('重叠歌曲只保留第一次出现的位置', () async {
      final shared = _song('/shared.mp3');
      final only = _song('/only.mp3');

      final songs = await expandSearchEntries([
        SearchEntry.song(shared),
        SearchEntry.album(_album('1', [only, shared])),
      ], _noFolderSongs);

      expect(songs.map((s) => s.path), ['/shared.mp3', '/only.mp3']);
    });

    test('文件夹走注入的加载函数', () async {
      final folder = MusicFolder(path: '/music/rock', name: 'rock');
      final a = _song('/music/rock/a.mp3');
      final b = _song('/music/rock/b.mp3');

      final songs = await expandSearchEntries(
        [SearchEntry.folder(folder)],
        (target) async =>
            target.path == '/music/rock' ? [a, b] : const <MusicFile>[],
      );

      expect(songs.map((s) => s.path), [
        '/music/rock/a.mp3',
        '/music/rock/b.mp3',
      ]);
    });

    test('空选择展开为空', () async {
      expect(await expandSearchEntries([], _noFolderSongs), isEmpty);
    });
  });
}
