enum PlaybackSourceType {
  playlist,
  folder,
  album,
  artist,
}

class PlaybackSource {
  final PlaybackSourceType type;
  final String id;
  final String? name;

  PlaybackSource({
    required this.type,
    required this.id,
    this.name,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'id': id,
      'name': name,
    };
  }

  factory PlaybackSource.fromJson(Map<String, dynamic> json) {
    return PlaybackSource(
      type: PlaybackSourceType.values.firstWhere((e) => e.name == json['type']),
      id: json['id'] as String,
      name: json['name'] as String?,
    );
  }
}
