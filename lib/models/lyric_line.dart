class LyricLine {
  final Duration timestamp;
  final String text;
  final String translation;
  final bool isTimed;

  const LyricLine({
    required this.timestamp,
    required this.text,
    this.translation = '',
    this.isTimed = true,
  });

  LyricLine copyWith({
    Duration? timestamp,
    String? text,
    String? translation,
    bool? isTimed,
  }) {
    return LyricLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      translation: translation ?? this.translation,
      isTimed: isTimed ?? this.isTimed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestampMs': timestamp.inMilliseconds,
      'text': text,
      'translation': translation,
      'isTimed': isTimed,
    };
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestamp: Duration(milliseconds: (json['timestampMs'] as num).round()),
      text: json['text'] as String? ?? '',
      translation: json['translation'] as String? ?? '',
      isTimed: json['isTimed'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LyricLine &&
            timestamp == other.timestamp &&
            text == other.text &&
            translation == other.translation &&
            isTimed == other.isTimed;
  }

  @override
  int get hashCode => Object.hash(timestamp, text, translation, isTimed);
}
