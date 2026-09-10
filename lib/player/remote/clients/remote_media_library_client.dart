import '../../../models/music_file.dart';
import '../proxy/remote_media_resolver.dart';
import '../remote_server_models.dart';
import 'jellyfin_client.dart';
import 'subsonic_client.dart';

/// Unified abstraction for structured remote media servers (Navidrome/Subsonic, Jellyfin).
abstract class RemoteMediaLibraryClient {
  RemoteServer get server;
  String get password;

  Future<ConnectionTestResult> testConnection();
  Future<List<Map<String, dynamic>>> getArtists();
  Future<Map<String, dynamic>?> getArtist(String artistId);
  Future<Map<String, dynamic>?> getArtistInfo(String artistId);
  Future<List<Map<String, dynamic>>> getAlbumList({
    String type = 'alphabeticalByName',
    int size = 500,
    int offset = 0,
  });
  Future<Map<String, dynamic>?> getAlbum(String albumId);
  Future<Map<String, dynamic>?> getSong(String songId);
  Future<List<Map<String, dynamic>>> getSongs({
    String query = '',
    int count = 500,
    int offset = 0,
  });
  Future<List<Map<String, dynamic>>> getPlaylists();
  Future<Map<String, dynamic>?> getPlaylist(String playlistId);
  Future<Map<String, dynamic>?> createPlaylist({
    required String name,
    List<String>? songIds,
  });
  Future<bool> updatePlaylist({
    required String playlistId,
    String? name,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
  });
  Future<bool> deletePlaylist(String playlistId);
  Future<Map<String, dynamic>> search(
    String query, {
    int artistCount = 20,
    int albumCount = 20,
    int songCount = 50,
  });
  Future<List<Map<String, dynamic>>> getStarredSongs();
  Future<List<Map<String, dynamic>>> getStarredArtists();
  Future<bool> star({String? id, String? albumId, String? artistId});
  Future<bool> unstar({String? id, String? albumId, String? artistId});
  String buildStreamUrl(String trackId, {int? maxBitRate});
  String buildCoverArtUrl(String itemId, {int size = 300});
  MusicFile buildMusicFile(Map<String, dynamic> trackJson);

  /// Factory constructor to create the appropriate client implementation.
  static RemoteMediaLibraryClient create({
    required RemoteServer server,
    required String password,
  }) {
    if (server.type == RemoteServerType.jellyfin) {
      return JellyfinMediaLibraryClient(
        client: JellyfinClient(server: server, password: password),
        server: server,
        password: password,
      );
    }
    return SubsonicMediaLibraryClient(
      client: SubsonicClient(server: server, password: password),
      server: server,
      password: password,
    );
  }
}

class SubsonicMediaLibraryClient implements RemoteMediaLibraryClient {
  final SubsonicClient client;
  @override
  final RemoteServer server;
  @override
  final String password;

  SubsonicMediaLibraryClient({
    required this.client,
    required this.server,
    required this.password,
  });

  @override
  Future<ConnectionTestResult> testConnection() => client.testConnection();

  @override
  Future<List<Map<String, dynamic>>> getArtists() => client.getArtists();

  @override
  Future<Map<String, dynamic>?> getArtist(String artistId) =>
      client.getArtist(artistId);

  @override
  Future<Map<String, dynamic>?> getArtistInfo(String artistId) =>
      client.getArtistInfo(artistId);

  @override
  Future<List<Map<String, dynamic>>> getAlbumList({
    String type = 'alphabeticalByName',
    int size = 500,
    int offset = 0,
  }) =>
      client.getAlbumList(type: type, size: size, offset: offset);

  @override
  Future<Map<String, dynamic>?> getAlbum(String albumId) =>
      client.getAlbum(albumId);

  @override
  Future<Map<String, dynamic>?> getSong(String songId) =>
      client.getSong(songId);

  @override
  Future<List<Map<String, dynamic>>> getSongs({
    String query = '',
    int count = 500,
    int offset = 0,
  }) =>
      client.getSongs(query: query, count: count, offset: offset);

  @override
  Future<List<Map<String, dynamic>>> getPlaylists() => client.getPlaylists();

  @override
  Future<Map<String, dynamic>?> getPlaylist(String playlistId) =>
      client.getPlaylist(playlistId);

  @override
  Future<Map<String, dynamic>?> createPlaylist({
    required String name,
    List<String>? songIds,
  }) =>
      client.createPlaylist(name: name, songIds: songIds);

  @override
  Future<bool> updatePlaylist({
    required String playlistId,
    String? name,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
  }) =>
      client.updatePlaylist(
        playlistId: playlistId,
        name: name,
        songIdsToAdd: songIdsToAdd,
        songIndexesToRemove: songIndexesToRemove,
      );

  @override
  Future<bool> deletePlaylist(String playlistId) =>
      client.deletePlaylist(playlistId);

