// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'musicbrainz_tag_completion_service.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$MusicBrainzReleaseMatch {

 String get id; String get title; String? get country; String? get dateLabel; int? get trackCount; String? get releaseGroupId; Map<String, dynamic> get raw;
/// Create a copy of MusicBrainzReleaseMatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MusicBrainzReleaseMatchCopyWith<MusicBrainzReleaseMatch> get copyWith => _$MusicBrainzReleaseMatchCopyWithImpl<MusicBrainzReleaseMatch>(this as MusicBrainzReleaseMatch, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MusicBrainzReleaseMatch&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.country, country) || other.country == country)&&(identical(other.dateLabel, dateLabel) || other.dateLabel == dateLabel)&&(identical(other.trackCount, trackCount) || other.trackCount == trackCount)&&(identical(other.releaseGroupId, releaseGroupId) || other.releaseGroupId == releaseGroupId)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,country,dateLabel,trackCount,releaseGroupId,const DeepCollectionEquality().hash(raw));

@override
String toString() {
  return 'MusicBrainzReleaseMatch(id: $id, title: $title, country: $country, dateLabel: $dateLabel, trackCount: $trackCount, releaseGroupId: $releaseGroupId, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $MusicBrainzReleaseMatchCopyWith<$Res>  {
  factory $MusicBrainzReleaseMatchCopyWith(MusicBrainzReleaseMatch value, $Res Function(MusicBrainzReleaseMatch) _then) = _$MusicBrainzReleaseMatchCopyWithImpl;
@useResult
$Res call({
 String id, String title, String? country, String? dateLabel, int? trackCount, String? releaseGroupId, Map<String, dynamic> raw
});




}
/// @nodoc
class _$MusicBrainzReleaseMatchCopyWithImpl<$Res>
    implements $MusicBrainzReleaseMatchCopyWith<$Res> {
  _$MusicBrainzReleaseMatchCopyWithImpl(this._self, this._then);

  final MusicBrainzReleaseMatch _self;
  final $Res Function(MusicBrainzReleaseMatch) _then;

/// Create a copy of MusicBrainzReleaseMatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? country = freezed,Object? dateLabel = freezed,Object? trackCount = freezed,Object? releaseGroupId = freezed,Object? raw = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,dateLabel: freezed == dateLabel ? _self.dateLabel : dateLabel // ignore: cast_nullable_to_non_nullable
as String?,trackCount: freezed == trackCount ? _self.trackCount : trackCount // ignore: cast_nullable_to_non_nullable
as int?,releaseGroupId: freezed == releaseGroupId ? _self.releaseGroupId : releaseGroupId // ignore: cast_nullable_to_non_nullable
as String?,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [MusicBrainzReleaseMatch].
extension MusicBrainzReleaseMatchPatterns on MusicBrainzReleaseMatch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MusicBrainzReleaseMatch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MusicBrainzReleaseMatch() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MusicBrainzReleaseMatch value)  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzReleaseMatch():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MusicBrainzReleaseMatch value)?  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzReleaseMatch() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String? country,  String? dateLabel,  int? trackCount,  String? releaseGroupId,  Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MusicBrainzReleaseMatch() when $default != null:
return $default(_that.id,_that.title,_that.country,_that.dateLabel,_that.trackCount,_that.releaseGroupId,_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String? country,  String? dateLabel,  int? trackCount,  String? releaseGroupId,  Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzReleaseMatch():
return $default(_that.id,_that.title,_that.country,_that.dateLabel,_that.trackCount,_that.releaseGroupId,_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String? country,  String? dateLabel,  int? trackCount,  String? releaseGroupId,  Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzReleaseMatch() when $default != null:
return $default(_that.id,_that.title,_that.country,_that.dateLabel,_that.trackCount,_that.releaseGroupId,_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _MusicBrainzReleaseMatch extends MusicBrainzReleaseMatch {
  const _MusicBrainzReleaseMatch({required this.id, required this.title, required this.country, required this.dateLabel, required this.trackCount, required this.releaseGroupId, required final  Map<String, dynamic> raw}): _raw = raw,super._();
  

@override final  String id;
@override final  String title;
@override final  String? country;
@override final  String? dateLabel;
@override final  int? trackCount;
@override final  String? releaseGroupId;
 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of MusicBrainzReleaseMatch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MusicBrainzReleaseMatchCopyWith<_MusicBrainzReleaseMatch> get copyWith => __$MusicBrainzReleaseMatchCopyWithImpl<_MusicBrainzReleaseMatch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MusicBrainzReleaseMatch&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.country, country) || other.country == country)&&(identical(other.dateLabel, dateLabel) || other.dateLabel == dateLabel)&&(identical(other.trackCount, trackCount) || other.trackCount == trackCount)&&(identical(other.releaseGroupId, releaseGroupId) || other.releaseGroupId == releaseGroupId)&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,country,dateLabel,trackCount,releaseGroupId,const DeepCollectionEquality().hash(_raw));

@override
String toString() {
  return 'MusicBrainzReleaseMatch(id: $id, title: $title, country: $country, dateLabel: $dateLabel, trackCount: $trackCount, releaseGroupId: $releaseGroupId, raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$MusicBrainzReleaseMatchCopyWith<$Res> implements $MusicBrainzReleaseMatchCopyWith<$Res> {
  factory _$MusicBrainzReleaseMatchCopyWith(_MusicBrainzReleaseMatch value, $Res Function(_MusicBrainzReleaseMatch) _then) = __$MusicBrainzReleaseMatchCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String? country, String? dateLabel, int? trackCount, String? releaseGroupId, Map<String, dynamic> raw
});




}
/// @nodoc
class __$MusicBrainzReleaseMatchCopyWithImpl<$Res>
    implements _$MusicBrainzReleaseMatchCopyWith<$Res> {
  __$MusicBrainzReleaseMatchCopyWithImpl(this._self, this._then);

  final _MusicBrainzReleaseMatch _self;
  final $Res Function(_MusicBrainzReleaseMatch) _then;

/// Create a copy of MusicBrainzReleaseMatch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? country = freezed,Object? dateLabel = freezed,Object? trackCount = freezed,Object? releaseGroupId = freezed,Object? raw = null,}) {
  return _then(_MusicBrainzReleaseMatch(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,dateLabel: freezed == dateLabel ? _self.dateLabel : dateLabel // ignore: cast_nullable_to_non_nullable
as String?,trackCount: freezed == trackCount ? _self.trackCount : trackCount // ignore: cast_nullable_to_non_nullable
as int?,releaseGroupId: freezed == releaseGroupId ? _self.releaseGroupId : releaseGroupId // ignore: cast_nullable_to_non_nullable
as String?,raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$MusicBrainzReleaseGroup {

 String get key; String get title; List<MusicBrainzReleaseMatch> get releases;
/// Create a copy of MusicBrainzReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MusicBrainzReleaseGroupCopyWith<MusicBrainzReleaseGroup> get copyWith => _$MusicBrainzReleaseGroupCopyWithImpl<MusicBrainzReleaseGroup>(this as MusicBrainzReleaseGroup, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MusicBrainzReleaseGroup&&(identical(other.key, key) || other.key == key)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other.releases, releases));
}


@override
int get hashCode => Object.hash(runtimeType,key,title,const DeepCollectionEquality().hash(releases));

@override
String toString() {
  return 'MusicBrainzReleaseGroup(key: $key, title: $title, releases: $releases)';
}


}

/// @nodoc
abstract mixin class $MusicBrainzReleaseGroupCopyWith<$Res>  {
  factory $MusicBrainzReleaseGroupCopyWith(MusicBrainzReleaseGroup value, $Res Function(MusicBrainzReleaseGroup) _then) = _$MusicBrainzReleaseGroupCopyWithImpl;
@useResult
$Res call({
 String key, String title, List<MusicBrainzReleaseMatch> releases
});




}
/// @nodoc
class _$MusicBrainzReleaseGroupCopyWithImpl<$Res>
    implements $MusicBrainzReleaseGroupCopyWith<$Res> {
  _$MusicBrainzReleaseGroupCopyWithImpl(this._self, this._then);

  final MusicBrainzReleaseGroup _self;
  final $Res Function(MusicBrainzReleaseGroup) _then;

/// Create a copy of MusicBrainzReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? title = null,Object? releases = null,}) {
  return _then(_self.copyWith(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,releases: null == releases ? _self.releases : releases // ignore: cast_nullable_to_non_nullable
as List<MusicBrainzReleaseMatch>,
  ));
}

}


/// Adds pattern-matching-related methods to [MusicBrainzReleaseGroup].
extension MusicBrainzReleaseGroupPatterns on MusicBrainzReleaseGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MusicBrainzReleaseGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MusicBrainzReleaseGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MusicBrainzReleaseGroup value)  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzReleaseGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MusicBrainzReleaseGroup value)?  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzReleaseGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String key,  String title,  List<MusicBrainzReleaseMatch> releases)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MusicBrainzReleaseGroup() when $default != null:
return $default(_that.key,_that.title,_that.releases);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String key,  String title,  List<MusicBrainzReleaseMatch> releases)  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzReleaseGroup():
return $default(_that.key,_that.title,_that.releases);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String key,  String title,  List<MusicBrainzReleaseMatch> releases)?  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzReleaseGroup() when $default != null:
return $default(_that.key,_that.title,_that.releases);case _:
  return null;

}
}

}

