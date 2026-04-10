// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lyrics_service.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LyricTrack implements DiagnosticableTreeMixin {

 int? get id; String? get lyricsId; String? get name; String? get trackName; String? get artistName; String? get albumName; double? get duration; bool get instrumental; String? get plainLyrics; String? get syncedLyrics;
/// Create a copy of LyricTrack
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LyricTrackCopyWith<LyricTrack> get copyWith => _$LyricTrackCopyWithImpl<LyricTrack>(this as LyricTrack, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LyricTrack'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('lyricsId', lyricsId))..add(DiagnosticsProperty('name', name))..add(DiagnosticsProperty('trackName', trackName))..add(DiagnosticsProperty('artistName', artistName))..add(DiagnosticsProperty('albumName', albumName))..add(DiagnosticsProperty('duration', duration))..add(DiagnosticsProperty('instrumental', instrumental))..add(DiagnosticsProperty('plainLyrics', plainLyrics))..add(DiagnosticsProperty('syncedLyrics', syncedLyrics));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LyricTrack&&(identical(other.id, id) || other.id == id)&&(identical(other.lyricsId, lyricsId) || other.lyricsId == lyricsId)&&(identical(other.name, name) || other.name == name)&&(identical(other.trackName, trackName) || other.trackName == trackName)&&(identical(other.artistName, artistName) || other.artistName == artistName)&&(identical(other.albumName, albumName) || other.albumName == albumName)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.instrumental, instrumental) || other.instrumental == instrumental)&&(identical(other.plainLyrics, plainLyrics) || other.plainLyrics == plainLyrics)&&(identical(other.syncedLyrics, syncedLyrics) || other.syncedLyrics == syncedLyrics));
}


@override
int get hashCode => Object.hash(runtimeType,id,lyricsId,name,trackName,artistName,albumName,duration,instrumental,plainLyrics,syncedLyrics);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LyricTrack(id: $id, lyricsId: $lyricsId, name: $name, trackName: $trackName, artistName: $artistName, albumName: $albumName, duration: $duration, instrumental: $instrumental, plainLyrics: $plainLyrics, syncedLyrics: $syncedLyrics)';
}


}

/// @nodoc
abstract mixin class $LyricTrackCopyWith<$Res>  {
  factory $LyricTrackCopyWith(LyricTrack value, $Res Function(LyricTrack) _then) = _$LyricTrackCopyWithImpl;
@useResult
$Res call({
 int? id, String? lyricsId, String? name, String? trackName, String? artistName, String? albumName, double? duration, bool instrumental, String? plainLyrics, String? syncedLyrics
});




}
/// @nodoc
class _$LyricTrackCopyWithImpl<$Res>
    implements $LyricTrackCopyWith<$Res> {
  _$LyricTrackCopyWithImpl(this._self, this._then);

  final LyricTrack _self;
  final $Res Function(LyricTrack) _then;

/// Create a copy of LyricTrack
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? lyricsId = freezed,Object? name = freezed,Object? trackName = freezed,Object? artistName = freezed,Object? albumName = freezed,Object? duration = freezed,Object? instrumental = null,Object? plainLyrics = freezed,Object? syncedLyrics = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,lyricsId: freezed == lyricsId ? _self.lyricsId : lyricsId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,trackName: freezed == trackName ? _self.trackName : trackName // ignore: cast_nullable_to_non_nullable
as String?,artistName: freezed == artistName ? _self.artistName : artistName // ignore: cast_nullable_to_non_nullable
as String?,albumName: freezed == albumName ? _self.albumName : albumName // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double?,instrumental: null == instrumental ? _self.instrumental : instrumental // ignore: cast_nullable_to_non_nullable
as bool,plainLyrics: freezed == plainLyrics ? _self.plainLyrics : plainLyrics // ignore: cast_nullable_to_non_nullable
as String?,syncedLyrics: freezed == syncedLyrics ? _self.syncedLyrics : syncedLyrics // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [LyricTrack].
extension LyricTrackPatterns on LyricTrack {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LyricTrack value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LyricTrack() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LyricTrack value)  $default,){
final _that = this;
switch (_that) {
case _LyricTrack():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LyricTrack value)?  $default,){
final _that = this;
switch (_that) {
case _LyricTrack() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  String? lyricsId,  String? name,  String? trackName,  String? artistName,  String? albumName,  double? duration,  bool instrumental,  String? plainLyrics,  String? syncedLyrics)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LyricTrack() when $default != null:
return $default(_that.id,_that.lyricsId,_that.name,_that.trackName,_that.artistName,_that.albumName,_that.duration,_that.instrumental,_that.plainLyrics,_that.syncedLyrics);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  String? lyricsId,  String? name,  String? trackName,  String? artistName,  String? albumName,  double? duration,  bool instrumental,  String? plainLyrics,  String? syncedLyrics)  $default,) {final _that = this;
switch (_that) {
case _LyricTrack():
return $default(_that.id,_that.lyricsId,_that.name,_that.trackName,_that.artistName,_that.albumName,_that.duration,_that.instrumental,_that.plainLyrics,_that.syncedLyrics);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  String? lyricsId,  String? name,  String? trackName,  String? artistName,  String? albumName,  double? duration,  bool instrumental,  String? plainLyrics,  String? syncedLyrics)?  $default,) {final _that = this;
switch (_that) {
case _LyricTrack() when $default != null:
return $default(_that.id,_that.lyricsId,_that.name,_that.trackName,_that.artistName,_that.albumName,_that.duration,_that.instrumental,_that.plainLyrics,_that.syncedLyrics);case _:
  return null;

}
}

}

