import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vynody/models/music_file.dart';
import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/utils/m3u_utils.dart';
import 'package:vynody/utils/list_reorder_utils.dart';

/// 播放列表排序字段
enum PlaylistSortField {
  custom,
  name,
  trackCount,
  updatedAt,
  createdAt,
}

extension PlaylistSortFieldX on PlaylistSortField {
  String get storageValue => name;
  static PlaylistSortField fromStorageValue(
    String? value,
    PlaylistSortField defaultValue,
  ) {
    if (value == null) return defaultValue;
    return PlaylistSortField.values.firstWhere(
      (e) => e.name == value,
      orElse: () => defaultValue,
    );
  }
}

/// 播放列表模型
class Playlist {
  final String id;
  String name;
  final List<MusicFile> songs;
  final DateTime createdAt;
  DateTime updatedAt;

  Playlist({
    required this.id,
    required this.name,
    List<MusicFile>? songs,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : songs = songs ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  /// 从JSON创建播放列表
  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String,
      name: json['name'] as String,
      songs:
          (json['songs'] as List<dynamic>?)
              ?.map(
                (s) => MusicFile(
                  path: s['path'] as String,
                  name: s['name'] as String,
                  title: s['title'] as String?,
                  artist: s['artist'] as String?,
                  album: s['album'] as String?,
                  trackNumber: s['trackNumber'] as int?,
                  durationMillis: s['durationMillis'] as int?,
                  id: s['id'] as int?,
                  mediaUri: s['mediaUri'] as String?,
                  thumbnailPath: s['thumbnailPath'] as String?,
                  artworkWidth: s['artworkWidth'] as int?,
                  artworkHeight: s['artworkHeight'] as int?,
                  themeColorsBlob: s['themeColorsBlob'] != null
                      ? base64Decode(s['themeColorsBlob'] as String)
                      : null,
                ),
              )
              .toList() ??
          [],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songs': songs
          .map(
            (s) => {
              'path': s.path,
              'name': s.name,
              'title': s.title,
              'artist': s.artist,
              'album': s.album,
              'trackNumber': s.trackNumber,
              'durationMillis': s.durationMillis,
              'id': s.id,
              'mediaUri': s.mediaUri,
              'thumbnailPath': s.thumbnailPath,
              'artworkWidth': s.artworkWidth,
              'artworkHeight': s.artworkHeight,
              'themeColorsBlob': s.themeColorsBlob != null
                  ? base64Encode(s.themeColorsBlob!)
                  : null,
            },
          )
          .toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// 复制并修改
  Playlist copyWith({
    String? id,
    String? name,
    List<MusicFile>? songs,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songs: songs ?? List.from(this.songs),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// 播放列表管理服务
class PlaylistService extends ChangeNotifier {
  final List<Playlist> _playlists = [];
  String? _currentPlaylistId;
  static const String _legacyStorageKey = 'playlists';
  static const String _playlistsFileName = 'playlists.json';
  static const String _currentPlaylistKey = 'current_playlist_id';
  static const String favoritePlaylistId = 'favorites';

  static Future<File> get playlistsFile async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, _playlistsFileName));
  }

  List<Playlist> get playlists => List.unmodifiable(_playlists);
  Playlist? get currentPlaylist => _currentPlaylistId != null
      ? _playlists.firstWhere(
          (p) => p.id == _currentPlaylistId,
          orElse: () => _playlists.isNotEmpty
              ? _playlists.first
              : Playlist(id: 'default', name: '默认列表'),
        )
      : (_playlists.isNotEmpty ? _playlists.first : null);

  PlaylistService() {
    _init();
  }

  /// 初始化，加载保存的播放列表
  Future<void> _init() async {
    await _loadPlaylists();
    if (_disposed) return;
    // 确保内置列表始终存在，并保持在普通列表之后。
    final hasDefault = _playlists.any((p) => p.id == 'default');
    final hasFavorites = _playlists.any((p) => p.id == favoritePlaylistId);

    if (!hasDefault) {
      _playlists.insert(0, Playlist(id: 'default', name: '默认列表'));
    }
    if (!hasFavorites) {
      final favoriteIndex = _playlists.indexWhere((p) => p.id == 'default');
      final insertIndex = favoriteIndex == -1
          ? _playlists.length
          : favoriteIndex + 1;
      _playlists.insert(
        insertIndex,
        Playlist(id: favoritePlaylistId, name: '收藏'),
      );
    }

    if (_playlists.isNotEmpty &&
        (_currentPlaylistId == null ||
            !_playlists.any((p) => p.id == _currentPlaylistId))) {
      _currentPlaylistId = _playlists.first.id;
    }
    if (_disposed) return;
    await _savePlaylists();
    if (_disposed) return;
    notifyListeners();
  }

  List<String> _cachedRootPaths = [];

  /// 从本地存储加载播放列表
  Future<void> _loadPlaylists() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentId = prefs.getString(_currentPlaylistKey);
      _cachedRootPaths = prefs.getStringList('root_paths') ?? [];

      String? jsonString;
      final file = await playlistsFile;
      if (await file.exists()) {
        jsonString = await file.readAsString();
        if (prefs.containsKey(_legacyStorageKey)) {
          await prefs.remove(_legacyStorageKey);
        }
      } else {
        // Fallback: migrate from legacy prefs if present
        jsonString = prefs.getString(_legacyStorageKey);
        if (jsonString != null && jsonString.trim().isNotEmpty) {
          try {
            final parent = file.parent;
            if (!parent.existsSync()) {
              await parent.create(recursive: true);
            }
            final tmpFile = File('${file.path}.tmp');
            await tmpFile.writeAsString(jsonString, flush: true);
            if (await file.exists()) {
              await file.delete();
            }
            await tmpFile.rename(file.path);
            await prefs.remove(_legacyStorageKey);
          } catch (e) {
            debugPrint('Error migrating playlists to file: $e');
          }
        }
      }

      if (jsonString != null && jsonString.trim().isNotEmpty) {
        final List<dynamic> jsonList = json.decode(jsonString);
        _playlists.clear();
        _playlists.addAll(
          jsonList.map(
            (json) => Playlist.fromJson(json as Map<String, dynamic>),
          ),
        );
      }

      _currentPlaylistId = currentId;
    } catch (e) {
      debugPrint('Error loading playlists: $e');
    }
  }

