// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'metadata_database.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SongMetadata {

 int? get id; String get path; String get title; String get album; String get artist; int? get duration; String? get artworkPath; String? get thumbnailPath; int? get artworkWidth; int? get artworkHeight; int? get trackNumber; Uint8List? get themeColorsBlob; Uint8List? get waveformBlob; int? get lastModifiedTime; int? get createdAt; List<String>? get genres;
/// Create a copy of SongMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SongMetadataCopyWith<SongMetadata> get copyWith => _$SongMetadataCopyWithImpl<SongMetadata>(this as SongMetadata, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SongMetadata&&(identical(other.id, id) || other.id == id)&&(identical(other.path, path) || other.path == path)&&(identical(other.title, title) || other.title == title)&&(identical(other.album, album) || other.album == album)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.artworkPath, artworkPath) || other.artworkPath == artworkPath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.artworkWidth, artworkWidth) || other.artworkWidth == artworkWidth)&&(identical(other.artworkHeight, artworkHeight) || other.artworkHeight == artworkHeight)&&(identical(other.trackNumber, trackNumber) || other.trackNumber == trackNumber)&&const DeepCollectionEquality().equals(other.themeColorsBlob, themeColorsBlob)&&const DeepCollectionEquality().equals(other.waveformBlob, waveformBlob)&&(identical(other.lastModifiedTime, lastModifiedTime) || other.lastModifiedTime == lastModifiedTime)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.genres, genres));
}


@override
int get hashCode => Object.hash(runtimeType,id,path,title,album,artist,duration,artworkPath,thumbnailPath,artworkWidth,artworkHeight,trackNumber,const DeepCollectionEquality().hash(themeColorsBlob),const DeepCollectionEquality().hash(waveformBlob),lastModifiedTime,createdAt,const DeepCollectionEquality().hash(genres));

@override
String toString() {
  return 'SongMetadata(id: $id, path: $path, title: $title, album: $album, artist: $artist, duration: $duration, artworkPath: $artworkPath, thumbnailPath: $thumbnailPath, artworkWidth: $artworkWidth, artworkHeight: $artworkHeight, trackNumber: $trackNumber, themeColorsBlob: $themeColorsBlob, waveformBlob: $waveformBlob, lastModifiedTime: $lastModifiedTime, createdAt: $createdAt, genres: $genres)';
}


}