/// @nodoc


class _MusicBrainzReleaseGroup extends MusicBrainzReleaseGroup {
  const _MusicBrainzReleaseGroup({required this.key, required this.title, final  List<MusicBrainzReleaseMatch> releases = const <MusicBrainzReleaseMatch>[]}): _releases = releases,super._();
  

@override final  String key;
@override final  String title;
 final  List<MusicBrainzReleaseMatch> _releases;
@override@JsonKey() List<MusicBrainzReleaseMatch> get releases {
  if (_releases is EqualUnmodifiableListView) return _releases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_releases);
}


/// Create a copy of MusicBrainzReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MusicBrainzReleaseGroupCopyWith<_MusicBrainzReleaseGroup> get copyWith => __$MusicBrainzReleaseGroupCopyWithImpl<_MusicBrainzReleaseGroup>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MusicBrainzReleaseGroup&&(identical(other.key, key) || other.key == key)&&(identical(other.title, title) || other.title == title)&&const DeepCollectionEquality().equals(other._releases, _releases));
}


@override
int get hashCode => Object.hash(runtimeType,key,title,const DeepCollectionEquality().hash(_releases));

@override
String toString() {
  return 'MusicBrainzReleaseGroup(key: $key, title: $title, releases: $releases)';
}


}

/// @nodoc
abstract mixin class _$MusicBrainzReleaseGroupCopyWith<$Res> implements $MusicBrainzReleaseGroupCopyWith<$Res> {
  factory _$MusicBrainzReleaseGroupCopyWith(_MusicBrainzReleaseGroup value, $Res Function(_MusicBrainzReleaseGroup) _then) = __$MusicBrainzReleaseGroupCopyWithImpl;
@override @useResult
$Res call({
 String key, String title, List<MusicBrainzReleaseMatch> releases
});




}
/// @nodoc
class __$MusicBrainzReleaseGroupCopyWithImpl<$Res>
    implements _$MusicBrainzReleaseGroupCopyWith<$Res> {
  __$MusicBrainzReleaseGroupCopyWithImpl(this._self, this._then);

  final _MusicBrainzReleaseGroup _self;
  final $Res Function(_MusicBrainzReleaseGroup) _then;

/// Create a copy of MusicBrainzReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? title = null,Object? releases = null,}) {
  return _then(_MusicBrainzReleaseGroup(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,releases: null == releases ? _self._releases : releases // ignore: cast_nullable_to_non_nullable
as List<MusicBrainzReleaseMatch>,
  ));
}


}

