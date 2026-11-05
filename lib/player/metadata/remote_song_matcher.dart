import 'dart:io';

import 'package:vynody/player/metadata/metadata_database.dart';
import 'package:vynody/player/remote/proxy/remote_media_resolver.dart';

/// 跨设备匹配用的文本归一化：小写 + 去掉全部标点与空白，只留字母、数字与 CJK。
///
/// 两边（远端条目 / 本地曲目）必须用**同一个**函数归一，否则会出现「看起来
/// 一样却匹配不上」。此前 `sharing_service._normalizeMetadataString` 与
/// `m3u_utils` 的匹配各自造轮子，这里收敛成唯一入口。
String normalizeSongMatchText(String? value) {
  if (value == null || value.isEmpty) return '';
  return value.toLowerCase().replaceAll(_nonMatchChars, '');
}

final RegExp _nonMatchChars = RegExp(r'[^a-z0-9\u4e00-\u9fff]+');

/// 艺术家字段的常见分隔写法。
///
/// `A feat. B`、`A ft. B`、`A & B`、`A, B`、`A、B` 指向的是同一批人，但归一化
/// 后整串并不相等（`afeatb` vs `ab`）。所以按分隔符拆出每个参与者作为**额外**
/// 的可匹配键，整串归一化结果仍然保留为首选键。
///
/// 不拆 `/` 与 `;`：`AC/DC`、`Simon & Garfunkel; Art Garfunkel` 这类写法里，
/// 拆开会让「AC」这种短名字误命中「AC/DC」。
final RegExp _artistSeparators = RegExp(
  r'(?:\bfeat\.?|\bft\.?|&|,|，|、|×)',
  caseSensitive: false,
);

/// 返回艺术家可参与匹配的键集合，整串归一化结果排在第一个。
List<String> artistMatchKeys(String? artist) {
  final full = normalizeSongMatchText(artist);
  if (full.isEmpty) return const [''];
  final keys = <String>[full];
  for (final part in artist!.split(_artistSeparators)) {
    final key = normalizeSongMatchText(part);
    if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
  }
  return keys;
}

/// 一次内存匹配的结果。
class RemoteSongMatch {
  const RemoteSongMatch({required this.matches, required this.ambiguous});

  static const RemoteSongMatch empty = RemoteSongMatch(
    matches: [],
    ambiguous: false,
  );

  /// 经过时长与专辑收敛后的候选，最可能的排在最前。
  final List<SongMetadata> matches;

  /// 收敛后仍有多个候选（同名不同版本 / 同一首歌在多个目录各存一份）。
  ///
  /// 为 true 时 `matches.first` 仍是一个合理选择，但调用方应当把它计入
  /// `ambiguous` 而不是假装唯一命中。
  final bool ambiguous;

  bool get isEmpty => matches.isEmpty;
  SongMetadata? get best => matches.isEmpty ? null : matches.first;
}

/// 本地文件存在性探针：把逐次 `existsSync()` 换成带缓存的异步探测。
///
/// 歌单解析的「右到左子路径穷举」会对每首歌做 `目录段数 × 根目录数` 次探测，
/// 同步调用全压在 UI isolate 上；改成异步后同样的次数不再阻塞渲染。
class LocalFileProbe {
  final Map<String, Future<bool>> _cache = {};

  Future<bool> exists(String path) {
    if (path.isEmpty) return Future<bool>.value(false);
    return _cache.putIfAbsent(path, () => File(path).exists());
  }
}

/// 把「远端条目」映射到本地曲库的单一实现。
///
/// 曲库只读一遍，归一化只算一遍，之后每条条目都是内存查表：此前
/// `_importLyricsList` 每条远端条目都要对全库跑一次正则归一化（O(N²)），
/// 3000 首的库要跑上千万次 `replaceAll`，主 isolate 直接卡住。
class RemoteSongMatcher {
  RemoteSongMatcher._(this.db, List<SongMetadata> songs, this.probe) {
    for (final song in songs) {
      _index(song);
    }
  }

  /// 读一遍全库并建索引。库为空时也要能构造，只是一个都匹配不上。
  static Future<RemoteSongMatcher> build({
    MetadataDatabase? db,
    LocalFileProbe? probe,
  }) async {
    final target = db ?? MetadataDatabase();
    final songs = await target.getAllSongMetadata();
    return RemoteSongMatcher._(target, songs, probe ?? LocalFileProbe());
  }

  final MetadataDatabase db;
  final LocalFileProbe probe;

  final Map<String, SongMetadata> _byPath = {};
  final Map<String, List<SongMetadata>> _byFileName = {};
  final Map<String, List<SongMetadata>> _byTitleArtist = {};
  final Map<String, List<SongMetadata>> _byTitle = {};

  int _songCount = 0;

  /// 建索引时读到的曲目数，用于日志与「曲库还没扫完」的判断。
  int get songCount => _songCount;