/// @nodoc
abstract mixin class $SongMetadataCopyWith<$Res>  {
  factory $SongMetadataCopyWith(SongMetadata value, $Res Function(SongMetadata) _then) = _$SongMetadataCopyWithImpl;
@useResult
$Res call({
 int? id, String path, String title, String album, String artist, int? duration, String? artworkPath, String? thumbnailPath, int? artworkWidth, int? artworkHeight, int? trackNumber, Uint8List? themeColorsBlob, Uint8List? waveformBlob, int? lastModifiedTime, int? createdAt, List<String>? genres
});




}
/// @nodoc
class _$SongMetadataCopyWithImpl<$Res>
    implements $SongMetadataCopyWith<$Res> {
  _$SongMetadataCopyWithImpl(this._self, this._then);

  final SongMetadata _self;
  final $Res Function(SongMetadata) _then;

/// Create a copy of SongMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = freezed,Object? path = null,Object? title = null,Object? album = null,Object? artist = null,Object? duration = freezed,Object? artworkPath = freezed,Object? thumbnailPath = freezed,Object? artworkWidth = freezed,Object? artworkHeight = freezed,Object? trackNumber = freezed,Object? themeColorsBlob = freezed,Object? waveformBlob = freezed,Object? lastModifiedTime = freezed,Object? createdAt = freezed,Object? genres = freezed,}) {
  return _then(_self.copyWith(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,album: null == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String,artist: null == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int?,artworkPath: freezed == artworkPath ? _self.artworkPath : artworkPath // ignore: cast_nullable_to_non_nullable
as String?,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,artworkWidth: freezed == artworkWidth ? _self.artworkWidth : artworkWidth // ignore: cast_nullable_to_non_nullable
as int?,artworkHeight: freezed == artworkHeight ? _self.artworkHeight : artworkHeight // ignore: cast_nullable_to_non_nullable
as int?,trackNumber: freezed == trackNumber ? _self.trackNumber : trackNumber // ignore: cast_nullable_to_non_nullable
as int?,themeColorsBlob: freezed == themeColorsBlob ? _self.themeColorsBlob : themeColorsBlob // ignore: cast_nullable_to_non_nullable
as Uint8List?,waveformBlob: freezed == waveformBlob ? _self.waveformBlob : waveformBlob // ignore: cast_nullable_to_non_nullable
as Uint8List?,lastModifiedTime: freezed == lastModifiedTime ? _self.lastModifiedTime : lastModifiedTime // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int?,genres: freezed == genres ? _self.genres : genres // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}

}


/// Adds pattern-matching-related methods to [SongMetadata].
extension SongMetadataPatterns on SongMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SongMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SongMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SongMetadata value)  $default,){
final _that = this;
switch (_that) {
case _SongMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SongMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _SongMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int? id,  String path,  String title,  String album,  String artist,  int? duration,  String? artworkPath,  String? thumbnailPath,  int? artworkWidth,  int? artworkHeight,  int? trackNumber,  Uint8List? themeColorsBlob,  Uint8List? waveformBlob,  int? lastModifiedTime,  int? createdAt,  List<String>? genres)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SongMetadata() when $default != null:
return $default(_that.id,_that.path,_that.title,_that.album,_that.artist,_that.duration,_that.artworkPath,_that.thumbnailPath,_that.artworkWidth,_that.artworkHeight,_that.trackNumber,_that.themeColorsBlob,_that.waveformBlob,_that.lastModifiedTime,_that.createdAt,_that.genres);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int? id,  String path,  String title,  String album,  String artist,  int? duration,  String? artworkPath,  String? thumbnailPath,  int? artworkWidth,  int? artworkHeight,  int? trackNumber,  Uint8List? themeColorsBlob,  Uint8List? waveformBlob,  int? lastModifiedTime,  int? createdAt,  List<String>? genres)  $default,) {final _that = this;
switch (_that) {
case _SongMetadata():
return $default(_that.id,_that.path,_that.title,_that.album,_that.artist,_that.duration,_that.artworkPath,_that.thumbnailPath,_that.artworkWidth,_that.artworkHeight,_that.trackNumber,_that.themeColorsBlob,_that.waveformBlob,_that.lastModifiedTime,_that.createdAt,_that.genres);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int? id,  String path,  String title,  String album,  String artist,  int? duration,  String? artworkPath,  String? thumbnailPath,  int? artworkWidth,  int? artworkHeight,  int? trackNumber,  Uint8List? themeColorsBlob,  Uint8List? waveformBlob,  int? lastModifiedTime,  int? createdAt,  List<String>? genres)?  $default,) {final _that = this;
switch (_that) {
case _SongMetadata() when $default != null:
return $default(_that.id,_that.path,_that.title,_that.album,_that.artist,_that.duration,_that.artworkPath,_that.thumbnailPath,_that.artworkWidth,_that.artworkHeight,_that.trackNumber,_that.themeColorsBlob,_that.waveformBlob,_that.lastModifiedTime,_that.createdAt,_that.genres);case _:
  return null;

}
}

}

/// @nodoc


class _SongMetadata extends SongMetadata {
  const _SongMetadata({this.id, required this.path, required this.title, required this.album, required this.artist, this.duration, this.artworkPath, this.thumbnailPath, this.artworkWidth, this.artworkHeight, this.trackNumber, this.themeColorsBlob, this.waveformBlob, this.lastModifiedTime, this.createdAt, final  List<String>? genres}): _genres = genres,super._();
  

@override final  int? id;
@override final  String path;
@override final  String title;
@override final  String album;
@override final  String artist;
@override final  int? duration;
@override final  String? artworkPath;
@override final  String? thumbnailPath;
@override final  int? artworkWidth;
@override final  int? artworkHeight;
@override final  int? trackNumber;
@override final  Uint8List? themeColorsBlob;
@override final  Uint8List? waveformBlob;
@override final  int? lastModifiedTime;
@override final  int? createdAt;
 final  List<String>? _genres;
@override List<String>? get genres {
  final value = _genres;
  if (value == null) return null;
  if (_genres is EqualUnmodifiableListView) return _genres;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}


/// Create a copy of SongMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SongMetadataCopyWith<_SongMetadata> get copyWith => __$SongMetadataCopyWithImpl<_SongMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SongMetadata&&(identical(other.id, id) || other.id == id)&&(identical(other.path, path) || other.path == path)&&(identical(other.title, title) || other.title == title)&&(identical(other.album, album) || other.album == album)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.duration, duration) || other.duration == duration)&&(identical(other.artworkPath, artworkPath) || other.artworkPath == artworkPath)&&(identical(other.thumbnailPath, thumbnailPath) || other.thumbnailPath == thumbnailPath)&&(identical(other.artworkWidth, artworkWidth) || other.artworkWidth == artworkWidth)&&(identical(other.artworkHeight, artworkHeight) || other.artworkHeight == artworkHeight)&&(identical(other.trackNumber, trackNumber) || other.trackNumber == trackNumber)&&const DeepCollectionEquality().equals(other.themeColorsBlob, themeColorsBlob)&&const DeepCollectionEquality().equals(other.waveformBlob, waveformBlob)&&(identical(other.lastModifiedTime, lastModifiedTime) || other.lastModifiedTime == lastModifiedTime)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._genres, _genres));
}


