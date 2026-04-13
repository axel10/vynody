// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'music_lyric.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MusicLyric _$MusicLyricFromJson(Map<String, dynamic> json) => _MusicLyric(
  id: json['id'] as String? ?? '',
  syncedLines:
      (json['syncedLines'] as List<dynamic>?)
          ?.map((e) => LyricLine.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const <LyricLine>[],
  plainText: json['plainText'] as String? ?? '',
  translations:
      (json['translations'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(
          k,
          MusicLyricTranslation.fromJson(e as Map<String, dynamic>),
        ),
      ) ??
      const <String, MusicLyricTranslation>{},
  source: json['source'] as String? ?? '',
  timelineOffset: json['timelineOffset'] == null
      ? Duration.zero
      : durationFromMilliseconds(json['timelineOffset']),
);

Map<String, dynamic> _$MusicLyricToJson(_MusicLyric instance) =>
    <String, dynamic>{
      'id': instance.id,
      'syncedLines': instance.syncedLines,
      'plainText': instance.plainText,
      'translations': instance.translations,
      'source': instance.source,
      'timelineOffset': durationToMilliseconds(instance.timelineOffset),
    };