/// @nodoc
mixin _$MusicBrainzTrackMatch {

 String get recordingId; String get title; String get artist; String? get album; String? get releaseId; String? get releaseGroupId; String? get releaseDate; String? get country; int? get durationMillis; int? get trackNumber; int get score; String? get disambiguation; List<MusicBrainzReleaseMatch> get releases; Map<String, dynamic> get raw; ResolvedCover? get resolvedCover;
/// Create a copy of MusicBrainzTrackMatch
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MusicBrainzTrackMatchCopyWith<MusicBrainzTrackMatch> get copyWith => _$MusicBrainzTrackMatchCopyWithImpl<MusicBrainzTrackMatch>(this as MusicBrainzTrackMatch, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MusicBrainzTrackMatch&&(identical(other.recordingId, recordingId) || other.recordingId == recordingId)&&(identical(other.title, title) || other.title == title)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.album, album) || other.album == album)&&(identical(other.releaseId, releaseId) || other.releaseId == releaseId)&&(identical(other.releaseGroupId, releaseGroupId) || other.releaseGroupId == releaseGroupId)&&(identical(other.releaseDate, releaseDate) || other.releaseDate == releaseDate)&&(identical(other.country, country) || other.country == country)&&(identical(other.durationMillis, durationMillis) || other.durationMillis == durationMillis)&&(identical(other.trackNumber, trackNumber) || other.trackNumber == trackNumber)&&(identical(other.score, score) || other.score == score)&&(identical(other.disambiguation, disambiguation) || other.disambiguation == disambiguation)&&const DeepCollectionEquality().equals(other.releases, releases)&&const DeepCollectionEquality().equals(other.raw, raw)&&(identical(other.resolvedCover, resolvedCover) || other.resolvedCover == resolvedCover));
}


@override
int get hashCode => Object.hash(runtimeType,recordingId,title,artist,album,releaseId,releaseGroupId,releaseDate,country,durationMillis,trackNumber,score,disambiguation,const DeepCollectionEquality().hash(releases),const DeepCollectionEquality().hash(raw),resolvedCover);

@override
String toString() {
  return 'MusicBrainzTrackMatch(recordingId: $recordingId, title: $title, artist: $artist, album: $album, releaseId: $releaseId, releaseGroupId: $releaseGroupId, releaseDate: $releaseDate, country: $country, durationMillis: $durationMillis, trackNumber: $trackNumber, score: $score, disambiguation: $disambiguation, releases: $releases, raw: $raw, resolvedCover: $resolvedCover)';
}


}

