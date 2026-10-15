import 'music_file.dart';

class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.title,
    required this.artist,
    required this.songs,
    required this.representativeSong,
    required this.totalDurationMillis,
    this.genres,
    this.minYear,
    this.maxYear,
  });

  final String id;
  final String title;
  final String artist;
  final List<MusicFile> songs;
  final MusicFile representativeSong;
  final int totalDurationMillis;
  final List<String>? genres;
  final int? minYear;
  final int? maxYear;

  int get trackCount => songs.length;
  bool get isUnknownAlbum => title.trim().toLowerCase() == 'unknown album';

  int get latestTimestampMillis => songs.fold<int>(
    0,
    (latest, song) =>
        song.lastModifiedTime != null && song.lastModifiedTime! > latest
        ? song.lastModifiedTime!
        : latest,
  );

  /// 多个流派按曲目数量降序排列
  List<String> get sortedGenres {
    if (genres != null && genres!.isNotEmpty) {
      return genres!;
    }
    final freq = <String, int>{};
    for (final song in songs) {
      final songGenres = song.genres;
      if (songGenres != null) {
        for (final g in songGenres) {
          final trimmed = g.trim();
          if (trimmed.isNotEmpty) {
            freq[trimmed] = (freq[trimmed] ?? 0) + 1;
          }
        }
      }
    }
    if (freq.isEmpty) return const [];
    final list = freq.keys.toList()
      ..sort((a, b) {
        final countCompare = freq[b]!.compareTo(freq[a]!);
        if (countCompare != 0) return countCompare;
        return a.compareTo(b);
      });
    return list;
  }

  /// 年份或年份区间展示文本（单一年份展示单个，如 2021；多个不同年份展示区间，如 1998 - 2004）
  String? get yearRangeText {
    int? min = minYear;
    int? max = maxYear;
    if (min == null || max == null) {
      final years = songs
          .map((s) => s.year)
          .whereType<int>()
          .where((y) => y > 0)
          .toSet();
      if (years.isNotEmpty) {
        min = years.reduce((a, b) => a < b ? a : b);
        max = years.reduce((a, b) => a > b ? a : b);
      }
    }
    if (min == null || max == null || min <= 0 || max <= 0) return null;
    if (min == max) return '$min';
    return '$min - $max';
  }

  /// 格式化流派文本（取前 3 个主要流派，以 / 拼接，如：流行 / 摇滚）
  String? get genresText {
    final list = sortedGenres;
    if (list.isEmpty) return null;
    return list.take(3).join(' / ');
  }
}
