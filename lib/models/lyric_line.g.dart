// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyric_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LyricLine _$LyricLineFromJson(Map<String, dynamic> json) => _LyricLine(
  timestamp: durationFromMilliseconds(json['timestampMs']),
  text: json['text'] as String? ?? '',
  isTimed: json['isTimed'] as bool? ?? true,
  words:
      (json['words'] as List<dynamic>?)
          ?.map((e) => LyricWord.fromJson(e as Map<String, dynamic>))
          .toList() ??
      null,
);

Map<String, dynamic> _$LyricLineToJson(_LyricLine instance) =>
    <String, dynamic>{
      'timestampMs': durationToMilliseconds(instance.timestamp),
      'text': instance.text,
      'isTimed': instance.isTimed,
      'words': instance.words,
    };

_LyricWord _$LyricWordFromJson(Map<String, dynamic> json) => _LyricWord(
  timestamp: durationFromMilliseconds(json['timestampMs']),
  durationMs: (json['durationMs'] as num).toInt(),
  text: json['text'] as String,
);

Map<String, dynamic> _$LyricWordToJson(_LyricWord instance) =>
    <String, dynamic>{
      'timestampMs': durationToMilliseconds(instance.timestamp),
      'durationMs': instance.durationMs,
      'text': instance.text,
    };
