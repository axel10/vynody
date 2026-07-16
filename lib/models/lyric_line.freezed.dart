// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lyric_line.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$LyricLine {

@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration get timestamp; String get text; bool get isTimed; List<LyricWord>? get words;
/// Create a copy of LyricLine
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LyricLineCopyWith<LyricLine> get copyWith => _$LyricLineCopyWithImpl<LyricLine>(this as LyricLine, _$identity);

  /// Serializes this LyricLine to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LyricLine&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.text, text) || other.text == text)&&(identical(other.isTimed, isTimed) || other.isTimed == isTimed)&&const DeepCollectionEquality().equals(other.words, words));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,timestamp,text,isTimed,const DeepCollectionEquality().hash(words));

@override
String toString() {
  return 'LyricLine(timestamp: $timestamp, text: $text, isTimed: $isTimed, words: $words)';
}


}

/// @nodoc
abstract mixin class $LyricLineCopyWith<$Res>  {
  factory $LyricLineCopyWith(LyricLine value, $Res Function(LyricLine) _then) = _$LyricLineCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration timestamp, String text, bool isTimed, List<LyricWord>? words
});




}
/// @nodoc
class _$LyricLineCopyWithImpl<$Res>
    implements $LyricLineCopyWith<$Res> {
  _$LyricLineCopyWithImpl(this._self, this._then);

  final LyricLine _self;
  final $Res Function(LyricLine) _then;

/// Create a copy of LyricLine
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? timestamp = null,Object? text = null,Object? isTimed = null,Object? words = freezed,}) {
  return _then(_self.copyWith(
timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as Duration,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,isTimed: null == isTimed ? _self.isTimed : isTimed // ignore: cast_nullable_to_non_nullable
as bool,words: freezed == words ? _self.words : words // ignore: cast_nullable_to_non_nullable
as List<LyricWord>?,
  ));
}

}


/// Adds pattern-matching-related methods to [LyricLine].
extension LyricLinePatterns on LyricLine {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LyricLine value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LyricLine() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LyricLine value)  $default,){
final _that = this;
switch (_that) {
case _LyricLine():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LyricLine value)?  $default,){
final _that = this;
switch (_that) {
case _LyricLine() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timestamp,  String text,  bool isTimed,  List<LyricWord>? words)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LyricLine() when $default != null:
return $default(_that.timestamp,_that.text,_that.isTimed,_that.words);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timestamp,  String text,  bool isTimed,  List<LyricWord>? words)  $default,) {final _that = this;
switch (_that) {
case _LyricLine():
return $default(_that.timestamp,_that.text,_that.isTimed,_that.words);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timestamp,  String text,  bool isTimed,  List<LyricWord>? words)?  $default,) {final _that = this;
switch (_that) {
case _LyricLine() when $default != null:
return $default(_that.timestamp,_that.text,_that.isTimed,_that.words);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LyricLine extends LyricLine {
  const _LyricLine({@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) required this.timestamp, this.text = '', this.isTimed = true, final  List<LyricWord>? words = null}): _words = words,super._();
  factory _LyricLine.fromJson(Map<String, dynamic> json) => _$LyricLineFromJson(json);

@override@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) final  Duration timestamp;
@override@JsonKey() final  String text;
@override@JsonKey() final  bool isTimed;
 final  List<LyricWord>? _words;
@override@JsonKey() List<LyricWord>? get words {
  final value = _words;
  if (value == null) return null;
  if (_words is EqualUnmodifiableListView) return _words;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of LyricLine
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LyricLineCopyWith<_LyricLine> get copyWith => __$LyricLineCopyWithImpl<_LyricLine>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LyricLineToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LyricLine&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.text, text) || other.text == text)&&(identical(other.isTimed, isTimed) || other.isTimed == isTimed)&&const DeepCollectionEquality().equals(other._words, _words));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,timestamp,text,isTimed,const DeepCollectionEquality().hash(_words));

@override
String toString() {
  return 'LyricLine(timestamp: $timestamp, text: $text, isTimed: $isTimed, words: $words)';
}


}