/// @nodoc


class _LyricTrack extends LyricTrack with DiagnosticableTreeMixin {
  const _LyricTrack({this.id, this.lyricsId, this.name, this.trackName, this.artistName, this.albumName, this.duration, this.instrumental = false, this.plainLyrics, this.syncedLyrics}): super._();
  

@override final  int? id;
@override final  String? lyricsId;
@override final  String? name;
@override final  String? trackName;
@override final  String? artistName;
@override final  String? albumName;
@override final  double? duration;
@override@JsonKey() final  bool instrumental;
@override final  String? plainLyrics;
@override final  String? syncedLyrics;

/// Create a copy of LyricTrack
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LyricTrackCopyWith<_LyricTrack> get copyWith => __$LyricTrackCopyWithImpl<_LyricTrack>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LyricTrack'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('lyricsId', lyricsId))..add(DiagnosticsProperty('name', name))..add(DiagnosticsProperty('trackName', trackName))..add(DiagnosticsProperty('artistName', artistName))..add(DiagnosticsProperty('albumName', albumName))..add(DiagnosticsProperty('duration', duration))..add(DiagnosticsProperty('instrumental', instrumental))..add(DiagnosticsProperty('plainLyrics', plainLyrics))..add(DiagnosticsProperty('syncedLyrics', syncedLyrics));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LyricTrack&&(identical(other.id, id) || other.id == id)&&(identical(other.lyricsId, lyricsId) || other.lyricsId == lyricsId)&&(identical(other.name, name) || other.name == name)&&(identical(other.trackName, trackName) || other.trackName == trackName)&&(identical(other.artistName, artistName) || other.artistName == artistName)&&(identical(other.albumName, albumName) || other.albumName == albumName)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.instrumental, instrumental) || other.instrumental == instrumental)&&(identical(other.plainLyrics, plainLyrics) || other.plainLyrics == plainLyrics)&&(identical(other.syncedLyrics, syncedLyrics) || other.syncedLyrics == syncedLyrics));
}


@override
int get hashCode => Object.hash(runtimeType,id,lyricsId,name,trackName,artistName,albumName,duration,instrumental,plainLyrics,syncedLyrics);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LyricTrack(id: $id, lyricsId: $lyricsId, name: $name, trackName: $trackName, artistName: $artistName, albumName: $albumName, duration: $duration, instrumental: $instrumental, plainLyrics: $plainLyrics, syncedLyrics: $syncedLyrics)';
}


}