/// @nodoc
abstract mixin class $MusicBrainzTrackMatchCopyWith<$Res>  {
  factory $MusicBrainzTrackMatchCopyWith(MusicBrainzTrackMatch value, $Res Function(MusicBrainzTrackMatch) _then) = _$MusicBrainzTrackMatchCopyWithImpl;
@useResult
$Res call({
 String recordingId, String title, String artist, String? album, String? releaseId, String? releaseGroupId, String? releaseDate, String? country, int? durationMillis, int? trackNumber, int score, String? disambiguation, List<MusicBrainzReleaseMatch> releases, Map<String, dynamic> raw, ResolvedCover? resolvedCover
});


$ResolvedCoverCopyWith<$Res>? get resolvedCover;

}
/// @nodoc
class _$MusicBrainzTrackMatchCopyWithImpl<$Res>
    implements $MusicBrainzTrackMatchCopyWith<$Res> {
  _$MusicBrainzTrackMatchCopyWithImpl(this._self, this._then);

  final MusicBrainzTrackMatch _self;
  final $Res Function(MusicBrainzTrackMatch) _then;

/// Create a copy of MusicBrainzTrackMatch
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? recordingId = null,Object? title = null,Object? artist = null,Object? album = freezed,Object? releaseId = freezed,Object? releaseGroupId = freezed,Object? releaseDate = freezed,Object? country = freezed,Object? durationMillis = freezed,Object? trackNumber = freezed,Object? score = null,Object? disambiguation = freezed,Object? releases = null,Object? raw = null,Object? resolvedCover = freezed,}) {
  return _then(_self.copyWith(
recordingId: null == recordingId ? _self.recordingId : recordingId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,artist: null == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,releaseId: freezed == releaseId ? _self.releaseId : releaseId // ignore: cast_nullable_to_non_nullable
as String?,releaseGroupId: freezed == releaseGroupId ? _self.releaseGroupId : releaseGroupId // ignore: cast_nullable_to_non_nullable
as String?,releaseDate: freezed == releaseDate ? _self.releaseDate : releaseDate // ignore: cast_nullable_to_non_nullable
as String?,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,durationMillis: freezed == durationMillis ? _self.durationMillis : durationMillis // ignore: cast_nullable_to_non_nullable
as int?,trackNumber: freezed == trackNumber ? _self.trackNumber : trackNumber // ignore: cast_nullable_to_non_nullable
as int?,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as int,disambiguation: freezed == disambiguation ? _self.disambiguation : disambiguation // ignore: cast_nullable_to_non_nullable
as String?,releases: null == releases ? _self.releases : releases // ignore: cast_nullable_to_non_nullable
as List<MusicBrainzReleaseMatch>,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,resolvedCover: freezed == resolvedCover ? _self.resolvedCover : resolvedCover // ignore: cast_nullable_to_non_nullable
as ResolvedCover?,
  ));
}
/// Create a copy of MusicBrainzTrackMatch
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResolvedCoverCopyWith<$Res>? get resolvedCover {
    if (_self.resolvedCover == null) {
    return null;
  }

  return $ResolvedCoverCopyWith<$Res>(_self.resolvedCover!, (value) {
    return _then(_self.copyWith(resolvedCover: value));
  });
}
}


/// Adds pattern-matching-related methods to [MusicBrainzTrackMatch].
extension MusicBrainzTrackMatchPatterns on MusicBrainzTrackMatch {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MusicBrainzTrackMatch value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MusicBrainzTrackMatch() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MusicBrainzTrackMatch value)  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzTrackMatch():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MusicBrainzTrackMatch value)?  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzTrackMatch() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String recordingId,  String title,  String artist,  String? album,  String? releaseId,  String? releaseGroupId,  String? releaseDate,  String? country,  int? durationMillis,  int? trackNumber,  int score,  String? disambiguation,  List<MusicBrainzReleaseMatch> releases,  Map<String, dynamic> raw,  ResolvedCover? resolvedCover)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MusicBrainzTrackMatch() when $default != null:
return $default(_that.recordingId,_that.title,_that.artist,_that.album,_that.releaseId,_that.releaseGroupId,_that.releaseDate,_that.country,_that.durationMillis,_that.trackNumber,_that.score,_that.disambiguation,_that.releases,_that.raw,_that.resolvedCover);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String recordingId,  String title,  String artist,  String? album,  String? releaseId,  String? releaseGroupId,  String? releaseDate,  String? country,  int? durationMillis,  int? trackNumber,  int score,  String? disambiguation,  List<MusicBrainzReleaseMatch> releases,  Map<String, dynamic> raw,  ResolvedCover? resolvedCover)  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzTrackMatch():
return $default(_that.recordingId,_that.title,_that.artist,_that.album,_that.releaseId,_that.releaseGroupId,_that.releaseDate,_that.country,_that.durationMillis,_that.trackNumber,_that.score,_that.disambiguation,_that.releases,_that.raw,_that.resolvedCover);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String recordingId,  String title,  String artist,  String? album,  String? releaseId,  String? releaseGroupId,  String? releaseDate,  String? country,  int? durationMillis,  int? trackNumber,  int score,  String? disambiguation,  List<MusicBrainzReleaseMatch> releases,  Map<String, dynamic> raw,  ResolvedCover? resolvedCover)?  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzTrackMatch() when $default != null:
return $default(_that.recordingId,_that.title,_that.artist,_that.album,_that.releaseId,_that.releaseGroupId,_that.releaseDate,_that.country,_that.durationMillis,_that.trackNumber,_that.score,_that.disambiguation,_that.releases,_that.raw,_that.resolvedCover);case _:
  return null;

}
}

}

