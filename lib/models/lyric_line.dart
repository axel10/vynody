
class LyricLine {
  final Duration timestamp;
  final String text;

  const LyricLine({required this.timestamp, required this.text});

  Map<String, dynamic> toJson() {
    return {'timestampMs': timestamp.inMilliseconds, 'text': text};
  }

  factory LyricLine.fromJson(Map<String, dynamic> json) {
    return LyricLine(
      timestamp: Duration(milliseconds: (json['timestampMs'] as num).round()),
      text: json['text'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LyricLine &&
            timestamp == other.timestamp &&
            text == other.text;
  }

  @override
  int get hashCode => Object.hash(timestamp, text);
}