@override
int get hashCode => Object.hash(runtimeType,id,path,title,album,artist,duration,artworkPath,thumbnailPath,artworkWidth,artworkHeight,trackNumber,const DeepCollectionEquality().hash(themeColorsBlob),const DeepCollectionEquality().hash(waveformBlob),lastModifiedTime,createdAt,const DeepCollectionEquality().hash(_genres));

@override
String toString() {
  return 'SongMetadata(id: $id, path: $path, title: $title, album: $album, artist: $artist, duration: $duration, artworkPath: $artworkPath, thumbnailPath: $thumbnailPath, artworkWidth: $artworkWidth, artworkHeight: $artworkHeight, trackNumber: $trackNumber, themeColorsBlob: $themeColorsBlob, waveformBlob: $waveformBlob, lastModifiedTime: $lastModifiedTime, createdAt: $createdAt, genres: $genres)';
}


}

/// @nodoc
abstract mixin class _$SongMetadataCopyWith<$Res> implements $SongMetadataCopyWith<$Res> {
  factory _$SongMetadataCopyWith(_SongMetadata value, $Res Function(_SongMetadata) _then) = __$SongMetadataCopyWithImpl;
@override @useResult
$Res call({
 int? id, String path, String title, String album, String artist, int? duration, String? artworkPath, String? thumbnailPath, int? artworkWidth, int? artworkHeight, int? trackNumber, Uint8List? themeColorsBlob, Uint8List? waveformBlob, int? lastModifiedTime, int? createdAt, List<String>? genres
});




}
/// @nodoc
class __$SongMetadataCopyWithImpl<$Res>
    implements _$SongMetadataCopyWith<$Res> {
  __$SongMetadataCopyWithImpl(this._self, this._then);

  final _SongMetadata _self;
  final $Res Function(_SongMetadata) _then;

/// Create a copy of SongMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = freezed,Object? path = null,Object? title = null,Object? album = null,Object? artist = null,Object? duration = freezed,Object? artworkPath = freezed,Object? thumbnailPath = freezed,Object? artworkWidth = freezed,Object? artworkHeight = freezed,Object? trackNumber = freezed,Object? themeColorsBlob = freezed,Object? waveformBlob = freezed,Object? lastModifiedTime = freezed,Object? createdAt = freezed,Object? genres = freezed,}) {
  return _then(_SongMetadata(
id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int?,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,album: null == album ? _self.album : album // ignore: cast_nullable_to_non_nullable
as String,artist: null == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String,duration: freezed == duration ? _self.duration : duration // ignore: cast_nullable_to_non_nullable
as int?,artworkPath: freezed == artworkPath ? _self.artworkPath : artworkPath // ignore: cast_nullable_to_non_nullable
as String?,thumbnailPath: freezed == thumbnailPath ? _self.thumbnailPath : thumbnailPath // ignore: cast_nullable_to_non_nullable
as String?,artworkWidth: freezed == artworkWidth ? _self.artworkWidth : artworkWidth // ignore: cast_nullable_to_non_nullable
as int?,artworkHeight: freezed == artworkHeight ? _self.artworkHeight : artworkHeight // ignore: cast_nullable_to_non_nullable
as int?,trackNumber: freezed == trackNumber ? _self.trackNumber : trackNumber // ignore: cast_nullable_to_non_nullable
as int?,themeColorsBlob: freezed == themeColorsBlob ? _self.themeColorsBlob : themeColorsBlob // ignore: cast_nullable_to_non_nullable
as Uint8List?,waveformBlob: freezed == waveformBlob ? _self.waveformBlob : waveformBlob // ignore: cast_nullable_to_non_nullable
as Uint8List?,lastModifiedTime: freezed == lastModifiedTime ? _self.lastModifiedTime : lastModifiedTime // ignore: cast_nullable_to_non_nullable
as int?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int?,genres: freezed == genres ? _self._genres : genres // ignore: cast_nullable_to_non_nullable
as List<String>?,
  ));
}


}

// dart format on
