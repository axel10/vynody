class LyricsTimelineActionType {
  static const String manualEdit = 'manual_edit';
  static const String timelineAdjust = 'timeline_adjust';
  static const String onlineMatch = 'online_match';
  static const String importFile = 'import_file';
  static const String aiGenerate = 'ai_generate';
  static const String initial = 'initial';
  static const String restore = 'restore';

  const LyricsTimelineActionType._();
}

class LyricsTimelineEntry {
  final int? id;
  final String cacheKey;
  final String actionType;
  final String description;
  final String lyrics;
  final String? translation;
  final int timelineOffsetMillis;
  final int createdAtMillis;

  const LyricsTimelineEntry({
    this.id,
    required this.cacheKey,
    required this.actionType,
    required this.description,
    required this.lyrics,
    this.translation,
    this.timelineOffsetMillis = 0,
    required this.createdAtMillis,
  });

  DateTime get createdAt =>
      DateTime.fromMillisecondsSinceEpoch(createdAtMillis);

  bool hasSameContent(LyricsTimelineEntry other) {
    return lyrics.trim() == other.lyrics.trim() &&
        (translation ?? '').trim() == (other.translation ?? '').trim() &&
        timelineOffsetMillis == other.timelineOffsetMillis;
  }
}
