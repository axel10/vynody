import 'dart:convert';

import 'package:vynody/models/lyric_line.dart';

enum LyricsCacheSource {
  none,
  aiGenerate,
  aiTimeline,
  ai,
  manualAdjust,
  lrclib,
  embedded,
  external;

  static LyricsCacheSource fromDbValue(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'get':
      case 'search':
        return LyricsCacheSource.lrclib;
      case 'none':
        return LyricsCacheSource.none;
      case 'gemini_generate':
      case 'ai_generate':
        return LyricsCacheSource.aiGenerate;
      case 'gemini_timeline':
      case 'ai_timeline':
        return LyricsCacheSource.aiTimeline;
      case 'gemini':
      case 'ai':
        return LyricsCacheSource.ai;
      case 'manual_adjust':
        return LyricsCacheSource.manualAdjust;
      case 'lrclib':
        return LyricsCacheSource.lrclib;
      case 'embedded':
        return LyricsCacheSource.embedded;
      case 'external':
        return LyricsCacheSource.external;
      default:
        return LyricsCacheSource.lrclib;
    }
  }

  static LyricsCacheSource fromMusicLyricSource(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'gemini':
      case 'ai':
        return LyricsCacheSource.ai;
      case 'lrclib':
      case 'get':
      case 'search':
        return LyricsCacheSource.lrclib;
      case 'manual_adjust':
        return LyricsCacheSource.manualAdjust;
      case 'none':
        return LyricsCacheSource.none;
      case 'gemini_generate':
      case 'ai_generate':
        return LyricsCacheSource.aiGenerate;
      case 'gemini_timeline':
      case 'ai_timeline':
        return LyricsCacheSource.aiTimeline;
      case 'embedded':
        return LyricsCacheSource.embedded;
      case 'external':
        return LyricsCacheSource.external;
      default:
        return normalized.isEmpty
            ? LyricsCacheSource.manualAdjust
            : LyricsCacheSource.lrclib;
    }
  }

  String get dbValue {
    return switch (this) {
      LyricsCacheSource.none => 'none',
      LyricsCacheSource.aiGenerate => 'ai_generate',
      LyricsCacheSource.aiTimeline => 'ai_timeline',
      LyricsCacheSource.ai => 'ai',
      LyricsCacheSource.manualAdjust => 'manual_adjust',
      LyricsCacheSource.lrclib => 'lrclib',
      LyricsCacheSource.embedded => 'embedded',
      LyricsCacheSource.external => 'external',
    };
  }

  String get musicLyricSource {
    return switch (this) {
      LyricsCacheSource.none => 'none',
      LyricsCacheSource.aiGenerate => 'ai',
      LyricsCacheSource.aiTimeline => 'ai',
      LyricsCacheSource.ai => 'ai',
      LyricsCacheSource.manualAdjust => 'manual_adjust',
      LyricsCacheSource.lrclib => 'lrclib',
      LyricsCacheSource.embedded => 'embedded',
      LyricsCacheSource.external => 'external',
    };
  }

  bool get isAiSource {
    return this == LyricsCacheSource.aiGenerate ||
        this == LyricsCacheSource.aiTimeline ||
        this == LyricsCacheSource.ai;
  }

  @Deprecated('Use isAiSource')
  bool get isGeminiSource => isAiSource;
}

class LyricsCacheRecord {
  final int? id;
  final String cacheKey;
  final LyricsCacheSource source;
  final String languageCode;
  final bool isSynced;
  final String? syncedLyrics;
  final List<LyricLine> syncedLines;
  final int timelineOffsetMillis;
  final int updatedAtMillis;

  const LyricsCacheRecord({
    this.id,
    required this.cacheKey,
    required this.source,
    this.languageCode = '',
    required this.isSynced,
    this.syncedLyrics,
    required this.syncedLines,
    required this.timelineOffsetMillis,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'cacheKey': cacheKey,
      'source': source.dbValue,
      'languageCode': languageCode,
      'isSynced': isSynced ? 1 : 0,
      'syncedLyrics': syncedLyrics,
      'syncedLinesJson': jsonEncode(
        syncedLines.map((line) => line.toJson()).toList(growable: false),
      ),
      'timelineOffsetMillis': timelineOffsetMillis,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory LyricsCacheRecord.fromMap(Map<String, dynamic> map) {
    final decodedLines = _decodeSyncedLines(map['syncedLinesJson']);

    return LyricsCacheRecord(
      id: map['id'] as int?,
      cacheKey: map['cacheKey'] as String? ?? '',
      source: LyricsCacheSource.fromDbValue(map['source']),
      languageCode: map['languageCode'] as String? ?? '',
      isSynced: (map['isSynced'] as int? ?? 0) == 1,
      syncedLyrics: map['syncedLyrics'] as String?,
      syncedLines: decodedLines,
      timelineOffsetMillis: (map['timelineOffsetMillis'] as int?) ?? 0,
      updatedAtMillis:
          (map['updatedAtMillis'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class LyricsTranslationCacheRecord {
  final int? id;
  final String cacheKey;
  final String languageCode;
  final String translatedText;
  final List<String> translatedLines;
  final String? provider;
  final int updatedAtMillis;

  const LyricsTranslationCacheRecord({
    this.id,
    required this.cacheKey,
    required this.languageCode,
    required this.translatedText,
    required this.translatedLines,
    this.provider,
    required this.updatedAtMillis,
  });

  Map<String, dynamic> toMap() {
    return {
      'cacheKey': cacheKey,
      'languageCode': languageCode,
      'translatedText': translatedText,
      'translatedLinesJson': jsonEncode(translatedLines),
      'provider': provider,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  factory LyricsTranslationCacheRecord.fromMap(Map<String, dynamic> map) {
    final rawLines = map['translatedLinesJson'] as String?;
    final decodedLines = rawLines == null || rawLines.isEmpty
        ? <String>[]
        : (jsonDecode(rawLines) as List)
              .map((item) => item?.toString() ?? '')
              .toList(growable: false);

    return LyricsTranslationCacheRecord(
      id: map['id'] as int?,
      cacheKey: map['cacheKey'] as String? ?? '',
      languageCode: map['languageCode'] as String? ?? 'zh',
      translatedText: map['translatedText'] as String? ?? '',
      translatedLines: decodedLines,
      provider: map['provider'] as String?,
      updatedAtMillis:
          (map['updatedAtMillis'] as int?) ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

List<LyricLine> _decodeSyncedLines(Object? rawValue) {
  if (rawValue == null) return const <LyricLine>[];

  if (rawValue is String && rawValue.trim().isEmpty) {
    return const <LyricLine>[];
  }

  final decodedValue = rawValue is String ? jsonDecode(rawValue) : rawValue;
  if (decodedValue is! List) return const <LyricLine>[];

  return decodedValue
      .whereType<Map>()
      .map((item) => LyricLine.fromJson(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}
