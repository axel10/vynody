import 'package:flutter_test/flutter_test.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/library/playlist_service.dart';
import 'package:vynody/utils/m3u_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Playlist Sharing Serialization & Parsing', () {
    test('generate and parse M3U for playlist sharing payload', () {
      final songs = <MusicFile>[
        const MusicFile(
          path: '/music/nightglow.mp3',
          name: 'nightglow.mp3',
          title: 'Nightglow',
          artist: 'Tanya Chua',
          album: 'Honkai',
          durationMillis: 210000,
        ),
        const MusicFile(
          path: '/music/rubia.flac',
          name: 'rubia.flac',
          title: 'Rubia',
          artist: 'Zhou Shen',
          album: 'Honkai',
          durationMillis: 185000,
        ),
      ];

      final m3uContent = M3uUtils.generate(songs, playlistName: 'Anime Soundtracks');
      expect(m3uContent, contains('#EXTM3U'));
      expect(m3uContent, contains('#PLAYLIST:Anime Soundtracks'));
      expect(m3uContent, contains('Nightglow'));
      expect(m3uContent, contains('Rubia'));

      final parsed = M3uUtils.parse(m3uContent);
      expect(parsed.playlistName, equals('Anime Soundtracks'));
      expect(parsed.entries.length, equals(2));
      expect(parsed.entries[0].title, equals('Nightglow'));
      expect(parsed.entries[0].artist, equals('Tanya Chua'));
      expect(parsed.entries[1].title, equals('Rubia'));
      expect(parsed.entries[1].artist, equals('Zhou Shen'));
    });

    test('PlaylistService addPlaylist preserves songs and updates state', () async {
      final service = PlaylistService();
      final playlist = Playlist(
        id: 'pl-shared-1',
        name: 'Shared Rock Hits',
        songs: const [
          MusicFile(
            path: '/music/rock.mp3',
            name: 'rock.mp3',
            title: 'Rock Song',
            artist: 'Band',
            album: 'Rock Album',
            durationMillis: 200000,
          ),
        ],
      );

      await service.addPlaylist(playlist);
      expect(service.playlists.any((p) => p.id == 'pl-shared-1'), isTrue);
      final found = service.playlists.firstWhere((p) => p.id == 'pl-shared-1');
      expect(found.name, equals('Shared Rock Hits'));
      expect(found.songs.length, equals(1));
    });

    test('PlaylistService deletePlaylists batch deletes playlists and ignores favorites', () async {
      final service = PlaylistService();
      final pl1 = Playlist(id: 'pl-batch-1', name: 'Batch 1');
      final pl2 = Playlist(id: 'pl-batch-2', name: 'Batch 2');
      final pl3 = Playlist(id: 'pl-batch-3', name: 'Batch 3');

      await service.addPlaylist(pl1);
      await service.addPlaylist(pl2);
      await service.addPlaylist(pl3);

      expect(service.playlists.any((p) => p.id == 'pl-batch-1'), isTrue);
      expect(service.playlists.any((p) => p.id == 'pl-batch-2'), isTrue);
      expect(service.playlists.any((p) => p.id == 'pl-batch-3'), isTrue);

      await service.deletePlaylists(['pl-batch-1', 'pl-batch-2', PlaylistService.favoritePlaylistId]);

      expect(service.playlists.any((p) => p.id == 'pl-batch-1'), isFalse);
      expect(service.playlists.any((p) => p.id == 'pl-batch-2'), isFalse);
      expect(service.playlists.any((p) => p.id == 'pl-batch-3'), isTrue);
      expect(service.playlists.any((p) => p.id == PlaylistService.favoritePlaylistId), isTrue);
    });
  });

  group('mergeOrAddPlaylist（跨设备导入）', () {
    MusicFile song(String path) => MusicFile(
      path: path,
      name: path.split('/').last,
      title: path.split('/').last,
    );

    test('同名歌单合并，按本地 path 去重，不产生「(1)」副本', () async {
      final service = PlaylistService();
      await service.mergeOrAddPlaylist(
        name: 'Road Trip',
        songs: [song('/m/a.mp3'), song('/m/b.mp3')],
      );

      final result = await service.mergeOrAddPlaylist(
        name: 'Road Trip',
        songs: [song('/m/b.mp3'), song('/m/c.mp3')],
      );

      expect(result.merged, isTrue);
      expect(result.addedSongs, 1);
      expect(result.skippedSongs, 1);
      expect(
        service.playlists.where((p) => p.name == 'Road Trip').length,
        1,
      );
      expect(result.playlist.songs.map((s) => s.path).toList(), [
        '/m/a.mp3',
        '/m/b.mp3',
        '/m/c.mp3',
      ]);
    });

    test('名字大小写与首尾空格不同仍视为同一个歌单', () async {
      final service = PlaylistService();
      await service.mergeOrAddPlaylist(name: 'Chill', songs: [song('/m/a.mp3')]);
      final result = await service.mergeOrAddPlaylist(
        name: '  chill  ',
        songs: [song('/m/b.mp3')],
      );

      expect(result.merged, isTrue);
      expect(service.playlists.where((p) => p.name == 'Chill').length, 1);
      expect(result.playlist.songs.length, 2);
    });

    test('不同名新建歌单', () async {
      final service = PlaylistService();
      await service.mergeOrAddPlaylist(name: 'A', songs: [song('/m/a.mp3')]);
      final result = await service.mergeOrAddPlaylist(
        name: 'B',
        songs: [song('/m/b.mp3')],
      );

      expect(result.merged, isFalse);
      expect(result.addedSongs, 1);
      expect(service.playlists.any((p) => p.name == 'B'), isTrue);
    });

    test('空名走兜底，不会生成空标题歌单', () async {
      final service = PlaylistService();
      final result = await service.mergeOrAddPlaylist(
        name: '   ',
        songs: [song('/m/a.mp3')],
      );

      expect(result.playlist.name.trim(), isNotEmpty);
    });
  });
}
