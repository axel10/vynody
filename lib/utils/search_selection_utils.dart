import '../models/album_summary.dart';
import '../models/artist_summary.dart';
import '../models/music_file.dart';
import '../models/music_folder.dart';
import '../player/library/playlist_service.dart';

/// 搜索结果里一条可选中条目的类型。
enum SearchEntryKind { song, folder, album, artist, playlist }

/// 搜索页的统一选择键：`<kind>:<id>`。
///
/// 两个本地搜索页共用一套选择集，键里必须带类型前缀。虽然歌曲 / 文件夹用
/// 文件路径、专辑 / 歌单用 id，实际撞车概率很低，但同一页里不同分节的条目
/// 混放在同一个 `Set<String>` 里时，不带前缀就无法从键反推它属于哪一段，
/// 展开成歌曲、刷新缓存都无从下手。
String _keyOf(SearchEntryKind kind, String id) => '${kind.name}:$id';

String songSelectionKey(String path) =>
    _keyOf(SearchEntryKind.song, path.trim());

String folderSelectionKey(String path) =>
    _keyOf(SearchEntryKind.folder, path.trim());

String albumSelectionKey(String id) => _keyOf(SearchEntryKind.album, id.trim());

String artistSelectionKey(String queryKey) =>
    _keyOf(SearchEntryKind.artist, queryKey.trim());

String playlistSelectionKey(String id) =>
    _keyOf(SearchEntryKind.playlist, id.trim());

/// 一条搜索结果条目的最小描述。
///
/// 只带「展开成歌曲」与「画勾选态」需要的东西，不复制实体本身——实体对象
/// 仍然是页面手里那一份，避免出现两份不同步的副本。
class SearchEntry {
  const SearchEntry({
    required this.kind,
    required this.key,
    this.song,
    this.folder,
    this.album,
    this.artist,
    this.playlist,
  });

  factory SearchEntry.song(MusicFile song) => SearchEntry(
    kind: SearchEntryKind.song,
    key: songSelectionKey(song.path),
    song: song,
  );

  factory SearchEntry.folder(MusicFolder folder) => SearchEntry(
    kind: SearchEntryKind.folder,
    key: folderSelectionKey(folder.path),
    folder: folder,
  );

  factory SearchEntry.album(AlbumSummary album) => SearchEntry(
    kind: SearchEntryKind.album,
    key: albumSelectionKey(album.id),
    album: album,
  );

  factory SearchEntry.artist(ArtistSummary artist) => SearchEntry(
    kind: SearchEntryKind.artist,
    key: artistSelectionKey(artist.queryKey),
    artist: artist,
  );

  factory SearchEntry.playlist(Playlist playlist) => SearchEntry(
    kind: SearchEntryKind.playlist,
    key: playlistSelectionKey(playlist.id),
    playlist: playlist,
  );

  final SearchEntryKind kind;
  final String key;
  final MusicFile? song;
  final MusicFolder? folder;
  final AlbumSummary? album;
  final ArtistSummary? artist;
  final Playlist? playlist;
}

/// 把选择集里的条目展开成去重后的歌曲列表。
///
/// 集合类条目（专辑 / 艺术家 / 歌单 / 文件夹）一律取它的全部歌曲，单曲条目
/// 取自身。文件夹是搜索结果的空壳 `MusicFolder(path, name)`，`allSongs` 恒空，
/// 所以它的歌曲由调用方注入的 [loadFolderSongs] 提供
/// （页面传 `scanner.getSongsForFolder`，它内部先查内存树、再回退 DB 按路径查）。
///
/// 多个文件夹的查询并行发起，避免一次选中多个目录时串行等待。
Future<List<MusicFile>> expandSearchEntries(
  Iterable<SearchEntry> entries,
  Future<List<MusicFile>> Function(MusicFolder folder) loadFolderSongs,
) async {
  final list = entries.toList(growable: false);

  final folderSongs = <String, Future<List<MusicFile>>>{};
  for (final entry in list) {
    final folder = entry.folder;
    if (entry.kind == SearchEntryKind.folder && folder != null) {
      folderSongs[entry.key] = loadFolderSongs(folder);
    }
  }

  final songs = <MusicFile>[];
  final seenPaths = <String>{};
  void addAll(Iterable<MusicFile> batch) {
    for (final song in batch) {
      if (seenPaths.add(song.path)) songs.add(song);
    }
  }

  for (final entry in list) {
    switch (entry.kind) {
      case SearchEntryKind.song:
        final song = entry.song;
        if (song != null) addAll([song]);
        break;
      case SearchEntryKind.album:
        final album = entry.album;
        if (album != null) addAll(album.songs);
        break;
      case SearchEntryKind.artist:
        final artist = entry.artist;
        if (artist != null) addAll(artist.songs);
        break;
      case SearchEntryKind.playlist:
        final playlist = entry.playlist;
        if (playlist != null) addAll(playlist.songs);
        break;
      case SearchEntryKind.folder:
        final pending = folderSongs[entry.key];
        if (pending != null) addAll(await pending);
        break;
    }
  }

  return songs;
}
