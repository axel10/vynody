import 'package:vynody/models/music_file.dart';

/// 一条待上报（或已上报）的曲目记录。
///
/// 字段在入队时就被快照下来，之后不再回查数据库 —— 曲目可能被删除、
/// 重命名或重新打标签，而 Last.fm 记录的是「当时听的是什么」。
class LastFmScrobbleEntry {
  const LastFmScrobbleEntry({
    required this.artist,
    required this.track,
    required this.playedAt,
    this.album,
    this.albumArtist,
    this.durationSeconds,
    this.trackNumber,
    this.mbid,
  });

  final String artist;
  final String track;
  final DateTime playedAt;
  final String? album;
  final String? albumArtist;
  final int? durationSeconds;
  final int? trackNumber;
  final String? mbid;

  /// 从本地曲目构造一条上报记录。返回 null 表示该曲目缺少必要字段，
  /// 应当直接跳过而不是上报一条垃圾记录。
  ///
  /// 字段策略（刻意不做清洗）：artist 原样使用，仅当为空时回退到
  /// albumArtist；title 为空则跳过。Last.fm 自身也存在大量 remaster /
  /// feat. 版本条目，粗暴裁掉后缀反而会降低匹配率。
  static LastFmScrobbleEntry? fromSong(
    MusicFile song, {
    required DateTime playedAt,
    int? durationSeconds,
  }) {
    final track = song.title?.trim() ?? '';
    if (track.isEmpty) return null;

    final artist = _firstNonEmpty([song.artist, song.albumArtist]);
    if (artist == null) return null;

    final album = song.album?.trim();
    final albumArtist = song.albumArtist?.trim();
    final resolvedDuration = durationSeconds ?? _secondsFromMillis(song.durationMillis);

    return LastFmScrobbleEntry(
      artist: artist,
      track: track,
      playedAt: playedAt,
      album: (album == null || album.isEmpty) ? null : album,
      albumArtist: (albumArtist == null || albumArtist.isEmpty) ? null : albumArtist,
      durationSeconds: (resolvedDuration == null || resolvedDuration <= 0)
          ? null
          : resolvedDuration,
      trackNumber: song.trackNumber,
    );
  }

  /// `track.updateNowPlaying` 的参数（不带数组下标）。
  Map<String, String> toNowPlayingParams() {
    return <String, String>{
      'artist': artist,
      'track': track,
      'album': ?album,
      'albumArtist': ?albumArtist,
      if (durationSeconds != null) 'duration': '$durationSeconds',
      if (trackNumber != null) 'trackNumber': '$trackNumber',
      'mbid': ?mbid,
    };
  }

  /// `track.scrobble` 的参数（Last.fm 用 `artist[0]` 这类数组下标表达批量）。
  Map<String, String> toScrobbleParams(int index) {
    return <String, String>{
      'artist[$index]': artist,
      'track[$index]': track,
      'timestamp[$index]': '${playedAt.millisecondsSinceEpoch ~/ 1000}',
      'album[$index]': ?album,
      'albumArtist[$index]': ?albumArtist,
      if (durationSeconds != null) 'duration[$index]': '$durationSeconds',
      if (trackNumber != null) 'trackNumber[$index]': '$trackNumber',
      'mbid[$index]': ?mbid,
    };
  }

  LastFmScrobbleEntry copyWith({DateTime? playedAt}) {
    return LastFmScrobbleEntry(
      artist: artist,
      track: track,
      playedAt: playedAt ?? this.playedAt,
      album: album,
      albumArtist: albumArtist,
      durationSeconds: durationSeconds,
      trackNumber: trackNumber,
      mbid: mbid,
    );
  }

  static int? _secondsFromMillis(int? millis) {
    if (millis == null || millis <= 0) return null;
    return millis ~/ 1000;
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}