/// @nodoc
abstract mixin class _$LyricTrackCopyWith<$Res> implements $LyricTrackCopyWith<$Res> {
  factory _$LyricTrackCopyWith(_LyricTrack value, $Res Function(_LyricTrack) _then) = __$LyricTrackCopyWithImpl;
@override @useResult
$Res call({
 int? id, String? lyricsId, String? name, String? trackName, String? artistName, String? albumName, double? duration, bool instrumental, String? plainLyrics, String? syncedLyrics
});




}
/// @nodoc
class __$LyricTrackCopyWithImpl<$Res>
    implements _$LyricTrackCopyWith<$Res> {
  __$LyricTrackCopyWithImpl(this._self, this._then);

  final _LyricTrack _self;
  final $Res Function(_LyricTrack) _then;

/// Create a copy of LyricTrack
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? lyricsId = freezed,Object? name = freezed,Object? trackName = freezed,Object? artistName = freezed,Object? albumName = freezed,Object? duration = freezed,Object? instrumental = null,Object? plainLyrics = freezed,Object? syncedLyrics = freezed,}) {
  return _then(_LyricTrack(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,lyricsId: freezed == lyricsId ? _self.lyricsId : lyricsId // ignore: cast_nullable_to_non_nullable
as String?,name: freezed == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String?,trackName: freezed == trackName ? _self.trackName : trackName // ignore: cast_nullable_to_non_nullable
as String?,artistName: freezed == artistName ? _self.artistName : artistName // ignore: cast_nullable_to_non_nullable
as String?,albumName: freezed == albumName ? _self.albumName : albumName // ignore: cast_nullable_to_non_nullable
as String?,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as double?,instrumental: null == instrumental ? _self.instrumental : instrumental // ignore: cast_nullable_to_non_nullable
as bool,plainLyrics: freezed == plainLyrics ? _self.plainLyrics : plainLyrics // ignore: cast_nullable_to_non_nullable
as String?,syncedLyrics: freezed == syncedLyrics ? _self.syncedLyrics : syncedLyrics // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$LyricSelectionResult implements DiagnosticableTreeMixin {

 LyricTrack get track; bool get fromGetApi; String get source; double get score; LyricScoreBreakdown get breakdown; int get durationDiffSeconds; List<LyricLine> get syncedLines; String get lyricsText; Duration get timelineOffset;
/// Create a copy of LyricSelectionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LyricSelectionResultCopyWith<LyricSelectionResult> get copyWith => _$LyricSelectionResultCopyWithImpl<LyricSelectionResult>(this as LyricSelectionResult, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LyricSelectionResult'))
    ..add(DiagnosticsProperty('track', track))..add(DiagnosticsProperty('fromGetApi', fromGetApi))..add(DiagnosticsProperty('source', source))..add(DiagnosticsProperty('score', score))..add(DiagnosticsProperty('breakdown', breakdown))..add(DiagnosticsProperty('durationDiffSeconds', durationDiffSeconds))..add(DiagnosticsProperty('syncedLines', syncedLines))..add(DiagnosticsProperty('lyricsText', lyricsText))..add(DiagnosticsProperty('timelineOffset', timelineOffset));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LyricSelectionResult&&(identical(other.track, track) || other.track == track)&&(identical(other.fromGetApi, fromGetApi) || other.fromGetApi == fromGetApi)&&(identical(other.source, source) || other.source == source)&&(identical(other.score, score) || other.score == score)&&(identical(other.breakdown, breakdown) || other.breakdown == breakdown)&&(identical(other.durationDiffSeconds, durationDiffSeconds) || other.durationDiffSeconds == durationDiffSeconds)&&const DeepCollectionEquality().equals(other.syncedLines, syncedLines)&&(identical(other.lyricsText, lyricsText) || other.lyricsText == lyricsText)&&(identical(other.timelineOffset, timelineOffset) || other.timelineOffset == timelineOffset));
}


@override
int get hashCode => Object.hash(runtimeType,track,fromGetApi,source,score,breakdown,durationDiffSeconds,const DeepCollectionEquality().hash(syncedLines),lyricsText,timelineOffset);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LyricSelectionResult(track: $track, fromGetApi: $fromGetApi, source: $source, score: $score, breakdown: $breakdown, durationDiffSeconds: $durationDiffSeconds, syncedLines: $syncedLines, lyricsText: $lyricsText, timelineOffset: $timelineOffset)';
}


}

