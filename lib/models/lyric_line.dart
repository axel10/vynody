class LyricLine {
  final Duration timestamp;
  final String text;
  final bool isTimed;

  const LyricLine({
    required this.timestamp,
    required this.text,
    this.isTimed = true,
  });

  LyricLine copyWith({Duration? timestamp, String? text, bool? isTimed}) {
    return LyricLine(
      timestamp: timestamp ?? this.timestamp,
      text: text ?? this.text,
      isTimed: isTimed ?? this.isTimed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'timestampMs': timestamp.inMilliseconds,
      'text': text,
      'isTimed': isTimed,
    };
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestamp: Duration(milliseconds: (json['timestampMs'] as num).round()),
      text: json['text'] as String? ?? '',
      isTimed: json['isTimed'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LyricLine &&
            timestamp == other.timestamp &&
            text == other.text &&
            isTimed == other.isTimed;
  }

  @override
  int get hashCode => Object.hash(timestamp, text, isTimed);
}