  @override
  Future<Map<String, dynamic>> search(
    String query, {
    int artistCount = 20,
    int albumCount = 20,
    int songCount = 50,
  }) =>
      client.search(
        query,
        artistCount: artistCount,
        albumCount: albumCount,
        songCount: songCount,
      );

  @override
  Future<List<Map<String, dynamic>>> getStarredSongs() =>
      client.getStarredSongs();

  @override
  Future<List<Map<String, dynamic>>> getStarredArtists() =>
      client.getStarredArtists();

  @override
  Future<bool> star({String? id, String? albumId, String? artistId}) =>
      client.star(id: id, albumId: albumId, artistId: artistId);

  @override
  Future<bool> unstar({String? id, String? albumId, String? artistId}) =>
      client.unstar(id: id, albumId: albumId, artistId: artistId);

  @override
  String buildStreamUrl(String trackId, {int? maxBitRate}) =>
      client.buildStreamUrl(trackId, maxBitRate: maxBitRate);

  @override
  String buildCoverArtUrl(String itemId, {int size = 300}) =>
      client.buildCoverArtUrl(itemId, size: size);

  @override
  MusicFile buildMusicFile(Map<String, dynamic> trackJson) =>
      RemoteMediaResolver.buildMusicFileFromSubsonic(trackJson, server);
}

class JellyfinMediaLibraryClient implements RemoteMediaLibraryClient {
  final JellyfinClient client;
  @override
  final RemoteServer server;
  @override
  final String password;

  JellyfinMediaLibraryClient({
    required this.client,
    required this.server,
    required this.password,
  });

  @override
  Future<ConnectionTestResult> testConnection() => client.testConnection();

  @override
  Future<List<Map<String, dynamic>>> getArtists() => client.getArtists();

  @override
  Future<Map<String, dynamic>?> getArtist(String artistId) =>
      client.getArtist(artistId);

  @override
  Future<Map<String, dynamic>?> getArtistInfo(String artistId) =>
      client.getArtistInfo(artistId);

  @override
  Future<List<Map<String, dynamic>>> getAlbumList({
    String type = 'alphabeticalByName',
    int size = 500,
    int offset = 0,
  }) =>
      client.getAlbumList(type: type, size: size, offset: offset);

  @override
  Future<Map<String, dynamic>?> getAlbum(String albumId) =>
      client.getAlbum(albumId);

  @override
  Future<Map<String, dynamic>?> getSong(String songId) =>
      client.getSong(songId);

  @override
  Future<List<Map<String, dynamic>>> getSongs({
    String query = '',
    int count = 500,
    int offset = 0,
  }) =>
      client.getSongs(query: query, count: count, offset: offset);

  @override
  Future<List<Map<String, dynamic>>> getPlaylists() => client.getPlaylists();

  @override
  Future<Map<String, dynamic>?> getPlaylist(String playlistId) =>
      client.getPlaylist(playlistId);

  @override
  Future<Map<String, dynamic>?> createPlaylist({
    required String name,
    List<String>? songIds,
  }) =>
      client.createPlaylist(name: name, songIds: songIds);

  @override
  Future<bool> updatePlaylist({
    required String playlistId,
    String? name,
    List<String>? songIdsToAdd,
    List<int>? songIndexesToRemove,
  }) =>
      client.updatePlaylist(
        playlistId: playlistId,
        name: name,
        songIdsToAdd: songIdsToAdd,
        songIndexesToRemove: songIndexesToRemove,
      );

  @override
  Future<bool> deletePlaylist(String playlistId) =>
      client.deletePlaylist(playlistId);

  @override
  Future<Map<String, dynamic>> search(
    String query, {
    int artistCount = 20,
    int albumCount = 20,
    int songCount = 50,
  }) =>
      client.search(
        query,
        artistCount: artistCount,
        albumCount: albumCount,
        songCount: songCount,
      );

  @override
  Future<List<Map<String, dynamic>>> getStarredSongs() =>
      client.getStarredSongs();

  @override
  Future<List<Map<String, dynamic>>> getStarredArtists() =>
      client.getStarredArtists();

  @override
  Future<bool> star({String? id, String? albumId, String? artistId}) =>
      client.star(id: id, albumId: albumId, artistId: artistId);

  @override
  Future<bool> unstar({String? id, String? albumId, String? artistId}) =>
      client.unstar(id: id, albumId: albumId, artistId: artistId);

  @override
  String buildStreamUrl(String trackId, {int? maxBitRate}) =>
      client.buildStreamUrl(trackId, maxBitRate: maxBitRate);

  @override
  String buildCoverArtUrl(String itemId, {int size = 300}) =>
      client.buildCoverArtUrl(itemId, size: size);

  @override
  MusicFile buildMusicFile(Map<String, dynamic> trackJson) =>
      RemoteMediaResolver.buildMusicFileFromJellyfin(trackJson, server);
}
