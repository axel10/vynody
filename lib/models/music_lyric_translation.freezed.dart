// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'music_lyric_translation.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$MusicLyricTranslation {

 String get languageCode; String get translatedText;@JsonKey(fromJson: stringListFromJson, toJson: stringListToJson) List<String> get translatedLines; String? get provider; DateTime? get updatedAt;
/// Create a copy of MusicLyricTranslation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MusicLyricTranslationCopyWith<MusicLyricTranslation> get copyWith => _$MusicLyricTranslationCopyWithImpl<MusicLyricTranslation>(this as MusicLyricTranslation, _$identity);

  /// Serializes this MusicLyricTranslation to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MusicLyricTranslation&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.translatedText, translatedText) || other.translatedText == translatedText)&&const DeepCollectionEquality().equals(other.translatedLines, translatedLines)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,languageCode,translatedText,const DeepCollectionEquality().hash(translatedLines),provider,updatedAt);

@override
String toString() {
  return 'MusicLyricTranslation(languageCode: $languageCode, translatedText: $translatedText, translatedLines: $translatedLines, provider: $provider, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $MusicLyricTranslationCopyWith<$Res>  {
  factory $MusicLyricTranslationCopyWith(MusicLyricTranslation value, $Res Function(MusicLyricTranslation) _then) = _$MusicLyricTranslationCopyWithImpl;
@useResult
$Res call({
 String languageCode, String translatedText,@JsonKey(fromJson: stringListFromJson, toJson: stringListToJson) List<String> translatedLines, String? provider, DateTime? updatedAt
});




}
/// @nodoc
class _$MusicLyricTranslationCopyWithImpl<$Res>
    implements $MusicLyricTranslationCopyWith<$Res> {
  _$MusicLyricTranslationCopyWithImpl(this._self, this._then);

  final MusicLyricTranslation _self;
  final $Res Function(MusicLyricTranslation) _then;

/// Create a copy of MusicLyricTranslation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? languageCode = null,Object? translatedText = null,Object? translatedLines = null,Object? provider = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,translatedText: null == translatedText ? _self.translatedText : translatedText // ignore: cast_nullable_to_non_nullable
as String,translatedLines: null == translatedLines ? _self.translatedLines : translatedLines // ignore: cast_nullable_to_non_nullable
as List<String>,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [MusicLyricTranslation].
extension MusicLyricTranslationPatterns on MusicLyricTranslation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MusicLyricTranslation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MusicLyricTranslation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MusicLyricTranslation value)  $default,){
final _that = this;
switch (_that) {
case _MusicLyricTranslation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MusicLyricTranslation value)?  $default,){
final _that = this;
switch (_that) {
case _MusicLyricTranslation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String languageCode,  String translatedText, @JsonKey(fromJson: stringListFromJson, toJson: stringListToJson)  List<String> translatedLines,  String? provider,  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MusicLyricTranslation() when $default != null:
return $default(_that.languageCode,_that.translatedText,_that.translatedLines,_that.provider,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String languageCode,  String translatedText, @JsonKey(fromJson: stringListFromJson, toJson: stringListToJson)  List<String> translatedLines,  String? provider,  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _MusicLyricTranslation():
return $default(_that.languageCode,_that.translatedText,_that.translatedLines,_that.provider,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String languageCode,  String translatedText, @JsonKey(fromJson: stringListFromJson, toJson: stringListToJson)  List<String> translatedLines,  String? provider,  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _MusicLyricTranslation() when $default != null:
return $default(_that.languageCode,_that.translatedText,_that.translatedLines,_that.provider,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _MusicLyricTranslation extends MusicLyricTranslation {
  const _MusicLyricTranslation({this.languageCode = 'zh', this.translatedText = '', @JsonKey(fromJson: stringListFromJson, toJson: stringListToJson) final  List<String> translatedLines = const <String>[], this.provider, this.updatedAt}): _translatedLines = translatedLines,super._();
  factory _MusicLyricTranslation.fromJson(Map<String, dynamic> json) => _$MusicLyricTranslationFromJson(json);

@override@JsonKey() final  String languageCode;
@override@JsonKey() final  String translatedText;
 final  List<String> _translatedLines;
@override@JsonKey(fromJson: stringListFromJson, toJson: stringListToJson) List<String> get translatedLines {
  if (_translatedLines is EqualUnmodifiableListView) return _translatedLines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_translatedLines);
}

@override final  String? provider;
@override final  DateTime? updatedAt;

/// Create a copy of MusicLyricTranslation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MusicLyricTranslationCopyWith<_MusicLyricTranslation> get copyWith => __$MusicLyricTranslationCopyWithImpl<_MusicLyricTranslation>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MusicLyricTranslationToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MusicLyricTranslation&&(identical(other.languageCode, languageCode) || other.languageCode == languageCode)&&(identical(other.translatedText, translatedText) || other.translatedText == translatedText)&&const DeepCollectionEquality().equals(other._translatedLines, _translatedLines)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,languageCode,translatedText,const DeepCollectionEquality().hash(_translatedLines),provider,updatedAt);

@override
String toString() {
  return 'MusicLyricTranslation(languageCode: $languageCode, translatedText: $translatedText, translatedLines: $translatedLines, provider: $provider, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$MusicLyricTranslationCopyWith<$Res> implements $MusicLyricTranslationCopyWith<$Res> {
  factory _$MusicLyricTranslationCopyWith(_MusicLyricTranslation value, $Res Function(_MusicLyricTranslation) _then) = __$MusicLyricTranslationCopyWithImpl;
@override @useResult
$Res call({
 String languageCode, String translatedText,@JsonKey(fromJson: stringListFromJson, toJson: stringListToJson) List<String> translatedLines, String? provider, DateTime? updatedAt
});




}
/// @nodoc
class __$MusicLyricTranslationCopyWithImpl<$Res>
    implements _$MusicLyricTranslationCopyWith<$Res> {
  __$MusicLyricTranslationCopyWithImpl(this._self, this._then);

  final _MusicLyricTranslation _self;
  final $Res Function(_MusicLyricTranslation) _then;

/// Create a copy of MusicLyricTranslation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? languageCode = null,Object? translatedText = null,Object? translatedLines = null,Object? provider = freezed,Object? updatedAt = freezed,}) {
  return _then(_MusicLyricTranslation(
languageCode: null == languageCode ? _self.languageCode : languageCode // ignore: cast_nullable_to_non_nullable
as String,translatedText: null == translatedText ? _self.translatedText : translatedText // ignore: cast_nullable_to_non_nullable
as String,translatedLines: null == translatedLines ? _self._translatedLines : translatedLines // ignore: cast_nullable_to_non_nullable
as List<String>,provider: freezed == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