/// @nodoc


class _MusicBrainzTrackMatch extends MusicBrainzTrackMatch {
  const _MusicBrainzTrackMatch({required this.recordingId, required this.title, required this.artist, required this.album, required this.releaseId, required this.releaseGroupId, required this.releaseDate, required this.country, required this.durationMillis, required this.trackNumber, required this.score, required this.disambiguation, final  List<MusicBrainzReleaseMatch> releases = const <MusicBrainzReleaseMatch>[], required final  Map<String, dynamic> raw, required this.resolvedCover}): _releases = releases,_raw = raw,super._();
  

@override final  String recordingId;
@override final  String title;
@override final  String artist;
@override final  String? album;
@override final  String? releaseId;
@override final  String? releaseGroupId;
@override final  String? releaseDate;
@override final  String? country;
@override final  int? durationMillis;
@override final  int? trackNumber;
@override final  int score;
@override final  String? disambiguation;
 final  List<MusicBrainzReleaseMatch> _releases;
@override@JsonKey() List<MusicBrainzReleaseMatch> get releases {
  if (_releases is EqualUnmodifiableListView) return _releases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_releases);
}

 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}

@override final  ResolvedCover? resolvedCover;

/// Create a copy of MusicBrainzTrackMatch
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MusicBrainzTrackMatchCopyWith<_MusicBrainzTrackMatch> get copyWith => __$MusicBrainzTrackMatchCopyWithImpl<_MusicBrainzTrackMatch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MusicBrainzTrackMatch&&(identical(other.recordingId, recordingId) || other.recordingId == recordingId)&&(identical(other.title, title) || other.title == title)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.album, album) || other.album == album)&&(identical(other.releaseId, releaseId) || other.releaseId == releaseId)&&(identical(other.releaseGroupId, releaseGroupId) || other.releaseGroupId == releaseGroupId)&&(identical(other.releaseDate, releaseDate) || other.releaseDate == releaseDate)&&(identical(other.country, country) || other.country == country)&&(identical(other.durationMillis, durationMillis) || other.durationMillis == durationMillis)&&(identical(other.trackNumber, trackNumber) || other.trackNumber == trackNumber)&&(identical(other.score, score) || other.score == score)&&(identical(other.disambiguation, disambiguation) || other.disambiguation == disambiguation)&&const DeepCollectionEquality().equals(other._releases, _releases)&&const DeepCollectionEquality().equals(other._raw, _raw)&&(identical(other.resolvedCover, resolvedCover) || other.resolvedCover == resolvedCover));
}


@override
int get hashCode => Object.hash(runtimeType,recordingId,title,artist,album,releaseId,releaseGroupId,releaseDate,country,durationMillis,trackNumber,score,disambiguation,const DeepCollectionEquality().hash(_releases),const DeepCollectionEquality().hash(_raw),resolvedCover);

@override
String toString() {
  return 'MusicBrainzTrackMatch(recordingId: $recordingId, title: $title, artist: $artist, album: $album, releaseId: $releaseId, releaseGroupId: $releaseGroupId, releaseDate: $releaseDate, country: $country, durationMillis: $durationMillis, trackNumber: $trackNumber, score: $score, disambiguation: $disambiguation, releases: $releases, raw: $raw, resolvedCover: $resolvedCover)';
}


}

