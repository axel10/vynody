// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lyrics_controller_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LyricsControllerState {

 bool get isLyricsLoading; bool get isLyricsTranslating; String get lyricsTranslationStatus; bool get hasLyrics; bool get lyricsSearchAttempted; bool get isLyricsSynced; List<LyricLine> get currentLyricsLines; String get currentLyricsText; String? get currentLyricsTitle; String get lyricsTranslationLanguageCode;
/// Create a copy of LyricsControllerState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LyricsControllerStateCopyWith<LyricsControllerState> get copyWith => _$LyricsControllerStateCopyWithImpl<LyricsControllerState>(this as LyricsControllerState, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LyricsControllerState&&(identical(other.isLyricsLoading, isLyricsLoading) || other.isLyricsLoading == isLyricsLoading)&&(identical(other.isLyricsTranslating, isLyricsTranslating) || other.isLyricsTranslating == isLyricsTranslating)&&(identical(other.lyricsTranslationStatus, lyricsTranslationStatus) || other.lyricsTranslationStatus == lyricsTranslationStatus)&&(identical(other.hasLyrics, hasLyrics) || other.hasLyrics == hasLyrics)&&(identical(other.lyricsSearchAttempted, lyricsSearchAttempted) || other.lyricsSearchAttempted == lyricsSearchAttempted)&&(identical(other.isLyricsSynced, isLyricsSynced) || other.isLyricsSynced == isLyricsSynced)&&const DeepCollectionEquality().equals(other.currentLyricsLines, currentLyricsLines)&&(identical(other.currentLyricsText, currentLyricsText) || other.currentLyricsText == currentLyricsText)&&(identical(other.currentLyricsTitle, currentLyricsTitle) || other.currentLyricsTitle == currentLyricsTitle)&&(identical(other.lyricsTranslationLanguageCode, lyricsTranslationLanguageCode) || other.lyricsTranslationLanguageCode == lyricsTranslationLanguageCode));
}


@override
int get hashCode => Object.hash(runtimeType,isLyricsLoading,isLyricsTranslating,lyricsTranslationStatus,hasLyrics,lyricsSearchAttempted,isLyricsSynced,const DeepCollectionEquality().hash(currentLyricsLines),currentLyricsText,currentLyricsTitle,lyricsTranslationLanguageCode);

@override
String toString() {
  return 'LyricsControllerState(isLyricsLoading: $isLyricsLoading, isLyricsTranslating: $isLyricsTranslating, lyricsTranslationStatus: $lyricsTranslationStatus, hasLyrics: $hasLyrics, lyricsSearchAttempted: $lyricsSearchAttempted, isLyricsSynced: $isLyricsSynced, currentLyricsLines: $currentLyricsLines, currentLyricsText: $currentLyricsText, currentLyricsTitle: $currentLyricsTitle, lyricsTranslationLanguageCode: $lyricsTranslationLanguageCode)';
}


}