/// @nodoc
abstract mixin class $LyricSelectionResultCopyWith<$Res>  {
  factory $LyricSelectionResultCopyWith(LyricSelectionResult value, $Res Function(LyricSelectionResult) _then) = _$LyricSelectionResultCopyWithImpl;
@useResult
$Res call({
 LyricTrack track, bool fromGetApi, String source, double score, LyricScoreBreakdown breakdown, int durationDiffSeconds, List<LyricLine> syncedLines, String lyricsText, Duration timelineOffset
});


$LyricTrackCopyWith<$Res> get track;

}
/// @nodoc
class _$LyricSelectionResultCopyWithImpl<$Res>
    implements $LyricSelectionResultCopyWith<$Res> {
  _$LyricSelectionResultCopyWithImpl(this._self, this._then);

  final LyricSelectionResult _self;
  final $Res Function(LyricSelectionResult) _then;

/// Create a copy of LyricSelectionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? track = null,Object? fromGetApi = null,Object? source = null,Object? score = null,Object? breakdown = null,Object? durationDiffSeconds = null,Object? syncedLines = null,Object? lyricsText = null,Object? timelineOffset = null,}) {
  return _then(_self.copyWith(
track: null == track ? _self.track : track // ignore: cast_nullable_to_non_nullable
as LyricTrack,fromGetApi: null == fromGetApi ? _self.fromGetApi : fromGetApi // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,breakdown: null == breakdown ? _self.breakdown : breakdown // ignore: cast_nullable_to_non_nullable
as LyricScoreBreakdown,durationDiffSeconds: null == durationDiffSeconds ? _self.durationDiffSeconds : durationDiffSeconds // ignore: cast_nullable_to_non_nullable
as int,syncedLines: null == syncedLines ? _self.syncedLines : syncedLines // ignore: cast_nullable_to_non_nullable
as List<LyricLine>,lyricsText: null == lyricsText ? _self.lyricsText : lyricsText // ignore: cast_nullable_to_non_nullable
as String,timelineOffset: null == timelineOffset ? _self.timelineOffset : timelineOffset // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}
/// Create a copy of LyricSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LyricTrackCopyWith<$Res> get track {
  
  return $LyricTrackCopyWith<$Res>(_self.track, (value) {
    return _then(_self.copyWith(track: value));
  });
}
}


/// Adds pattern-matching-related methods to [LyricSelectionResult].
extension LyricSelectionResultPatterns on LyricSelectionResult {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LyricSelectionResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LyricSelectionResult() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LyricSelectionResult value)  $default,){
final _that = this;
switch (_that) {
case _LyricSelectionResult():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LyricSelectionResult value)?  $default,){
final _that = this;
switch (_that) {
case _LyricSelectionResult() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LyricTrack track,  bool fromGetApi,  String source,  double score,  LyricScoreBreakdown breakdown,  int durationDiffSeconds,  List<LyricLine> syncedLines,  String lyricsText,  Duration timelineOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LyricSelectionResult() when $default != null:
return $default(_that.track,_that.fromGetApi,_that.source,_that.score,_that.breakdown,_that.durationDiffSeconds,_that.syncedLines,_that.lyricsText,_that.timelineOffset);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LyricTrack track,  bool fromGetApi,  String source,  double score,  LyricScoreBreakdown breakdown,  int durationDiffSeconds,  List<LyricLine> syncedLines,  String lyricsText,  Duration timelineOffset)  $default,) {final _that = this;
switch (_that) {
case _LyricSelectionResult():
return $default(_that.track,_that.fromGetApi,_that.source,_that.score,_that.breakdown,_that.durationDiffSeconds,_that.syncedLines,_that.lyricsText,_that.timelineOffset);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LyricTrack track,  bool fromGetApi,  String source,  double score,  LyricScoreBreakdown breakdown,  int durationDiffSeconds,  List<LyricLine> syncedLines,  String lyricsText,  Duration timelineOffset)?  $default,) {final _that = this;
switch (_that) {
case _LyricSelectionResult() when $default != null:
return $default(_that.track,_that.fromGetApi,_that.source,_that.score,_that.breakdown,_that.durationDiffSeconds,_that.syncedLines,_that.lyricsText,_that.timelineOffset);case _:
  return null;

}
}

}

/// @nodoc


class _LyricSelectionResult extends LyricSelectionResult with DiagnosticableTreeMixin {
  const _LyricSelectionResult({required this.track, required this.fromGetApi, required this.source, required this.score, required this.breakdown, required this.durationDiffSeconds, final  List<LyricLine> syncedLines = const <LyricLine>[], required this.lyricsText, this.timelineOffset = Duration.zero}): _syncedLines = syncedLines,super._();
  

@override final  LyricTrack track;
@override final  bool fromGetApi;
@override final  String source;
@override final  double score;
@override final  LyricScoreBreakdown breakdown;
@override final  int durationDiffSeconds;
 final  List<LyricLine> _syncedLines;
@override@JsonKey() List<LyricLine> get syncedLines {
  if (_syncedLines is EqualUnmodifiableListView) return _syncedLines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_syncedLines);
}

@override final  String lyricsText;
@override@JsonKey() final  Duration timelineOffset;

