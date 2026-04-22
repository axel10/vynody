import 'music_file.dart';

class ArtistSummary {
  const ArtistSummary({
    required this.queryKey,
    required this.name,
    required this.songs,
    required this.representativeSong,
    required this.songCount,
    this.artistId,
    this.sortName,
    this.disambiguation,
    this.country,
    this.areaName,
    this.beginDate,
    this.endDate,
    this.imageFileTitle,
    this.imageUrl,
    this.thumbnailUrl,
    this.tags = const <String>[],
    this.noData = false,
  });

  final String queryKey;
  final String name;
  final List<MusicFile> songs;
  final MusicFile representativeSong;
  final int songCount;
  final String? artistId;
  final String? sortName;
  final String? disambiguation;
  final String? country;
  final String? areaName;
  final String? beginDate;
  final String? endDate;
  final String? imageFileTitle;
  final String? imageUrl;
  final String? thumbnailUrl;
  final List<String> tags;
  final bool noData;

  bool get isUnknownArtist => queryKey == _normalizeArtistKey('Unknown Artist');
  bool get hasImage => (imageUrl?.trim().isNotEmpty ?? false);

  ArtistSummary copyWith({
    String? queryKey,
    String? name,
    List<MusicFile>? songs,
    MusicFile? representativeSong,
    int? songCount,
    String? artistId,
    String? sortName,
    String? disambiguation,
    String? country,
    String? areaName,
    String? beginDate,
    String? endDate,
    String? imageFileTitle,
    String? imageUrl,
    String? thumbnailUrl,
    List<String>? tags,
    bool? noData,
  }) {
    return ArtistSummary(
      queryKey: queryKey ?? this.queryKey,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      representativeSong: representativeSong ?? this.representativeSong,
      songCount: songCount ?? this.songCount,
      artistId: artistId ?? this.artistId,
      sortName: sortName ?? this.sortName,
      disambiguation: disambiguation ?? this.disambiguation,
      country: country ?? this.country,
      areaName: areaName ?? this.areaName,
      beginDate: beginDate ?? this.beginDate,
      endDate: endDate ?? this.endDate,
      imageFileTitle: imageFileTitle ?? this.imageFileTitle,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      tags: tags ?? this.tags,
      noData: noData ?? this.noData,
    );
  }
}

String normalizeArtistKey(String value) => _normalizeArtistKey(value);

String _normalizeArtistKey(String value) {
  return value.trim().toLowerCase();
}
