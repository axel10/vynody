// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'music_lyric_translation.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MusicLyricTranslation _$MusicLyricTranslationFromJson(
  Map<String, dynamic> json,
) => _MusicLyricTranslation(
  languageCode: json['languageCode'] as String? ?? 'zh',
  translatedText: json['translatedText'] as String? ?? '',
  translatedLines: json['translatedLines'] == null
      ? const <String>[]
      : stringListFromJson(json['translatedLines']),
  provider: json['provider'] as String?,
  updatedAt: json['updatedAt'] == null
      ? null
      : DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$MusicLyricTranslationToJson(
  _MusicLyricTranslation instance,
) => <String, dynamic>{
  'languageCode': instance.languageCode,
  'translatedText': instance.translatedText,
  'translatedLines': stringListToJson(instance.translatedLines),
  'provider': instance.provider,
  'updatedAt': instance.updatedAt?.toIso8601String(),
};
