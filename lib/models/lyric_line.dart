import 'package:freezed_annotation/freezed_annotation.dart';

import 'lyrics_json_converters.dart';

part 'lyric_line.freezed.dart';
part 'lyric_line.g.dart';

@freezed
abstract class LyricLine with _$LyricLine {
  const LyricLine._();

  const factory LyricLine({
    @JsonKey(
      name: 'timestampMs',
      fromJson: durationFromMilliseconds,
      toJson: durationToMilliseconds,
    )
    required Duration timestamp,
    @Default('') String text,
    @Default(true) bool isTimed,
    @Default(null) List<LyricWord>? words,
  }) = _LyricLine;

  factory LyricLine.fromJson(Map<String, dynamic> json) =>
      _$LyricLineFromJson(json);
}

@freezed
abstract class LyricWord with _$LyricWord {
  const factory LyricWord({
    @JsonKey(
      name: 'timestampMs',
      fromJson: durationFromMilliseconds,
      toJson: durationToMilliseconds,
    )
    required Duration timestamp,
    required int durationMs,
    required String text,
  }) = _LyricWord;

  factory LyricWord.fromJson(Map<String, dynamic> json) =>
      _$LyricWordFromJson(json);
}