  void _index(SongMetadata song) {
    _songCount++;

    final pathKey = _pathKey(song.path);
    if (pathKey.isNotEmpty) _byPath[pathKey] = song;

    final fileNameKey = _fileNameKey(song.path);
    if (fileNameKey.isNotEmpty) {
      _addToBucket(_byFileName, fileNameKey, song);
    }

    final titleKey = normalizeSongMatchText(song.title);
    if (titleKey.isEmpty) return;
    _addToBucket(_byTitle, titleKey, song);
    for (final artistKey in artistMatchKeys(song.artist)) {
      _addToBucket(_byTitleArtist, _titleArtistKey(titleKey, artistKey), song);
    }
  }

  /// 完整路径精确命中（远端条目里带的 senderPath 与本机 path 相同时才可能）。
  SongMetadata? matchByPath(String path) => _byPath[_pathKey(path)];

  /// 按文件名命中，等价于原来的 `findSongsByPathSuffix(fileName)`。
  List<SongMetadata> matchByFileName(String fileName) {
    final key = _fileNameKey(fileName);
    if (key.isEmpty) return const [];
    return _byFileName[key] ?? const [];
  }

  /// 按 标题 + 艺术家（+ 时长 / 专辑）命中。
  ///
  /// 顺序：标题与艺术家都归一化相等 → 艺术家写法拆不开时退回只按标题。
  /// 多个候选时先按时长 ±3s 收，再按专辑收，仍不唯一则标记 `ambiguous`，
  /// 并按与条目时长的差值排序。
  RemoteSongMatch matchByMetadata({
    String? title,
    String? artist,
    String? album,
    int? durationMs,
  }) {
    final titleKey = normalizeSongMatchText(title);
    if (titleKey.isEmpty) return RemoteSongMatch.empty;

    final candidates = <SongMetadata>{};
    for (final artistKey in artistMatchKeys(artist)) {
      final bucket = _byTitleArtist[_titleArtistKey(titleKey, artistKey)];
      if (bucket != null) candidates.addAll(bucket);
    }
    if (candidates.isEmpty) {
      // 只在「一方根本没写艺术家」时放宽到只按标题匹配。
      // 无条件退回按标题会把「Home」这类同名不同艺术家的歌错配到一起，
      // 而漏掉一条歌词只是少一首，错配会把别人的歌词写进本机曲库。
      final incomingArtistEmpty = normalizeSongMatchText(artist).isEmpty;
      for (final song in _byTitle[titleKey] ?? const <SongMetadata>[]) {
        if (incomingArtistEmpty || normalizeSongMatchText(song.artist).isEmpty) {
          candidates.add(song);
        }
      }
    }
    if (candidates.isEmpty) return RemoteSongMatch.empty;

    var matches = candidates
        .where((song) => _durationMatches(song.duration, durationMs))
        .toList(growable: false);

    if (matches.length > 1) {
      final albumKey = normalizeSongMatchText(album);
      if (albumKey.isNotEmpty) {
        final narrowed = matches
            .where((song) => normalizeSongMatchText(song.album) == albumKey)
            .toList(growable: false);
        if (narrowed.isNotEmpty) matches = narrowed;
      }
    }

    if (matches.length > 1 && durationMs != null) {
      final sorted = matches.toList()
        ..sort(
          (a, b) => _durationDelta(a.duration, durationMs).compareTo(
            _durationDelta(b.duration, durationMs),
          ),
        );
      matches = sorted;
    }

    return RemoteSongMatch(matches: matches, ambiguous: matches.length > 1);
  }

  /// 远端 URI 视为「存在」，本地路径走异步探测并在本实例内缓存。
  Future<bool> exists(String path) {
    if (RemoteMediaResolver.isRemoteUri(path)) {
      return Future<bool>.value(true);
    }
    return probe.exists(path);
  }

  static String _pathKey(String path) {
    if (path.isEmpty) return '';
    return path.replaceAll('\\', '/').toLowerCase();
  }

  static String _fileNameKey(String pathOrName) {
    if (pathOrName.isEmpty) return '';
    final normalized = pathOrName.replaceAll('\\', '/');
    final name = normalized.contains('/')
        ? normalized.substring(normalized.lastIndexOf('/') + 1)
        : normalized;
    return name.toLowerCase();
  }

  static String _titleArtistKey(String titleKey, String artistKey) =>
      '$titleKey|$artistKey';

  static void _addToBucket(
    Map<String, List<SongMetadata>> bucket,
    String key,
    SongMetadata song,
  ) {
    (bucket[key] ??= <SongMetadata>[]).add(song);
  }

  static bool _durationMatches(int? songDuration, int? incomingDuration) {
    if (incomingDuration == null || songDuration == null) return true;
    return (songDuration - incomingDuration).abs() <= _durationToleranceMillis;
  }

  static int _durationDelta(int? songDuration, int? incomingDuration) {
    if (incomingDuration == null || songDuration == null) return 0;
    return (songDuration - incomingDuration).abs();
  }
}

/// 跨设备匹配允许的时长偏差。两侧读的是同一个音频文件，差异只该来自编码
/// 误差或标签里的整秒取整，3 秒足够覆盖。
const int _durationToleranceMillis = 3000;