/// @nodoc
abstract mixin class $LyricsControllerStateCopyWith<$Res>  {
  factory $LyricsControllerStateCopyWith(LyricsControllerState value, $Res Function(LyricsControllerState) _then) = _$LyricsControllerStateCopyWithImpl;
@useResult
$Res call({
 bool isLyricsLoading, bool isLyricsTranslating, String lyricsTranslationStatus, bool hasLyrics, bool lyricsSearchAttempted, bool isLyricsSynced, List<LyricLine> currentLyricsLines, String currentLyricsText, String? currentLyricsTitle, String lyricsTranslationLanguageCode
});




}
/// @nodoc
class _$LyricsControllerStateCopyWithImpl<$Res>
    implements $LyricsControllerStateCopyWith<$Res> {
  _$LyricsControllerStateCopyWithImpl(this._self, this._then);

  final LyricsControllerState _self;
  final $Res Function(LyricsControllerState) _then;

/// Create a copy of LyricsControllerState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? isLyricsLoading = null,Object? isLyricsTranslating = null,Object? lyricsTranslationStatus = null,Object? hasLyrics = null,Object? lyricsSearchAttempted = null,Object? isLyricsSynced = null,Object? currentLyricsLines = null,Object? currentLyricsText = null,Object? currentLyricsTitle = freezed,Object? lyricsTranslationLanguageCode = null,}) {
  return _then(_self.copyWith(
isLyricsLoading: null == isLyricsLoading ? _self.isLyricsLoading : isLyricsLoading // ignore: cast_nullable_to_non_nullable
as bool,isLyricsTranslating: null == isLyricsTranslating ? _self.isLyricsTranslating : isLyricsTranslating // ignore: cast_nullable_to_non_nullable
as bool,lyricsTranslationStatus: null == lyricsTranslationStatus ? _self.lyricsTranslationStatus : lyricsTranslationStatus // ignore: cast_nullable_to_non_nullable
as String,hasLyrics: null == hasLyrics ? _self.hasLyrics : hasLyrics // ignore: cast_nullable_to_non_nullable
as bool,lyricsSearchAttempted: null == lyricsSearchAttempted ? _self.lyricsSearchAttempted : lyricsSearchAttempted // ignore: cast_nullable_to_non_nullable
as bool,isLyricsSynced: null == isLyricsSynced ? _self.isLyricsSynced : isLyricsSynced // ignore: cast_nullable_to_non_nullable
as bool,currentLyricsLines: null == currentLyricsLines ? _self.currentLyricsLines : currentLyricsLines // ignore: cast_nullable_to_non_nullable
as List<LyricLine>,currentLyricsText: null == currentLyricsText ? _self.currentLyricsText : currentLyricsText // ignore: cast_nullable_to_non_nullable
as String,currentLyricsTitle: freezed == currentLyricsTitle ? _self.currentLyricsTitle : currentLyricsTitle // ignore: cast_nullable_to_non_nullable
as String?,lyricsTranslationLanguageCode: null == lyricsTranslationLanguageCode ? _self.lyricsTranslationLanguageCode : lyricsTranslationLanguageCode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [LyricsControllerState].
extension LyricsControllerStatePatterns on LyricsControllerState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LyricsControllerState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LyricsControllerState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LyricsControllerState value)  $default,){
final _that = this;
switch (_that) {
case _LyricsControllerState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LyricsControllerState value)?  $default,){
final _that = this;
switch (_that) {
case _LyricsControllerState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool isLyricsLoading,  bool isLyricsTranslating,  String lyricsTranslationStatus,  bool hasLyrics,  bool lyricsSearchAttempted,  bool isLyricsSynced,  List<LyricLine> currentLyricsLines,  String currentLyricsText,  String? currentLyricsTitle,  String lyricsTranslationLanguageCode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LyricsControllerState() when $default != null:
return $default(_that.isLyricsLoading,_that.isLyricsTranslating,_that.lyricsTranslationStatus,_that.hasLyrics,_that.lyricsSearchAttempted,_that.isLyricsSynced,_that.currentLyricsLines,_that.currentLyricsText,_that.currentLyricsTitle,_that.lyricsTranslationLanguageCode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool isLyricsLoading,  bool isLyricsTranslating,  String lyricsTranslationStatus,  bool hasLyrics,  bool lyricsSearchAttempted,  bool isLyricsSynced,  List<LyricLine> currentLyricsLines,  String currentLyricsText,  String? currentLyricsTitle,  String lyricsTranslationLanguageCode)  $default,) {final _that = this;
switch (_that) {
case _LyricsControllerState():
return $default(_that.isLyricsLoading,_that.isLyricsTranslating,_that.lyricsTranslationStatus,_that.hasLyrics,_that.lyricsSearchAttempted,_that.isLyricsSynced,_that.currentLyricsLines,_that.currentLyricsText,_that.currentLyricsTitle,_that.lyricsTranslationLanguageCode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool isLyricsLoading,  bool isLyricsTranslating,  String lyricsTranslationStatus,  bool hasLyrics,  bool lyricsSearchAttempted,  bool isLyricsSynced,  List<LyricLine> currentLyricsLines,  String currentLyricsText,  String? currentLyricsTitle,  String lyricsTranslationLanguageCode)?  $default,) {final _that = this;
switch (_that) {
case _LyricsControllerState() when $default != null:
return $default(_that.isLyricsLoading,_that.isLyricsTranslating,_that.lyricsTranslationStatus,_that.hasLyrics,_that.lyricsSearchAttempted,_that.isLyricsSynced,_that.currentLyricsLines,_that.currentLyricsText,_that.currentLyricsTitle,_that.lyricsTranslationLanguageCode);case _:
  return null;

}
}

}

/// @nodoc


class _LyricsControllerState extends LyricsControllerState {
  const _LyricsControllerState({this.isLyricsLoading = false, this.isLyricsTranslating = false, this.lyricsTranslationStatus = '', this.hasLyrics = false, this.lyricsSearchAttempted = false, this.isLyricsSynced = false, final  List<LyricLine> currentLyricsLines = const <LyricLine>[], this.currentLyricsText = '', this.currentLyricsTitle, this.lyricsTranslationLanguageCode = 'zh'}): _currentLyricsLines = currentLyricsLines,super._();
  

@override@JsonKey() final  bool isLyricsLoading;
@override@JsonKey() final  bool isLyricsTranslating;
@override@JsonKey() final  String lyricsTranslationStatus;
@override@JsonKey() final  bool hasLyrics;
@override@JsonKey() final  bool lyricsSearchAttempted;
@override@JsonKey() final  bool isLyricsSynced;
 final  List<LyricLine> _currentLyricsLines;
@override@JsonKey() List<LyricLine> get currentLyricsLines {
  if (_currentLyricsLines is EqualUnmodifiableListView) return _currentLyricsLines;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_currentLyricsLines);
}

@override@JsonKey() final  String currentLyricsText;
@override final  String? currentLyricsTitle;
@override@JsonKey() final  String lyricsTranslationLanguageCode;

/// Create a copy of LyricsControllerState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LyricsControllerStateCopyWith<_LyricsControllerState> get copyWith => __$LyricsControllerStateCopyWithImpl<_LyricsControllerState>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _LyricsControllerState&&(identical(other.isLyricsLoading, isLyricsLoading) || other.isLyricsLoading == isLyricsLoading)&&(identical(other.isLyricsTranslating, isLyricsTranslating) || other.isLyricsTranslating == isLyricsTranslating)&&(identical(other.lyricsTranslationStatus, lyricsTranslationStatus) || other.lyricsTranslationStatus == lyricsTranslationStatus)&&(identical(other.hasLyrics, hasLyrics) || other.hasLyrics == hasLyrics)&&(identical(other.lyricsSearchAttempted, lyricsSearchAttempted) || other.lyricsSearchAttempted == lyricsSearchAttempted)&&(identical(other.isLyricsSynced, isLyricsSynced) || other.isLyricsSynced == isLyricsSynced)&&const DeepCollectionEquality().equals(other._currentLyricsLines, _currentLyricsLines)&&(identical(other.currentLyricsText, currentLyricsText) || other.currentLyricsText == currentLyricsText)&&(identical(other.currentLyricsTitle, currentLyricsTitle) || other.currentLyricsTitle == currentLyricsTitle)&&(identical(other.lyricsTranslationLanguageCode, lyricsTranslationLanguageCode) || other.lyricsTranslationLanguageCode == lyricsTranslationLanguageCode));
}


@override
int get hashCode => Object.hash(runtimeType,isLyricsLoading,isLyricsTranslating,lyricsTranslationStatus,hasLyrics,lyricsSearchAttempted,isLyricsSynced,const DeepCollectionEquality().hash(_currentLyricsLines),currentLyricsText,currentLyricsTitle,lyricsTranslationLanguageCode);

@override
String toString() {
  return 'LyricsControllerState(isLyricsLoading: $isLyricsLoading, isLyricsTranslating: $isLyricsTranslating, lyricsTranslationStatus: $lyricsTranslationStatus, hasLyrics: $hasLyrics, lyricsSearchAttempted: $lyricsSearchAttempted, isLyricsSynced: $isLyricsSynced, currentLyricsLines: $currentLyricsLines, currentLyricsText: $currentLyricsText, currentLyricsTitle: $currentLyricsTitle, lyricsTranslationLanguageCode: $lyricsTranslationLanguageCode)';
}


}

