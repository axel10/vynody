// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'music_lyric.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MusicLyric {

 String get id; List<LyricLine> get syncedLines; String get plainText; Map<String, MusicLyricTranslation> get translations; String get source;@JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration get timelineOffset;
/// Create a copy of MusicLyric
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MusicLyricCopyWith<MusicLyric> get copyWith => _$MusicLyricCopyWithImpl<MusicLyric>(this as MusicLyric, _$identity);

  /// Serializes this MusicLyric to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MusicLyric&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other.syncedLines, syncedLines)&&(identical(other.plainText, plainText) || other.plainText == plainText)&&const DeepCollectionEquality().equals(other.translations, translations)&&(identical(other.source, source) || other.source == source)&&(identical(other.timelineOffset, timelineOffset) || other.timelineOffset == timelineOffset));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(syncedLines),plainText,const DeepCollectionEquality().hash(translations),source,timelineOffset);

@override
String toString() {
  return 'MusicLyric(id: $id, syncedLines: $syncedLines, plainText: $plainText, translations: $translations, source: $source, timelineOffset: $timelineOffset)';
}


}

/// @nodoc
abstract mixin class $MusicLyricCopyWith<$Res>  {
  factory $MusicLyricCopyWith(MusicLyric value, $Res Function(MusicLyric) _then) = _$MusicLyricCopyWithImpl;
@useResult
$Res call({
 String id, List<LyricLine> syncedLines, String plainText, Map<String, MusicLyricTranslation> translations, String source,@JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration timelineOffset
});




}
/// @nodoc
class _$MusicLyricCopyWithImpl<$Res>
    implements $MusicLyricCopyWith<$Res> {
  _$MusicLyricCopyWithImpl(this._self, this._then);

  final MusicLyric _self;
  final $Res Function(MusicLyric) _then;

/// Create a copy of MusicLyric
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? syncedLines = null,Object? plainText = null,Object? translations = null,Object? source = null,Object? timelineOffset = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,syncedLines: null == syncedLines ? _self.syncedLines : syncedLines // ignore: cast_nullable_to_non_nullable
as List<LyricLine>,plainText: null == plainText ? _self.plainText : plainText // ignore: cast_nullable_to_non_nullable
as String,translations: null == translations ? _self.translations : translations // ignore: cast_nullable_to_non_nullable
as Map<String, MusicLyricTranslation>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,timelineOffset: null == timelineOffset ? _self.timelineOffset : timelineOffset // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}

}


/// Adds pattern-matching-related methods to [MusicLyric].
extension MusicLyricPatterns on MusicLyric {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MusicLyric value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MusicLyric() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MusicLyric value)  $default,){
final _that = this;
switch (_that) {
case _MusicLyric():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MusicLyric value)?  $default,){
final _that = this;
switch (_that) {
case _MusicLyric() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  List<LyricLine> syncedLines,  String plainText,  Map<String, MusicLyricTranslation> translations,  String source, @JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timelineOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MusicLyric() when $default != null:
return $default(_that.id,_that.syncedLines,_that.plainText,_that.translations,_that.source,_that.timelineOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  List<LyricLine> syncedLines,  String plainText,  Map<String, MusicLyricTranslation> translations,  String source, @JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timelineOffset)  $default,) {final _that = this;
switch (_that) {
case _MusicLyric():
return $default(_that.id,_that.syncedLines,_that.plainText,_that.translations,_that.source,_that.timelineOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  List<LyricLine> syncedLines,  String plainText,  Map<String, MusicLyricTranslation> translations,  String source, @JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timelineOffset)?  $default,) {final _that = this;
switch (_that) {
case _MusicLyric() when $default != null:
return $default(_that.id,_that.syncedLines,_that.plainText,_that.translations,_that.source,_that.timelineOffset);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MusicLyric extends MusicLyric {
  const _MusicLyric({this.id = '', final  List<LyricLine> syncedLines = const <LyricLine>[], this.plainText = '', final  Map<String, MusicLyricTranslation> translations = const <String, MusicLyricTranslation>{}, this.source = '', @JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) this.timelineOffset = Duration.zero}): _syncedLines = syncedLines,_translations = translations,super._();
  factory _MusicLyric.fromJson(Map<String, dynamic> json) => _$MusicLyricFromJson(json);

@override@JsonKey() final  String id;
 final  List<LyricLine> _syncedLines;
@override@JsonKey() List<LyricLine> get syncedLines {
  if (_syncedLines is EqualUnmodifiableListView) return _syncedLines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_syncedLines);
}

@override@JsonKey() final  String plainText;
 final  Map<String, MusicLyricTranslation> _translations;
@override@JsonKey() Map<String, MusicLyricTranslation> get translations {
  if (_translations is EqualUnmodifiableMapView) return _translations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_translations);
}

@override@JsonKey() final  String source;
@override@JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) final  Duration timelineOffset;

/// Create a copy of MusicLyric
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MusicLyricCopyWith<_MusicLyric> get copyWith => __$MusicLyricCopyWithImpl<_MusicLyric>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MusicLyricToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MusicLyric&&(identical(other.id, id) || other.id == id)&&const DeepCollectionEquality().equals(other._syncedLines, _syncedLines)&&(identical(other.plainText, plainText) || other.plainText == plainText)&&const DeepCollectionEquality().equals(other._translations, _translations)&&(identical(other.source, source) || other.source == source)&&(identical(other.timelineOffset, timelineOffset) || other.timelineOffset == timelineOffset));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,const DeepCollectionEquality().hash(_syncedLines),plainText,const DeepCollectionEquality().hash(_translations),source,timelineOffset);

@override
String toString() {
  return 'MusicLyric(id: $id, syncedLines: $syncedLines, plainText: $plainText, translations: $translations, source: $source, timelineOffset: $timelineOffset)';
}


}

/// @nodoc
abstract mixin class _$MusicLyricCopyWith<$Res> implements $MusicLyricCopyWith<$Res> {
  factory _$MusicLyricCopyWith(_MusicLyric value, $Res Function(_MusicLyric) _then) = __$MusicLyricCopyWithImpl;
@override @useResult
$Res call({
 String id, List<LyricLine> syncedLines, String plainText, Map<String, MusicLyricTranslation> translations, String source,@JsonKey(fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration timelineOffset
});




}
/// @nodoc
class __$MusicLyricCopyWithImpl<$Res>
    implements _$MusicLyricCopyWith<$Res> {
  __$MusicLyricCopyWithImpl(this._self, this._then);

  final _MusicLyric _self;
  final $Res Function(_MusicLyric) _then;

/// Create a copy of MusicLyric
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? syncedLines = null,Object? plainText = null,Object? translations = null,Object? source = null,Object? timelineOffset = null,}) {
  return _then(_MusicLyric(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,syncedLines: null == syncedLines ? _self._syncedLines : syncedLines // ignore: cast_nullable_to_non_nullable
as List<LyricLine>,plainText: null == plainText ? _self.plainText : plainText // ignore: cast_nullable_to_non_nullable
as String,translations: null == translations ? _self._translations : translations // ignore: cast_nullable_to_non_nullable
as Map<String, MusicLyricTranslation>,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as String,timelineOffset: null == timelineOffset ? _self.timelineOffset : timelineOffset // ignore: cast_nullable_to_non_nullable
as Duration,
  ));
}


}

// dart format on