/// @nodoc
abstract mixin class _$MusicBrainzTrackMatchCopyWith<$Res> implements $MusicBrainzTrackMatchCopyWith<$Res> {
  factory _$MusicBrainzTrackMatchCopyWith(_MusicBrainzTrackMatch value, $Res Function(_MusicBrainzTrackMatch) _then) = __$MusicBrainzTrackMatchCopyWithImpl;
@override @useResult
$Res call({
 String recordingId, String title, String artist, String? album, String? releaseId, String? releaseGroupId, String? releaseDate, String? country, int? durationMillis, int? trackNumber, int score, String? disambiguation, List<MusicBrainzReleaseMatch> releases, Map<String, dynamic> raw, ResolvedCover? resolvedCover
});


@override $ResolvedCoverCopyWith<$Res>? get resolvedCover;

}
/// @nodoc
class __$MusicBrainzTrackMatchCopyWithImpl<$Res>
    implements _$MusicBrainzTrackMatchCopyWith<$Res> {
  __$MusicBrainzTrackMatchCopyWithImpl(this._self, this._then);

  final _MusicBrainzTrackMatch _self;
  final $Res Function(_MusicBrainzTrackMatch) _then;

/// Create a copy of MusicBrainzTrackMatch
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? recordingId = null,Object? title = null,Object? artist = null,Object? album = freezed,Object? releaseId = freezed,Object? releaseGroupId = freezed,Object? releaseDate = freezed,Object? country = freezed,Object? durationMillis = freezed,Object? trackNumber = freezed,Object? score = null,Object? disambiguation = freezed,Object? releases = null,Object? raw = null,Object? resolvedCover = freezed,}) {
  return _then(_MusicBrainzTrackMatch(
recordingId: null == recordingId ? _self.recordingId : recordingId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,artist: null == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String,album: freezed == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String?,releaseId: freezed == releaseId ? _self.releaseId : releaseId // ignore: cast_nullable_to_non_nullable
as String?,releaseGroupId: freezed == releaseGroupId ? _self.releaseGroupId : releaseGroupId // ignore: cast_nullable_to_non_nullable
as String?,releaseDate: freezed == releaseDate ? _self.releaseDate : releaseDate // ignore: cast_nullable_to_non_nullable
as String?,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,durationMillis: freezed == durationMillis ? _self.durationMillis : durationMillis // ignore: cast_nullable_to_non_nullable
as int?,trackNumber: freezed == trackNumber ? _self.trackNumber : trackNumber // ignore: cast_nullable_to_non_nullable
as int?,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as int,disambiguation: freezed == disambiguation ? _self.disambiguation : disambiguation // ignore: cast_nullable_to_non_nullable
as String?,releases: null == releases ? _self._releases : releases // ignore: cast_nullable_to_non_nullable
as List<MusicBrainzReleaseMatch>,raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,resolvedCover: freezed == resolvedCover ? _self.resolvedCover : resolvedCover // ignore: cast_nullable_to_non_nullable
as ResolvedCover?,
  ));
}

/// Create a copy of MusicBrainzTrackMatch
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ResolvedCoverCopyWith<$Res>? get resolvedCover {
    if (_self.resolvedCover == null) {
    return null;
  }

  return $ResolvedCoverCopyWith<$Res>(_self.resolvedCover!, (value) {
    return _then(_self.copyWith(resolvedCover: value));
  });
}
}

/// @nodoc
mixin _$ResolvedCover {

 String get endpoint; String get id; String? get largeUrl; String? get thumbnailUrl;
/// Create a copy of ResolvedCover
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ResolvedCoverCopyWith<ResolvedCover> get copyWith => _$ResolvedCoverCopyWithImpl<ResolvedCover>(this as ResolvedCover, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ResolvedCover&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.id, id) || other.id == id)&&(identical(other.largeUrl, largeUrl) || other.largeUrl == largeUrl)&&(identical(other.thumbnailUrl, thumbnailUrl) || other.thumbnailUrl == thumbnailUrl));
}


@override
int get hashCode => Object.hash(runtimeType,endpoint,id,largeUrl,thumbnailUrl);

@override
String toString() {
  return 'ResolvedCover(endpoint: $endpoint, id: $id, largeUrl: $largeUrl, thumbnailUrl: $thumbnailUrl)';
}


}

/// @nodoc
abstract mixin class $ResolvedCoverCopyWith<$Res>  {
  factory $ResolvedCoverCopyWith(ResolvedCover value, $Res Function(ResolvedCover) _then) = _$ResolvedCoverCopyWithImpl;
@useResult
$Res call({
 String endpoint, String id, String? largeUrl, String? thumbnailUrl
});




}
/// @nodoc
class _$ResolvedCoverCopyWithImpl<$Res>
    implements $ResolvedCoverCopyWith<$Res> {
  _$ResolvedCoverCopyWithImpl(this._self, this._then);

  final ResolvedCover _self;
  final $Res Function(ResolvedCover) _then;

/// Create a copy of ResolvedCover
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? endpoint = null,Object? id = null,Object? largeUrl = freezed,Object? thumbnailUrl = freezed,}) {
  return _then(_self.copyWith(
endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,largeUrl: freezed == largeUrl ? _self.largeUrl : largeUrl // ignore: cast_nullable_to_non_nullable
as String?,thumbnailUrl: freezed == thumbnailUrl ? _self.thumbnailUrl : thumbnailUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ResolvedCover].
extension ResolvedCoverPatterns on ResolvedCover {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ResolvedCover value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ResolvedCover() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ResolvedCover value)  $default,){
final _that = this;
switch (_that) {
case _ResolvedCover():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ResolvedCover value)?  $default,){
final _that = this;
switch (_that) {
case _ResolvedCover() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String endpoint,  String id,  String? largeUrl,  String? thumbnailUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ResolvedCover() when $default != null:
return $default(_that.endpoint,_that.id,_that.largeUrl,_that.thumbnailUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String endpoint,  String id,  String? largeUrl,  String? thumbnailUrl)  $default,) {final _that = this;
switch (_that) {
case _ResolvedCover():
return $default(_that.endpoint,_that.id,_that.largeUrl,_that.thumbnailUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String endpoint,  String id,  String? largeUrl,  String? thumbnailUrl)?  $default,) {final _that = this;
switch (_that) {
case _ResolvedCover() when $default != null:
return $default(_that.endpoint,_that.id,_that.largeUrl,_that.thumbnailUrl);case _:
  return null;

}
}

}

/// @nodoc


class _ResolvedCover extends ResolvedCover {
  const _ResolvedCover({required this.endpoint, required this.id, this.largeUrl, this.thumbnailUrl}): super._();
  

@override final  String endpoint;
@override final  String id;
@override final  String? largeUrl;
@override final  String? thumbnailUrl;

/// Create a copy of ResolvedCover
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ResolvedCoverCopyWith<_ResolvedCover> get copyWith => __$ResolvedCoverCopyWithImpl<_ResolvedCover>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ResolvedCover&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.id, id) || other.id == id)&&(identical(other.largeUrl, largeUrl) || other.largeUrl == largeUrl)&&(identical(other.thumbnailUrl, thumbnailUrl) || other.thumbnailUrl == thumbnailUrl));
}


