import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/album_summary.dart';
import 'package:vynody/models/artist_summary.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/pages/library_search_page.dart';
import 'package:vynody/player/library/playlist_service.dart';

MusicFile _song(String path, {String? title, String? artist, String? album}) {
  return MusicFile(
    path: path,
    name: title ?? path,
    title: title,
    artist: artist,
    album: album,
  );
}

void main() {
  final representative = _song('/music/a.mp3', title: 'A');

  group('filterAlbums', () {
    final albums = [
      AlbumSummary(
        id: '1',
        title: 'Blue Album',
        artist: 'Weezer',
        songs: const [],
        representativeSong: representative,
        totalDurationMillis: 0,
      ),
      AlbumSummary(
        id: '2',
        title: 'Yan Ta De Ri',
        artist: '朴树',
        songs: const [],
        representativeSong: representative,
        totalDurationMillis: 0,
      ),
    ];

    test('标题或艺术家命中都算，且不区分大小写', () {
      expect(filterAlbums(albums, 'blue').map((a) => a.id), ['1']);
      expect(filterAlbums(albums, 'WEEZER').map((a) => a.id), ['1']);
      expect(filterAlbums(albums, '朴树').map((a) => a.id), ['2']);
    });

    test('空查询返回全量，未命中返回空', () {
      expect(filterAlbums(albums, ''), albums);
      expect(filterAlbums(albums, 'nope'), isEmpty);
    });
  });

  group('filterArtists', () {
    final artists = [
      ArtistSummary(
        queryKey: 'weezer',
        name: 'Weezer',
        canonicalName: 'Weezer (band)',
        alternateNames: const ['River Weezer'],
        songs: const [],
        representativeSong: representative,
        songCount: 12,
        country: 'United States',
        tags: const ['rock', 'alt'],
      ),
      ArtistSummary(
        queryKey: 'pshu',
        name: '朴树',
        songs: const [],
        representativeSong: representative,
        songCount: 8,
      ),
    ];

    test('别名 / 全名 / 国籍 / 标签命中同样有效', () {
      expect(filterArtists(artists, 'river').map((a) => a.queryKey), ['weezer']);
      expect(
        filterArtists(artists, 'United S').map((a) => a.queryKey),
        ['weezer'],
      );
      expect(filterArtists(artists, 'alt').map((a) => a.queryKey), ['weezer']);
      expect(filterArtists(artists, '朴树').map((a) => a.queryKey), ['pshu']);
    });

    test('与艺人名无关的词不命中', () {
      expect(filterArtists(artists, 'blue'), isEmpty);
    });
  });

  group('filterPlaylists', () {
    final playlists = [
      Playlist(id: 'p1', name: '夜间驾驶'),
      Playlist(id: 'p2', name: 'Road Trip'),
    ];

    test('按歌单名筛，不区分大小写', () {
      expect(filterPlaylists(playlists, 'road').map((p) => p.id), ['p2']);
      expect(filterPlaylists(playlists, '夜间').map((p) => p.id), ['p1']);
      expect(filterPlaylists(playlists, 'nothing'), isEmpty);
    });
  });
}