/// @nodoc
abstract mixin class _$LyricLineCopyWith<$Res> implements $LyricLineCopyWith<$Res> {
  factory _$LyricLineCopyWith(_LyricLine value, $Res Function(_LyricLine) _then) = __$LyricLineCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration timestamp, String text, bool isTimed, List<LyricWord>? words
});




}
/// @nodoc
class __$LyricLineCopyWithImpl<$Res>
    implements _$LyricLineCopyWith<$Res> {
  __$LyricLineCopyWithImpl(this._self, this._then);

  final _LyricLine _self;
  final $Res Function(_LyricLine) _then;

/// Create a copy of LyricLine
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? timestamp = null,Object? text = null,Object? isTimed = null,Object? words = freezed,}) {
  return _then(_LyricLine(
timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as Duration,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,isTimed: null == isTimed ? _self.isTimed : isTimed // ignore: cast_nullable_to_non_nullable
as bool,words: freezed == words ? _self._words : words // ignore: cast_nullable_to_non_nullable
as List<LyricWord>?,
  ));
}


}


/// @nodoc
mixin _$LyricWord {

@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration get timestamp; int get durationMs; String get text;
/// Create a copy of LyricWord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LyricWordCopyWith<LyricWord> get copyWith => _$LyricWordCopyWithImpl<LyricWord>(this as LyricWord, _$identity);

  /// Serializes this LyricWord to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LyricWord&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.text, text) || other.text == text));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,timestamp,durationMs,text);

@override
String toString() {
  return 'LyricWord(timestamp: $timestamp, durationMs: $durationMs, text: $text)';
}


}

/// @nodoc
abstract mixin class $LyricWordCopyWith<$Res>  {
  factory $LyricWordCopyWith(LyricWord value, $Res Function(LyricWord) _then) = _$LyricWordCopyWithImpl;
@useResult
$Res call({
@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration timestamp, int durationMs, String text
});




}
/// @nodoc
class _$LyricWordCopyWithImpl<$Res>
    implements $LyricWordCopyWith<$Res> {
  _$LyricWordCopyWithImpl(this._self, this._then);

  final LyricWord _self;
  final $Res Function(LyricWord) _then;

/// Create a copy of LyricWord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? timestamp = null,Object? durationMs = null,Object? text = null,}) {
  return _then(_self.copyWith(
timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as Duration,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LyricWord].
extension LyricWordPatterns on LyricWord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LyricWord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LyricWord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LyricWord value)  $default,){
final _that = this;
switch (_that) {
case _LyricWord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LyricWord value)?  $default,){
final _that = this;
switch (_that) {
case _LyricWord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timestamp,  int durationMs,  String text)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LyricWord() when $default != null:
return $default(_that.timestamp,_that.durationMs,_that.text);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timestamp,  int durationMs,  String text)  $default,) {final _that = this;
switch (_that) {
case _LyricWord():
return $default(_that.timestamp,_that.durationMs,_that.text);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds)  Duration timestamp,  int durationMs,  String text)?  $default,) {final _that = this;
switch (_that) {
case _LyricWord() when $default != null:
return $default(_that.timestamp,_that.durationMs,_that.text);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _LyricWord implements LyricWord {
  const _LyricWord({@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) required this.timestamp, required this.durationMs, required this.text});
  factory _LyricWord.fromJson(Map<String, dynamic> json) => _$LyricWordFromJson(json);

@override@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) final  Duration timestamp;
@override final  int durationMs;
@override final  String text;

/// Create a copy of LyricWord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LyricWordCopyWith<_LyricWord> get copyWith => __$LyricWordCopyWithImpl<_LyricWord>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LyricWordToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LyricWord&&(identical(other.timestamp, timestamp) || other.timestamp == timestamp)&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs)&&(identical(other.text, text) || other.text == text));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,timestamp,durationMs,text);

@override
String toString() {
  return 'LyricWord(timestamp: $timestamp, durationMs: $durationMs, text: $text)';
}


}

/// @nodoc
abstract mixin class _$LyricWordCopyWith<$Res> implements $LyricWordCopyWith<$Res> {
  factory _$LyricWordCopyWith(_LyricWord value, $Res Function(_LyricWord) _then) = __$LyricWordCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(name: 'timestampMs', fromJson: durationFromMilliseconds, toJson: durationToMilliseconds) Duration timestamp, int durationMs, String text
});




}
/// @nodoc
class __$LyricWordCopyWithImpl<$Res>
    implements _$LyricWordCopyWith<$Res> {
  __$LyricWordCopyWithImpl(this._self, this._then);

  final _LyricWord _self;
  final $Res Function(_LyricWord) _then;

/// Create a copy of LyricWord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? timestamp = null,Object? durationMs = null,Object? text = null,}) {
  return _then(_LyricWord(
timestamp: null == timestamp ? _self.timestamp : timestamp // ignore: cast_nullable_to_non_nullable
as Duration,durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