@override
int get hashCode => Object.hash(runtimeType,endpoint,id,largeUrl,thumbnailUrl);

@override
String toString() {
  return 'ResolvedCover(endpoint: $endpoint, id: $id, largeUrl: $largeUrl, thumbnailUrl: $thumbnailUrl)';
}


}

/// @nodoc
abstract mixin class _$ResolvedCoverCopyWith<$Res> implements $ResolvedCoverCopyWith<$Res> {
  factory _$ResolvedCoverCopyWith(_ResolvedCover value, $Res Function(_ResolvedCover) _then) = __$ResolvedCoverCopyWithImpl;
@override @useResult
$Res call({
 String endpoint, String id, String? largeUrl, String? thumbnailUrl
});




}
/// @nodoc
class __$ResolvedCoverCopyWithImpl<$Res>
    implements _$ResolvedCoverCopyWith<$Res> {
  __$ResolvedCoverCopyWithImpl(this._self, this._then);

  final _ResolvedCover _self;
  final $Res Function(_ResolvedCover) _then;

/// Create a copy of ResolvedCover
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? endpoint = null,Object? id = null,Object? largeUrl = freezed,Object? thumbnailUrl = freezed,}) {
  return _then(_ResolvedCover(
endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,largeUrl: freezed == largeUrl ? _self.largeUrl : largeUrl // ignore: cast_nullable_to_non_nullable
as String?,thumbnailUrl: freezed == thumbnailUrl ? _self.thumbnailUrl : thumbnailUrl // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$MusicBrainzTagSelectionResult {

 SongMetadata get metadata; Uint8List? get artworkBytes; String? get thumbnailPath; MusicBrainzTrackMatch get match;
/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MusicBrainzTagSelectionResultCopyWith<MusicBrainzTagSelectionResult> get copyWith => _$MusicBrainzTagSelectionResultCopyWithImpl<MusicBrainzTagSelectionResult>(this as MusicBrainzTagSelectionResult, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is MusicBrainzTagSelectionResult&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.artworkBytes, artworkBytes)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.match, match) || other.match == match));
}


@override
int get hashCode => Object.hash(runtimeType,metadata,const DeepCollectionEquality().hash(artworkBytes),thumbnailPath,match);

@override
String toString() {
  return 'MusicBrainzTagSelectionResult(metadata: $metadata, artworkBytes: $artworkBytes, thumbnailPath: $thumbnailPath, match: $match)';
}


}

/// @nodoc
abstract mixin class $MusicBrainzTagSelectionResultCopyWith<$Res>  {
  factory $MusicBrainzTagSelectionResultCopyWith(MusicBrainzTagSelectionResult value, $Res Function(MusicBrainzTagSelectionResult) _then) = _$MusicBrainzTagSelectionResultCopyWithImpl;
@useResult
$Res call({
 SongMetadata metadata, Uint8List? artworkBytes, String? thumbnailPath, MusicBrainzTrackMatch match
});


$SongMetadataCopyWith<$Res> get metadata;$MusicBrainzTrackMatchCopyWith<$Res> get match;

}
/// @nodoc
class _$MusicBrainzTagSelectionResultCopyWithImpl<$Res>
    implements $MusicBrainzTagSelectionResultCopyWith<$Res> {
  _$MusicBrainzTagSelectionResultCopyWithImpl(this._self, this._then);

  final MusicBrainzTagSelectionResult _self;
  final $Res Function(MusicBrainzTagSelectionResult) _then;

/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? metadata = null,Object? artworkBytes = freezed,Object? thumbnailPath = freezed,Object? match = null,}) {
  return _then(_self.copyWith(
metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as SongMetadata,artworkBytes: freezed == artworkBytes ? _self.artworkBytes : artworkBytes // ignore: cast_nullable_to_non_nullable
as Uint8List?,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,match: null == match ? _self.match : match // ignore: cast_nullable_to_non_nullable
as MusicBrainzTrackMatch,
  ));
}
/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SongMetadataCopyWith<$Res> get metadata {
  
  return $SongMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MusicBrainzTrackMatchCopyWith<$Res> get match {
  
  return $MusicBrainzTrackMatchCopyWith<$Res>(_self.match, (value) {
    return _then(_self.copyWith(match: value));
  });
}
}