/// @nodoc
abstract mixin class _$LyricsControllerStateCopyWith<$Res> implements $LyricsControllerStateCopyWith<$Res> {
  factory _$LyricsControllerStateCopyWith(_LyricsControllerState value, $Res Function(_LyricsControllerState) _then) = __$LyricsControllerStateCopyWithImpl;
@override @useResult
$Res call({
 bool isLyricsLoading, bool isLyricsTranslating, String lyricsTranslationStatus, bool hasLyrics, bool lyricsSearchAttempted, bool isLyricsSynced, List<LyricLine> currentLyricsLines, String currentLyricsText, String? currentLyricsTitle, String lyricsTranslationLanguageCode
});




}
/// @nodoc
class __$LyricsControllerStateCopyWithImpl<$Res>
    implements _$LyricsControllerStateCopyWith<$Res> {
  __$LyricsControllerStateCopyWithImpl(this._self, this._then);

  final _LyricsControllerState _self;
  final $Res Function(_LyricsControllerState) _then;

/// Create a copy of LyricsControllerState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? isLyricsLoading = null,Object? isLyricsTranslating = null,Object? lyricsTranslationStatus = null,Object? hasLyrics = null,Object? lyricsSearchAttempted = null,Object? isLyricsSynced = null,Object? currentLyricsLines = null,Object? currentLyricsText = null,Object? currentLyricsTitle = freezed,Object? lyricsTranslationLanguageCode = null,}) {
  return _then(_LyricsControllerState(
isLyricsLoading: null == isLyricsLoading ? _self.isLyricsLoading : isLyricsLoading // ignore: cast_nullable_to_non_nullable
as bool,isLyricsTranslating: null == isLyricsTranslating ? _self.isLyricsTranslating : isLyricsTranslating // ignore: cast_nullable_to_non_nullable
as bool,lyricsTranslationStatus: null == lyricsTranslationStatus ? _self.lyricsTranslationStatus : lyricsTranslationStatus // ignore: cast_nullable_to_non_nullable
as String,hasLyrics: null == hasLyrics ? _self.hasLyrics : hasLyrics // ignore: cast_nullable_to_non_nullable
as bool,lyricsSearchAttempted: null == lyricsSearchAttempted ? _self.lyricsSearchAttempted : lyricsSearchAttempted // ignore: cast_nullable_to_non_nullable
as bool,isLyricsSynced: null == isLyricsSynced ? _self.isLyricsSynced : isLyricsSynced // ignore: cast_nullable_to_non_nullable
as bool,currentLyricsLines: null == currentLyricsLines ? _self._currentLyricsLines : currentLyricsLines // ignore: cast_nullable_to_non_nullable
as List<LyricLine>,currentLyricsText: null == currentLyricsText ? _self.currentLyricsText : currentLyricsText // ignore: cast_nullable_to_non_nullable
as String,currentLyricsTitle: freezed == currentLyricsTitle ? _self.currentLyricsTitle : currentLyricsTitle // ignore: cast_nullable_to_non_nullable
as String?,lyricsTranslationLanguageCode: null == lyricsTranslationLanguageCode ? _self.lyricsTranslationLanguageCode : lyricsTranslationLanguageCode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
