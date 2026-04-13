// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lyric_line.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LyricLine _$LyricLineFromJson(Map<String, dynamic> json) => _LyricLine(
  timestamp: durationFromMilliseconds(json['timestampMs']),
  text: json['text'] as String? ?? '',
  isTimed: json['isTimed'] as bool? ?? true,
);

Map<String, dynamic> _$LyricLineToJson(_LyricLine instance) =>
    <String, dynamic>{
      'timestampMs': durationToMilliseconds(instance.timestamp),
      'text': instance.text,
      'isTimed': instance.isTimed,
    };
