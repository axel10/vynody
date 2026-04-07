import 'package:flutter/foundation.dart';

class MusicLyricTranslation {
  final String languageCode;
  final String translatedText;
  final List<String> translatedLines;
  final String? provider;
  final DateTime? updatedAt;

  const MusicLyricTranslation({
    required this.languageCode,
    required this.translatedText,
    required this.translatedLines,
    this.provider,
    this.updatedAt,
  });

  bool get hasContent =>
      translatedText.trim().isNotEmpty ||
      translatedLines.any((line) => line.trim().isNotEmpty);

  String translatedLineAt(int index) {
    if (index < 0) return '';
    if (index >= translatedLines.length) return '';
    return translatedLines[index].trim();
  }

  MusicLyricTranslation copyWith({
    String? languageCode,
    String? translatedText,
    List<String>? translatedLines,
    String? provider,
    DateTime? updatedAt,
  }) {
    return MusicLyricTranslation(
      languageCode: languageCode ?? this.languageCode,
      translatedText: translatedText ?? this.translatedText,
      translatedLines: translatedLines ?? this.translatedLines,
      provider: provider ?? this.provider,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'languageCode': languageCode,
      'translatedText': translatedText,
      'translatedLines': translatedLines,
      'provider': provider,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory MusicLyricTranslation.fromJson(Map<String, dynamic> json) {
    final rawLines = json['translatedLines'];
    return MusicLyricTranslation(
      languageCode: json['languageCode'] as String? ?? 'zh',
      translatedText: json['translatedText'] as String? ?? '',
      translatedLines: rawLines is List
          ? rawLines.map((item) => item?.toString() ?? '').toList()
          : const [],
      provider: json['provider'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MusicLyricTranslation &&
            languageCode == other.languageCode &&
            translatedText == other.translatedText &&
            listEquals(translatedLines, other.translatedLines) &&
            provider == other.provider &&
            updatedAt == other.updatedAt;
  }

  @override
  int get hashCode => Object.hash(
    languageCode,
    translatedText,
    Object.hashAll(translatedLines),
    provider,
    updatedAt,
  );
}