/// Adds pattern-matching-related methods to [MusicBrainzTagSelectionResult].
extension MusicBrainzTagSelectionResultPatterns on MusicBrainzTagSelectionResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _MusicBrainzTagSelectionResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _MusicBrainzTagSelectionResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _MusicBrainzTagSelectionResult value)  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzTagSelectionResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _MusicBrainzTagSelectionResult value)?  $default,){
final _that = this;
switch (_that) {
case _MusicBrainzTagSelectionResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SongMetadata metadata,  Uint8List? artworkBytes,  String? thumbnailPath,  MusicBrainzTrackMatch match)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _MusicBrainzTagSelectionResult() when $default != null:
return $default(_that.metadata,_that.artworkBytes,_that.thumbnailPath,_that.match);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SongMetadata metadata,  Uint8List? artworkBytes,  String? thumbnailPath,  MusicBrainzTrackMatch match)  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzTagSelectionResult():
return $default(_that.metadata,_that.artworkBytes,_that.thumbnailPath,_that.match);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SongMetadata metadata,  Uint8List? artworkBytes,  String? thumbnailPath,  MusicBrainzTrackMatch match)?  $default,) {final _that = this;
switch (_that) {
case _MusicBrainzTagSelectionResult() when $default != null:
return $default(_that.metadata,_that.artworkBytes,_that.thumbnailPath,_that.match);case _:
  return null;

}
}

}

/// @nodoc


class _MusicBrainzTagSelectionResult extends MusicBrainzTagSelectionResult {
  const _MusicBrainzTagSelectionResult({required this.metadata, required this.artworkBytes, this.thumbnailPath, required this.match}): super._();
  

@override final  SongMetadata metadata;
@override final  Uint8List? artworkBytes;
@override final  String? thumbnailPath;
@override final  MusicBrainzTrackMatch match;

/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$MusicBrainzTagSelectionResultCopyWith<_MusicBrainzTagSelectionResult> get copyWith => __$MusicBrainzTagSelectionResultCopyWithImpl<_MusicBrainzTagSelectionResult>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _MusicBrainzTagSelectionResult&&(identical(other.metadata, metadata) || other.metadata == metadata)&&const DeepCollectionEquality().equals(other.artworkBytes, artworkBytes)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.match, match) || other.match == match));
}


@override
int get hashCode => Object.hash(runtimeType,metadata,const DeepCollectionEquality().hash(artworkBytes),thumbnailPath,match);

@override
String toString() {
  return 'MusicBrainzTagSelectionResult(metadata: $metadata, artworkBytes: $artworkBytes, thumbnailPath: $thumbnailPath, match: $match)';
}


}

/// @nodoc
abstract mixin class _$MusicBrainzTagSelectionResultCopyWith<$Res> implements $MusicBrainzTagSelectionResultCopyWith<$Res> {
  factory _$MusicBrainzTagSelectionResultCopyWith(_MusicBrainzTagSelectionResult value, $Res Function(_MusicBrainzTagSelectionResult) _then) = __$MusicBrainzTagSelectionResultCopyWithImpl;
@override @useResult
$Res call({
 SongMetadata metadata, Uint8List? artworkBytes, String? thumbnailPath, MusicBrainzTrackMatch match
});


@override $SongMetadataCopyWith<$Res> get metadata;@override $MusicBrainzTrackMatchCopyWith<$Res> get match;

}
/// @nodoc
class __$MusicBrainzTagSelectionResultCopyWithImpl<$Res>
    implements _$MusicBrainzTagSelectionResultCopyWith<$Res> {
  __$MusicBrainzTagSelectionResultCopyWithImpl(this._self, this._then);

  final _MusicBrainzTagSelectionResult _self;
  final $Res Function(_MusicBrainzTagSelectionResult) _then;

/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? metadata = null,Object? artworkBytes = freezed,Object? thumbnailPath = freezed,Object? match = null,}) {
  return _then(_MusicBrainzTagSelectionResult(
metadata: null == metadata ? _self.metadata : metadata // ignore: cast_nullable_to_non_nullable
as SongMetadata,artworkBytes: freezed == artworkBytes ? _self.artworkBytes : artworkBytes // ignore: cast_nullable_to_non_nullable
as Uint8List?,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,match: null == match ? _self.match : match // ignore: cast_nullable_to_non_nullable
as MusicBrainzTrackMatch,
  ));
}

/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SongMetadataCopyWith<$Res> get metadata {
  
  return $SongMetadataCopyWith<$Res>(_self.metadata, (value) {
    return _then(_self.copyWith(metadata: value));
  });
}/// Create a copy of MusicBrainzTagSelectionResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MusicBrainzTrackMatchCopyWith<$Res> get match {
  
  return $MusicBrainzTrackMatchCopyWith<$Res>(_self.match, (value) {
    return _then(_self.copyWith(match: value));
  });
}
}

// dart format on
