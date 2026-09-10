import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:vynody/player/remote/remote_server_models.dart';
import 'package:vynody/player/remote/remote_server_storage.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';
import 'package:vynody/player/remote/clients/webdav_client.dart';
import 'package:vynody/player/remote/clients/jellyfin_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late RemoteServerStorage storage;
  late RemoteMediaResolver resolver;

  final subsonicServer = RemoteServer(
    id: 'subsonic_test',
    name: 'My Navidrome',
    type: RemoteServerType.subsonic,
    url: 'http://example.com:4533',
    username: 'alice',
    createdAt: DateTime.now(),
  );

  final webdavServer = RemoteServer(
    id: 'webdav_test',
    name: 'My WebDAV',
    type: RemoteServerType.webdav,
    url: 'http://example.com/dav',
    username: 'bob',
    createdAt: DateTime.now(),
  );

  setUp(() async {
    HttpOverrides.global = null;
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    storage = RemoteServerStorage(prefs: prefs);
    await storage.saveServers([subsonicServer, webdavServer]);
    await storage.savePassword(subsonicServer.id, 'alice_pwd');
    await storage.savePassword(webdavServer.id, 'bob_pwd');

    resolver = RemoteMediaResolver(storage: storage);
  });

  test('RemoteMediaResolver parses virtual URIs correctly', () {
    expect(RemoteMediaResolver.isRemoteUri('subsonic://subsonic_test/track_123'), isTrue);
    expect(RemoteMediaResolver.isRemoteUri('webdav://webdav_test/Music/Song.flac'), isTrue);
    expect(RemoteMediaResolver.isRemoteUri('/local/path/song.mp3'), isFalse);

    final subInfo = RemoteMediaResolver.parseUri('subsonic://subsonic_test/track_123');
    expect(subInfo?.type, RemoteServerType.subsonic);
    expect(subInfo?.serverId, 'subsonic_test');
    expect(subInfo?.trackIdOrPath, 'track_123');

    final davInfo = RemoteMediaResolver.parseUri('webdav://webdav_test/Music/Song.flac');
    expect(davInfo?.type, RemoteServerType.webdav);
    expect(davInfo?.serverId, 'webdav_test');
    expect(davInfo?.trackIdOrPath, '/Music/Song.flac');

    final davInfoWithSpace = RemoteMediaResolver.parseUri('webdav://webdav_test/dav/test/Heartbeat Song (feat. Artist).flac');
    expect(davInfoWithSpace?.type, RemoteServerType.webdav);
    expect(davInfoWithSpace?.serverId, 'webdav_test');
    expect(davInfoWithSpace?.trackIdOrPath, '/dav/test/Heartbeat Song (feat. Artist).flac');

    final davInfoEncoded = RemoteMediaResolver.parseUri('webdav://webdav_test/dav/test/Heartbeat%20Song.flac');
    expect(davInfoEncoded?.type, RemoteServerType.webdav);
    expect(davInfoEncoded?.serverId, 'webdav_test');
    expect(davInfoEncoded?.trackIdOrPath, '/dav/test/Heartbeat Song.flac');
  });

  test('RemoteMediaResolver creates MusicFiles from Subsonic and WebDAV responses', () {
    final subSong = RemoteMediaResolver.buildMusicFileFromSubsonic({
      'id': 'tr_01',
      'title': 'Test Song',
      'artist': 'Test Artist',
      'album': 'Test Album',
      'duration': 180,
      'suffix': 'flac',
      'coverArt': 'cover_01',
    }, subsonicServer);

    expect(subSong.path, 'subsonic://subsonic_test/tr_01');
    expect(subSong.title, 'Test Song');
    expect(subSong.artist, 'Test Artist');
    expect(subSong.album, 'Test Album');
    expect(subSong.durationMillis, 180000);
    expect(subSong.artworkPath, 'subsonic-cover://subsonic_test/cover_01');

    final davFile = WebDavFile(
      path: '/Music/TestTrack.mp3',
      name: 'TestTrack.mp3',
      isDirectory: false,
      contentLength: 5000000,
    );
    final davSong = RemoteMediaResolver.buildMusicFileFromWebDav(davFile, webdavServer);
    expect(davSong.path, 'webdav://webdav_test/Music/TestTrack.mp3');
    expect(davSong.name, 'TestTrack.mp3');
    expect(davSong.title, 'TestTrack');
  });

  test('RemoteMediaResolver resolves playable sources with URL, headers and cacheKey', () async {
    final subSource = await resolver.resolvePlayableSource('subsonic://subsonic_test/track_123');
    expect(subSource.uri, contains('example.com:4533/rest/stream'));
    expect(subSource.uri, contains('u=alice'));
    expect(subSource.uri, contains('id=track_123'));
    expect(subSource.cacheKey, 'subsonic_test:track_123');

    final davSource = await resolver.resolvePlayableSource('webdav://webdav_test/Music/Song.flac');
    expect(davSource.uri, 'http://bob:bob_pwd@example.com/dav/Music/Song.flac');
    expect(davSource.headers?['Authorization'], isNotNull);
    expect(davSource.cacheKey, 'webdav_test:/Music/Song.flac');
  });

  test('RemoteMediaResolver parses and resolves Jellyfin virtual URIs', () {
    expect(RemoteMediaResolver.isRemoteUri('jellyfin://jellyfin_test/item_789'), isTrue);

    final jfInfo = RemoteMediaResolver.parseUri('jellyfin://jellyfin_test/item_789');
    expect(jfInfo?.type, RemoteServerType.jellyfin);
    expect(jfInfo?.serverId, 'jellyfin_test');
    expect(jfInfo?.trackIdOrPath, 'item_789');

    final jfSong = RemoteMediaResolver.buildMusicFileFromJellyfin({
      'id': 'item_789',
      'title': 'Jellyfin Track',
      'artist': 'Jellyfin Artist',
      'album': 'Jellyfin Album',
      'duration': 210,
      'suffix': 'mp3',
      'coverArt': 'item_789',
    }, RemoteServer(
      id: 'jellyfin_test',
      name: 'My Jellyfin',
      type: RemoteServerType.jellyfin,
      url: 'http://example.com:8096',
      username: 'charlie',
      createdAt: DateTime.now(),
    ));

    expect(jfSong.path, 'jellyfin://jellyfin_test/item_789');
    expect(jfSong.title, 'Jellyfin Track');
    expect(jfSong.artist, 'Jellyfin Artist');
    expect(jfSong.album, 'Jellyfin Album');
    expect(jfSong.durationMillis, 210000);
    expect(jfSong.artworkPath, 'jellyfin-cover://jellyfin_test/item_789');

    expect(RemoteMediaResolver.extractTrackId(jfSong), 'item_789');
  });

  test('JellyfinClient item normalization formats items to standardized schema', () {
    final rawItem = {
      'Id': 'item_abc',
      'Name': 'Midnight City',
      'Artists': ['M83'],
      'Album': 'Hurry Up, We\'re Dreaming',
      'AlbumId': 'alb_123',
      'RunTimeTicks': 2430000000, // 243 seconds
      'Container': 'flac',
      'IndexNumber': 5,
      'ParentIndexNumber': 1,
      'ProductionYear': 2011,
      'UserData': {'IsFavorite': true},
    };

    final normalized = JellyfinClient.normalizeSongItem(rawItem);
    expect(normalized['id'], 'item_abc');
    expect(normalized['title'], 'Midnight City');
    expect(normalized['artist'], 'M83');
    expect(normalized['album'], 'Hurry Up, We\'re Dreaming');
    expect(normalized['albumId'], 'alb_123');
    expect(normalized['duration'], 243);
    expect(normalized['track'], 5);
    expect(normalized['discNumber'], 1);
    expect(normalized['year'], 2011);
    expect(normalized['isFavorite'], isTrue);
    expect(normalized['starred'], isNotNull);
  });
}