  /// 刷新缓存的扫描根路径
  Future<void> refreshRootPaths() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedRootPaths = prefs.getStringList('root_paths') ?? [];
    } catch (_) {}
  }

  /// 保存播放列表到本地存储
  Future<void> _savePlaylists() async {
    try {
      final jsonString = json.encode(
        _playlists.map((p) => p.toJson()).toList(),
      );
      final file = await playlistsFile;
      final parent = file.parent;
      if (!parent.existsSync()) {
        await parent.create(recursive: true);
      }
      final tmpFile = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
      await tmpFile.writeAsString(jsonString, flush: true);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      if (await tmpFile.exists()) {
        await tmpFile.rename(file.path);
      }

      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_legacyStorageKey)) {
        await prefs.remove(_legacyStorageKey);
      }
      if (_currentPlaylistId != null) {
        await prefs.setString(_currentPlaylistKey, _currentPlaylistId!);
      } else {
        await prefs.remove(_currentPlaylistKey);
      }
    } catch (e) {
      debugPrint('Error saving playlists: $e');
    }
  }

  /// 创建新的播放列表
  Future<Playlist> createPlaylist(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final playlist = Playlist(id: id, name: name);
    _playlists.add(playlist);
    _currentPlaylistId = id;
    await _savePlaylists();
    notifyListeners();
    return playlist;
  }

  /// 添加已构建好的播放列表
  Future<void> addPlaylist(Playlist playlist) async {
    _playlists.add(playlist);
    _currentPlaylistId = playlist.id;
    await _savePlaylists();
    notifyListeners();
  }

  /// 检查是否存在同名播放列表 (不区分大小写，去除首尾空格)
  bool playlistExists(String name, {String? excludeId}) {
    final searchName = name.trim().toLowerCase();
    if (searchName.isEmpty) return false;
    return _playlists.any((p) {
      if (excludeId != null && p.id == excludeId) return false;
      return p.name.trim().toLowerCase() == searchName;
    });
  }

  /// 生成不重复的播放列表名称
  String generateUniquePlaylistName(String baseName) {
    final trimmed = baseName.trim();
    if (trimmed.isEmpty) return generateUniquePlaylistName('新建歌单');
    if (!playlistExists(trimmed)) return trimmed;

    int counter = 1;
    while (playlistExists('$trimmed ($counter)')) {
      counter++;
    }
    return '$trimmed ($counter)';
  }

  /// 从 M3U 文件导入播放列表
  Future<Playlist> importPlaylistFromM3u(
    String filePath, {
    Iterable<String>? rootPaths,
  }) async {
    final file = File(filePath);
    String content;
    try {
      content = await file.readAsString(encoding: utf8);
    } catch (_) {
      content = await file.readAsString(encoding: latin1);
    }

    final data = M3uUtils.parse(content, baseDir: p.dirname(filePath));
    final rawName = data.playlistName?.trim().isNotEmpty == true
        ? data.playlistName!.trim()
        : p.basenameWithoutExtension(filePath);
    final playlistName = generateUniquePlaylistName(rawName);

    final effectiveRoots = rootPaths ?? _cachedRootPaths;
    final songs = await M3uUtils.resolveMusicFiles(
      data.entries,
      rootPaths: effectiveRoots,
    );
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final playlist = Playlist(
      id: id,
      name: playlistName,
      songs: songs,
    );

    _playlists.add(playlist);
    _currentPlaylistId = id;
    await _savePlaylists();
    notifyListeners();
    return playlist;
  }

  /// 批量从 M3U 文件导入播放列表
  Future<List<Playlist>> importPlaylistsFromM3u(
    List<String> filePaths, {
    Iterable<String>? rootPaths,
  }) async {
    final imported = <Playlist>[];
    for (final path in filePaths) {
      try {
        final playlist = await importPlaylistFromM3u(path, rootPaths: rootPaths);
        imported.add(playlist);
      } catch (e) {
        debugPrint('Error importing playlist from $path: $e');
      }
    }
    return imported;
  }

  /// 导出播放列表为 M3U8 字符串
  String exportPlaylistToM3u(
    Playlist playlist, {
    Iterable<String>? rootPaths,
    String? baseDir,
  }) {
    final effectiveRoots = rootPaths ?? _cachedRootPaths;
    return M3uUtils.generate(
      playlist.songs,
      playlistName: playlist.name,
      rootPaths: effectiveRoots,
      baseDir: baseDir,
    );
  }

  /// 删除播放列表
  Future<void> deletePlaylist(String id) async {
    if (id == favoritePlaylistId) {
      return;
    }
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index != -1) {
      _playlists.removeAt(index);
      if (_currentPlaylistId == id) {
        _currentPlaylistId = _playlists.isNotEmpty ? _playlists.first.id : null;
      }
      await _savePlaylists();
      notifyListeners();
    }
  }

  /// 批量删除播放列表
  Future<void> deletePlaylists(Iterable<String> ids) async {
    final toDelete = ids.toSet()..remove(favoritePlaylistId);
    if (toDelete.isEmpty) return;

    final beforeLength = _playlists.length;
    _playlists.removeWhere((p) => toDelete.contains(p.id));
    if (_playlists.length != beforeLength) {
      if (_currentPlaylistId != null && toDelete.contains(_currentPlaylistId)) {
        _currentPlaylistId = _playlists.isNotEmpty ? _playlists.first.id : null;
      }
      notifyListeners();
      await _savePlaylists();
    }
  }

  /// 重命名播放列表
  Future<void> renamePlaylist(String id, String newName) async {
    if (id == favoritePlaylistId) {
      return;
    }
    final index = _playlists.indexWhere((p) => p.id == id);
    if (index != -1) {
      _playlists[index].name = newName;
      _playlists[index].updatedAt = DateTime.now();
      notifyListeners();
      await _savePlaylists();
    }
  }

  /// 切换当前播放列表
  void setCurrentPlaylist(String id) {
    if (_playlists.any((p) => p.id == id)) {
      _currentPlaylistId = id;
      notifyListeners();
      _savePlaylists();
    }
  }

  /// 向播放列表添加歌曲
  Future<void> addSongsToPlaylist(
    String playlistId,
    List<MusicFile> songs,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index].songs.addAll(songs);
      _playlists[index].updatedAt = DateTime.now();
      notifyListeners();
      await _savePlaylists();
    }
  }

  /// 从播放列表移除歌曲
  Future<void> removeSongsFromPlaylist(
    String playlistId,
    List<int> indices,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      // 按索引降序排序后删除，避免索引错位
      final sortedIndices = List<int>.from(indices)
        ..sort((a, b) => b.compareTo(a));
      for (final idx in sortedIndices) {
        if (idx >= 0 && idx < _playlists[index].songs.length) {
          _playlists[index].songs.removeAt(idx);
        }
      }
      _playlists[index].updatedAt = DateTime.now();
      notifyListeners();
      await _savePlaylists();
    }
  }

  /// 重新排序播放列表 (拖拽排序)
  Future<void> reorderPlaylist(int oldIndex, int newIndex) async {
    if (oldIndex < _playlists.length && newIndex <= _playlists.length) {
      if (newIndex > oldIndex) newIndex--;
      final item = _playlists.removeAt(oldIndex);
      _playlists.insert(newIndex, item);
      notifyListeners();
      await _savePlaylists();
    }
  }

  /// 按规则排序播放列表
  Future<void> sortPlaylists({
    required PlaylistSortField field,
    required bool ascending,
    bool pinFavoritesAndDefault = true,
  }) async {
    if (field == PlaylistSortField.custom) return;

    final List<Playlist> pinned = [];
    final List<Playlist> normal = [];

    for (final p in _playlists) {
      if (pinFavoritesAndDefault &&
          (p.id == favoritePlaylistId || p.id == 'default')) {
        pinned.add(p);
      } else {
        normal.add(p);
      }
    }

    pinned.sort((a, b) {
      if (a.id == 'default') return -1;
      if (b.id == 'default') return 1;
      return 0;
    });

    int Function(Playlist, Playlist) comparator;
    switch (field) {
      case PlaylistSortField.name:
        comparator = (a, b) =>
            compareNatural(a.name.toLowerCase(), b.name.toLowerCase());
        break;
      case PlaylistSortField.trackCount:
        comparator = (a, b) => a.songs.length.compareTo(b.songs.length);
        break;
      case PlaylistSortField.updatedAt:
        comparator = (a, b) => a.updatedAt.compareTo(b.updatedAt);
        break;
      case PlaylistSortField.createdAt:
        comparator = (a, b) => a.createdAt.compareTo(b.createdAt);
        break;
      case PlaylistSortField.custom:
        comparator = (a, b) => 0;
        break;
    }

    if (!ascending) {
      final base = comparator;
      comparator = (a, b) => base(b, a);
    }

    normal.sort(comparator);

    _playlists
      ..clear()
      ..addAll(pinned)
      ..addAll(normal);

    notifyListeners();
    await _savePlaylists();
  }

  /// 重新排序播放列表中的歌曲
  Future<void> reorderSongsInPlaylist(
    String playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      final songs = _playlists[index].songs;
      if (ListReorderUtils.moveItem(songs, oldIndex, newIndex)) {
        _playlists[index].updatedAt = DateTime.now();
        notifyListeners();
        await _savePlaylists();
      }
    }
  }

  /// 清空播放列表
  Future<void> clearPlaylist(String playlistId) async {
    final index = _playlists.indexWhere((p) => p.id == playlistId);
    if (index != -1) {
      _playlists[index].songs.clear();
      _playlists[index].updatedAt = DateTime.now();
      notifyListeners();
      await _savePlaylists();
    }
  }

  Playlist? get favoritePlaylist {
    try {
      return _playlists.firstWhere((p) => p.id == favoritePlaylistId);
    } catch (_) {
      return null;
    }
  }

  bool isFavoriteSong(MusicFile song) {
    return favoritePlaylist?.songs.any((item) => item.path == song.path) ??
        false;
  }

  Future<bool> toggleFavoriteSong(MusicFile song) async {
    final index = _playlists.indexWhere((p) => p.id == favoritePlaylistId);
    if (index == -1) return false;

    final playlist = _playlists[index];
    final existingIndex = playlist.songs.indexWhere(
      (item) => item.path == song.path,
    );
    final wasAdded = existingIndex == -1;

    if (existingIndex == -1) {
      playlist.songs.add(song);
    } else {
      playlist.songs.removeAt(existingIndex);
    }

    playlist.updatedAt = DateTime.now();
    await _savePlaylists();
    notifyListeners();
    return wasAdded;
  }

  Future<void> addSongToFavorite(MusicFile song) async {
    final index = _playlists.indexWhere((p) => p.id == favoritePlaylistId);
    if (index == -1) return;

    final playlist = _playlists[index];
    final existingIndex = playlist.songs.indexWhere(
      (item) => item.path == song.path,
    );
    if (existingIndex == -1) {
      playlist.songs.add(song);
    } else {
      playlist.songs[existingIndex] = song;
    }
    playlist.updatedAt = DateTime.now();
    await _savePlaylists();
    notifyListeners();
  }

  Future<void> updateSongMetadataByPath(
    SongMetadata metadata, {
    Uint8List? artworkBytes,
  }) async {
    bool changed = false;
    final isArtworkCleared = artworkBytes != null && artworkBytes.isEmpty;

    for (final playlist in _playlists) {
      for (var i = 0; i < playlist.songs.length; i++) {
        final song = playlist.songs[i];
        if (song.path != metadata.path) continue;

        playlist.songs[i] = song.copyWith(
          title: metadata.title,
          artist: metadata.artist,
          albumArtist: metadata.albumArtist,
          album: metadata.album,
          trackNumber: metadata.trackNumber,
          thumbnailPath: isArtworkCleared ? null : (metadata.thumbnailPath ?? song.thumbnailPath),
          artworkPath: isArtworkCleared ? null : (metadata.artworkPath ?? song.artworkPath),
          artworkWidth: isArtworkCleared ? null : (metadata.artworkWidth ?? song.artworkWidth),
          artworkHeight: isArtworkCleared ? null : (metadata.artworkHeight ?? song.artworkHeight),
          themeColorsBlob: isArtworkCleared ? null : (metadata.themeColorsBlob ?? song.themeColorsBlob),
          artworkBytes: isArtworkCleared ? null : (artworkBytes ?? song.artworkBytes),
          lastModifiedTime: metadata.lastModifiedTime,
        );

        playlist.updatedAt = DateTime.now();
        changed = true;
      }
    }

    if (changed) {
      await _savePlaylists();
      notifyListeners();
    }
  }

  void setSongMissingStateByPath(String path, bool isMissing) {
    var changed = false;
    for (final playlist in _playlists) {
      for (var i = 0; i < playlist.songs.length; i++) {
        final song = playlist.songs[i];
        if (song.path != path || song.isMissing == isMissing) continue;

        playlist.songs[i] = song.copyWith(isMissing: isMissing);
        changed = true;
      }
    }

    if (changed) {
      notifyListeners();
    }
  }

  bool _disposed = false;
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
