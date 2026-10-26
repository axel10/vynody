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
  Future<Map<String, dynamic>?> getArtist(String artistId, {String? artistName});
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

  /// 流派列表，元素形如
  /// `{id, name, songCount, albumCount, coverArt}`。
  Future<List<Map<String, dynamic>>> getGenres();

  /// 取某个流派下的歌曲。`genreId` 为该流派在 [getGenres] 中的 `id`
  /// （Subsonic 侧没有独立 ID，传流派名即可）。
  Future<List<Map<String, dynamic>>> getSongsByGenre(
    String genreId, {
    int count = 500,
    int offset = 0,
  });

  /// 取某个流派下的专辑，元素形如
  /// `{id, title, name, artist, songCount, coverArt, year}`。
  ///
  /// 之所以单独查专辑而不是由歌曲聚合：服务器统计的「专辑数」是按专辑实体
  /// 的流派算的，而歌曲列表只包含自身流派命中该流派的曲目，两者可能不一致
  /// （整张专辑有 20 首，其中只有 3 首带该流派标签时，聚合只能得到 1 张专辑，
  /// 但服务器的专辑数依然是 1；差异出现在专辑级流派与曲目级流派不同的库）。
  /// Subsonic 侧流派没有 ID，用流派名走 `getAlbumList2?type=byGenre`。
  Future<List<Map<String, dynamic>>> getAlbumsByGenre({
    required String genreId,
    required String genreName,
    int count = 500,
    int offset = 0,
  });

  /// 只取某张专辑的曲目（不含专辑信息），用于流派页横屏的专辑分组。
  Future<List<Map<String, dynamic>>> getAlbumSongs(String albumId);

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
  Future<List<Map<String, dynamic>>> getStarredAlbums();
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
  Future<Map<String, dynamic>?> getArtist(String artistId, {String? artistName}) =>
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
  Future<List<Map<String, dynamic>>> getGenres() => client.getGenres();

  @override
  Future<List<Map<String, dynamic>>> getSongsByGenre(
    String genreId, {
    int count = 500,
    int offset = 0,
  }) =>
      client.getSongsByGenre(genreId, count: count, offset: offset);

  @override
  Future<List<Map<String, dynamic>>> getAlbumsByGenre({
    required String genreId,
    required String genreName,
    int count = 500,
    int offset = 0,
  }) =>
      client.getAlbumsByGenre(
        genreId: genreId,
        genreName: genreName,
        count: count,
        offset: offset,
      );

  @override
  Future<List<Map<String, dynamic>>> getAlbumSongs(String albumId) =>
      client.getAlbumSongs(albumId);

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
  Future<List<Map<String, dynamic>>> getStarredAlbums() =>
      client.getStarredAlbums();

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
  Future<Map<String, dynamic>?> getArtist(String artistId, {String? artistName}) =>
      client.getArtist(artistId, artistName: artistName);

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
  Future<List<Map<String, dynamic>>> getGenres() => client.getGenres();

  @override
  Future<List<Map<String, dynamic>>> getSongsByGenre(
    String genreId, {
    int count = 500,
    int offset = 0,
  }) =>
      client.getSongsByGenre(genreId, count: count, offset: offset);

  @override
  Future<List<Map<String, dynamic>>> getAlbumsByGenre({
    required String genreId,
    required String genreName,
    int count = 500,
    int offset = 0,
  }) =>
      client.getAlbumsByGenre(
        genreId: genreId,
        genreName: genreName,
        count: count,
        offset: offset,
      );

  @override
  Future<List<Map<String, dynamic>>> getAlbumSongs(String albumId) =>
      client.getAlbumSongs(albumId);

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
  Future<List<Map<String, dynamic>>> getStarredAlbums() =>
      client.getStarredAlbums();

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