/// Create a copy of LyricSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LyricSelectionResultCopyWith<_LyricSelectionResult> get copyWith => __$LyricSelectionResultCopyWithImpl<_LyricSelectionResult>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'LyricSelectionResult'))
    ..add(DiagnosticsProperty('track', track))..add(DiagnosticsProperty('fromGetApi', fromGetApi))..add(DiagnosticsProperty('source', source))..add(DiagnosticsProperty('score', score))..add(DiagnosticsProperty('breakdown', breakdown))..add(DiagnosticsProperty('durationDiffSeconds', durationDiffSeconds))..add(DiagnosticsProperty('syncedLines', syncedLines))..add(DiagnosticsProperty('lyricsText', lyricsText))..add(DiagnosticsProperty('timelineOffset', timelineOffset));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LyricSelectionResult&&(identical(other.track, track) || other.track == track)&&(identical(other.fromGetApi, fromGetApi) || other.fromGetApi == fromGetApi)&&(identical(other.source, source) || other.source == source)&&(identical(other.score, score) || other.score == score)&&(identical(other.breakdown, breakdown) || other.breakdown == breakdown)&&(identical(other.durationDiffSeconds, durationDiffSeconds) || other.durationDiffSeconds == durationDiffSeconds)&&const DeepCollectionEquality().equals(other._syncedLines, _syncedLines)&&(identical(other.lyricsText, lyricsText) || other.lyricsText == lyricsText)&&(identical(other.timelineOffset, timelineOffset) || other.timelineOffset == timelineOffset));
}


@override
int get hashCode => Object.hash(runtimeType,track,fromGetApi,source,score,breakdown,durationDiffSeconds,const DeepCollectionEquality().hash(_syncedLines),lyricsText,timelineOffset);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'LyricSelectionResult(track: $track, fromGetApi: $fromGetApi, source: $source, score: $score, breakdown: $breakdown, durationDiffSeconds: $durationDiffSeconds, syncedLines: $syncedLines, lyricsText: $lyricsText, timelineOffset: $timelineOffset)';
}


}

/// @nodoc
abstract mixin class _$LyricSelectionResultCopyWith<$Res> implements $LyricSelectionResultCopyWith<$Res> {
  factory _$LyricSelectionResultCopyWith(_LyricSelectionResult value, $Res Function(_LyricSelectionResult) _then) = __$LyricSelectionResultCopyWithImpl;
@override @useResult
$Res call({
 LyricTrack track, bool fromGetApi, String source, double score, LyricScoreBreakdown breakdown, int durationDiffSeconds, List<LyricLine> syncedLines, String lyricsText, Duration timelineOffset
});


@override $LyricTrackCopyWith<$Res> get track;

}
/// @nodoc
class __$LyricSelectionResultCopyWithImpl<$Res>
    implements _$LyricSelectionResultCopyWith<$Res> {
  __$LyricSelectionResultCopyWithImpl(this._self, this._then);

  final _LyricSelectionResult _self;
  final $Res Function(_LyricSelectionResult) _then;

/// Create a copy of LyricSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? track = null,Object? fromGetApi = null,Object? source = null,Object? score = null,Object? breakdown = null,Object? durationDiffSeconds = null,Object? syncedLines = null,Object? lyricsText = null,Object? timelineOffset = null,}) {
  return _then(_LyricSelectionResult(
track: null == track ? _self.track : track // ignore: cast_nullable_to_non_nullable
as LyricTrack,fromGetApi: null == fromGetApi ? _self.fromGetApi : fromGetApi // ignore: cast_nullable_to_non_nullable
as bool,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,breakdown: null == breakdown ? _self.breakdown : breakdown // ignore: cast_nullable_to_non_nullable
as LyricScoreBreakdown,durationDiffSeconds: null == durationDiffSeconds ? _self.durationDiffSeconds : durationDiffSeconds // ignore: cast_nullable_to_non_nullable
as int,syncedLines: null == syncedLines ? _self._syncedLines : syncedLines // ignore: cast_nullable_to_non_nullable
as List<LyricLine>,lyricsText: null == lyricsText ? _self.lyricsText : lyricsText // ignore: cast_nullable_to_non_nullable
as String,timelineOffset: null == timelineOffset ? _self.timelineOffset : timelineOffset // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}

/// Create a copy of LyricSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LyricTrackCopyWith<$Res> get track {
  
  return $LyricTrackCopyWith<$Res>(_self.track, (value) {
    return _then(_self.copyWith(track: value));
  });
}
}

// dart format on
