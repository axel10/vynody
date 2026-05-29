// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acoustid_service.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcoustIDArtist implements DiagnosticableTreeMixin {

 String get id; String get name;
/// Create a copy of AcoustIDArtist
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcoustIDArtistCopyWith<AcoustIDArtist> get copyWith => _$AcoustIDArtistCopyWithImpl<AcoustIDArtist>(this as AcoustIDArtist, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDArtist'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('name', name));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcoustIDArtist&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,id,name);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDArtist(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class $AcoustIDArtistCopyWith<$Res>  {
  factory $AcoustIDArtistCopyWith(AcoustIDArtist value, $Res Function(AcoustIDArtist) _then) = _$AcoustIDArtistCopyWithImpl;
@useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class _$AcoustIDArtistCopyWithImpl<$Res>
    implements $AcoustIDArtistCopyWith<$Res> {
  _$AcoustIDArtistCopyWithImpl(this._self, this._then);

  final AcoustIDArtist _self;
  final $Res Function(AcoustIDArtist) _then;

/// Create a copy of AcoustIDArtist
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AcoustIDArtist].
extension AcoustIDArtistPatterns on AcoustIDArtist {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcoustIDArtist value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcoustIDArtist() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcoustIDArtist value)  $default,){
final _that = this;
switch (_that) {
case _AcoustIDArtist():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcoustIDArtist value)?  $default,){
final _that = this;
switch (_that) {
case _AcoustIDArtist() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcoustIDArtist() when $default != null:
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name)  $default,) {final _that = this;
switch (_that) {
case _AcoustIDArtist():
return $default(_that.id,_that.name);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name)?  $default,) {final _that = this;
switch (_that) {
case _AcoustIDArtist() when $default != null:
return $default(_that.id,_that.name);case _:
  return null;

}
}

}

/// @nodoc


class _AcoustIDArtist extends AcoustIDArtist with DiagnosticableTreeMixin {
  const _AcoustIDArtist({required this.id, required this.name}): super._();
  

@override final  String id;
@override final  String name;

/// Create a copy of AcoustIDArtist
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcoustIDArtistCopyWith<_AcoustIDArtist> get copyWith => __$AcoustIDArtistCopyWithImpl<_AcoustIDArtist>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDArtist'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('name', name));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcoustIDArtist&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name));
}


@override
int get hashCode => Object.hash(runtimeType,id,name);

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDArtist(id: $id, name: $name)';
}


}

/// @nodoc
abstract mixin class _$AcoustIDArtistCopyWith<$Res> implements $AcoustIDArtistCopyWith<$Res> {
  factory _$AcoustIDArtistCopyWith(_AcoustIDArtist value, $Res Function(_AcoustIDArtist) _then) = __$AcoustIDArtistCopyWithImpl;
@override @useResult
$Res call({
 String id, String name
});




}
/// @nodoc
class __$AcoustIDArtistCopyWithImpl<$Res>
    implements _$AcoustIDArtistCopyWith<$Res> {
  __$AcoustIDArtistCopyWithImpl(this._self, this._then);

  final _AcoustIDArtist _self;
  final $Res Function(_AcoustIDArtist) _then;

/// Create a copy of AcoustIDArtist
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,}) {
  return _then(_AcoustIDArtist(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AcoustIDRelease implements DiagnosticableTreeMixin {

 String get id; String get title; String? get country; String? get dateLabel; int? get trackCount; Map<String, dynamic> get raw;
/// Create a copy of AcoustIDRelease
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcoustIDReleaseCopyWith<AcoustIDRelease> get copyWith => _$AcoustIDReleaseCopyWithImpl<AcoustIDRelease>(this as AcoustIDRelease, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDRelease'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('country', country))..add(DiagnosticsProperty('dateLabel', dateLabel))..add(DiagnosticsProperty('trackCount', trackCount))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcoustIDRelease&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.country, country) || other.country == country)&&(identical(other.dateLabel, dateLabel) || other.dateLabel == dateLabel)&&(identical(other.trackCount, trackCount) || other.trackCount == trackCount)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,country,dateLabel,trackCount,const DeepCollectionEquality().hash(raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDRelease(id: $id, title: $title, country: $country, dateLabel: $dateLabel, trackCount: $trackCount, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $AcoustIDReleaseCopyWith<$Res>  {
  factory $AcoustIDReleaseCopyWith(AcoustIDRelease value, $Res Function(AcoustIDRelease) _then) = _$AcoustIDReleaseCopyWithImpl;
@useResult
$Res call({
 String id, String title, String? country, String? dateLabel, int? trackCount, Map<String, dynamic> raw
});




}
/// @nodoc
class _$AcoustIDReleaseCopyWithImpl<$Res>
    implements $AcoustIDReleaseCopyWith<$Res> {
  _$AcoustIDReleaseCopyWithImpl(this._self, this._then);

  final AcoustIDRelease _self;
  final $Res Function(AcoustIDRelease) _then;

/// Create a copy of AcoustIDRelease
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? country = freezed,Object? dateLabel = freezed,Object? trackCount = freezed,Object? raw = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,dateLabel: freezed == dateLabel ? _self.dateLabel : dateLabel // ignore: cast_nullable_to_non_nullable
as String?,trackCount: freezed == trackCount ? _self.trackCount : trackCount // ignore: cast_nullable_to_non_nullable
as int?,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [AcoustIDRelease].
extension AcoustIDReleasePatterns on AcoustIDRelease {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcoustIDRelease value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcoustIDRelease() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcoustIDRelease value)  $default,){
final _that = this;
switch (_that) {
case _AcoustIDRelease():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcoustIDRelease value)?  $default,){
final _that = this;
switch (_that) {
case _AcoustIDRelease() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String? country,  String? dateLabel,  int? trackCount,  Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcoustIDRelease() when $default != null:
return $default(_that.id,_that.title,_that.country,_that.dateLabel,_that.trackCount,_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String? country,  String? dateLabel,  int? trackCount,  Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _AcoustIDRelease():
return $default(_that.id,_that.title,_that.country,_that.dateLabel,_that.trackCount,_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String? country,  String? dateLabel,  int? trackCount,  Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _AcoustIDRelease() when $default != null:
return $default(_that.id,_that.title,_that.country,_that.dateLabel,_that.trackCount,_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _AcoustIDRelease extends AcoustIDRelease with DiagnosticableTreeMixin {
  const _AcoustIDRelease({required this.id, required this.title, this.country, this.dateLabel, this.trackCount, required final  Map<String, dynamic> raw}): _raw = raw,super._();
  

@override final  String id;
@override final  String title;
@override final  String? country;
@override final  String? dateLabel;
@override final  int? trackCount;
 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of AcoustIDRelease
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcoustIDReleaseCopyWith<_AcoustIDRelease> get copyWith => __$AcoustIDReleaseCopyWithImpl<_AcoustIDRelease>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDRelease'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('country', country))..add(DiagnosticsProperty('dateLabel', dateLabel))..add(DiagnosticsProperty('trackCount', trackCount))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcoustIDRelease&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.country, country) || other.country == country)&&(identical(other.dateLabel, dateLabel) || other.dateLabel == dateLabel)&&(identical(other.trackCount, trackCount) || other.trackCount == trackCount)&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,country,dateLabel,trackCount,const DeepCollectionEquality().hash(_raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDRelease(id: $id, title: $title, country: $country, dateLabel: $dateLabel, trackCount: $trackCount, raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$AcoustIDReleaseCopyWith<$Res> implements $AcoustIDReleaseCopyWith<$Res> {
  factory _$AcoustIDReleaseCopyWith(_AcoustIDRelease value, $Res Function(_AcoustIDRelease) _then) = __$AcoustIDReleaseCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String? country, String? dateLabel, int? trackCount, Map<String, dynamic> raw
});




}
/// @nodoc
class __$AcoustIDReleaseCopyWithImpl<$Res>
    implements _$AcoustIDReleaseCopyWith<$Res> {
  __$AcoustIDReleaseCopyWithImpl(this._self, this._then);

  final _AcoustIDRelease _self;
  final $Res Function(_AcoustIDRelease) _then;

/// Create a copy of AcoustIDRelease
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? country = freezed,Object? dateLabel = freezed,Object? trackCount = freezed,Object? raw = null,}) {
  return _then(_AcoustIDRelease(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,country: freezed == country ? _self.country : country // ignore: cast_nullable_to_non_nullable
as String?,dateLabel: freezed == dateLabel ? _self.dateLabel : dateLabel // ignore: cast_nullable_to_non_nullable
as String?,trackCount: freezed == trackCount ? _self.trackCount : trackCount // ignore: cast_nullable_to_non_nullable
as int?,raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$AcoustIDReleaseGroup implements DiagnosticableTreeMixin {

 String get id; String get title; String? get type; List<String> get secondaryTypes; List<AcoustIDRelease> get releases; Map<String, dynamic> get raw;
/// Create a copy of AcoustIDReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcoustIDReleaseGroupCopyWith<AcoustIDReleaseGroup> get copyWith => _$AcoustIDReleaseGroupCopyWithImpl<AcoustIDReleaseGroup>(this as AcoustIDReleaseGroup, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDReleaseGroup'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('type', type))..add(DiagnosticsProperty('secondaryTypes', secondaryTypes))..add(DiagnosticsProperty('releases', releases))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcoustIDReleaseGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.secondaryTypes, secondaryTypes)&&const DeepCollectionEquality().equals(other.releases, releases)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,type,const DeepCollectionEquality().hash(secondaryTypes),const DeepCollectionEquality().hash(releases),const DeepCollectionEquality().hash(raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDReleaseGroup(id: $id, title: $title, type: $type, secondaryTypes: $secondaryTypes, releases: $releases, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $AcoustIDReleaseGroupCopyWith<$Res>  {
  factory $AcoustIDReleaseGroupCopyWith(AcoustIDReleaseGroup value, $Res Function(AcoustIDReleaseGroup) _then) = _$AcoustIDReleaseGroupCopyWithImpl;
@useResult
$Res call({
 String id, String title, String? type, List<String> secondaryTypes, List<AcoustIDRelease> releases, Map<String, dynamic> raw
});




}
/// @nodoc
class _$AcoustIDReleaseGroupCopyWithImpl<$Res>
    implements $AcoustIDReleaseGroupCopyWith<$Res> {
  _$AcoustIDReleaseGroupCopyWithImpl(this._self, this._then);

  final AcoustIDReleaseGroup _self;
  final $Res Function(AcoustIDReleaseGroup) _then;

/// Create a copy of AcoustIDReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? type = freezed,Object? secondaryTypes = null,Object? releases = null,Object? raw = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,secondaryTypes: null == secondaryTypes ? _self.secondaryTypes : secondaryTypes // ignore: cast_nullable_to_non_nullable
as List<String>,releases: null == releases ? _self.releases : releases // ignore: cast_nullable_to_non_nullable
as List<AcoustIDRelease>,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [AcoustIDReleaseGroup].
extension AcoustIDReleaseGroupPatterns on AcoustIDReleaseGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcoustIDReleaseGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcoustIDReleaseGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcoustIDReleaseGroup value)  $default,){
final _that = this;
switch (_that) {
case _AcoustIDReleaseGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcoustIDReleaseGroup value)?  $default,){
final _that = this;
switch (_that) {
case _AcoustIDReleaseGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String? type,  List<String> secondaryTypes,  List<AcoustIDRelease> releases,  Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcoustIDReleaseGroup() when $default != null:
return $default(_that.id,_that.title,_that.type,_that.secondaryTypes,_that.releases,_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String? type,  List<String> secondaryTypes,  List<AcoustIDRelease> releases,  Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _AcoustIDReleaseGroup():
return $default(_that.id,_that.title,_that.type,_that.secondaryTypes,_that.releases,_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String? type,  List<String> secondaryTypes,  List<AcoustIDRelease> releases,  Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _AcoustIDReleaseGroup() when $default != null:
return $default(_that.id,_that.title,_that.type,_that.secondaryTypes,_that.releases,_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _AcoustIDReleaseGroup extends AcoustIDReleaseGroup with DiagnosticableTreeMixin {
  const _AcoustIDReleaseGroup({required this.id, required this.title, this.type, final  List<String> secondaryTypes = const <String>[], final  List<AcoustIDRelease> releases = const <AcoustIDRelease>[], required final  Map<String, dynamic> raw}): _secondaryTypes = secondaryTypes,_releases = releases,_raw = raw,super._();
  

@override final  String id;
@override final  String title;
@override final  String? type;
 final  List<String> _secondaryTypes;
@override@JsonKey() List<String> get secondaryTypes {
  if (_secondaryTypes is EqualUnmodifiableListView) return _secondaryTypes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_secondaryTypes);
}

 final  List<AcoustIDRelease> _releases;
@override@JsonKey() List<AcoustIDRelease> get releases {
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


/// Create a copy of AcoustIDReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcoustIDReleaseGroupCopyWith<_AcoustIDReleaseGroup> get copyWith => __$AcoustIDReleaseGroupCopyWithImpl<_AcoustIDReleaseGroup>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDReleaseGroup'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('type', type))..add(DiagnosticsProperty('secondaryTypes', secondaryTypes))..add(DiagnosticsProperty('releases', releases))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcoustIDReleaseGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other._secondaryTypes, _secondaryTypes)&&const DeepCollectionEquality().equals(other._releases, _releases)&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,type,const DeepCollectionEquality().hash(_secondaryTypes),const DeepCollectionEquality().hash(_releases),const DeepCollectionEquality().hash(_raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDReleaseGroup(id: $id, title: $title, type: $type, secondaryTypes: $secondaryTypes, releases: $releases, raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$AcoustIDReleaseGroupCopyWith<$Res> implements $AcoustIDReleaseGroupCopyWith<$Res> {
  factory _$AcoustIDReleaseGroupCopyWith(_AcoustIDReleaseGroup value, $Res Function(_AcoustIDReleaseGroup) _then) = __$AcoustIDReleaseGroupCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String? type, List<String> secondaryTypes, List<AcoustIDRelease> releases, Map<String, dynamic> raw
});




}
/// @nodoc
class __$AcoustIDReleaseGroupCopyWithImpl<$Res>
    implements _$AcoustIDReleaseGroupCopyWith<$Res> {
  __$AcoustIDReleaseGroupCopyWithImpl(this._self, this._then);

  final _AcoustIDReleaseGroup _self;
  final $Res Function(_AcoustIDReleaseGroup) _then;

/// Create a copy of AcoustIDReleaseGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? type = freezed,Object? secondaryTypes = null,Object? releases = null,Object? raw = null,}) {
  return _then(_AcoustIDReleaseGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,type: freezed == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as String?,secondaryTypes: null == secondaryTypes ? _self._secondaryTypes : secondaryTypes // ignore: cast_nullable_to_non_nullable
as List<String>,releases: null == releases ? _self._releases : releases // ignore: cast_nullable_to_non_nullable
as List<AcoustIDRelease>,raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$AcoustIDRecording implements DiagnosticableTreeMixin {

 String get id; String get title; String get artist; int? get durationMillis; List<AcoustIDReleaseGroup> get releaseGroups; Map<String, dynamic> get raw;
/// Create a copy of AcoustIDRecording
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcoustIDRecordingCopyWith<AcoustIDRecording> get copyWith => _$AcoustIDRecordingCopyWithImpl<AcoustIDRecording>(this as AcoustIDRecording, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDRecording'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('artist', artist))..add(DiagnosticsProperty('durationMillis', durationMillis))..add(DiagnosticsProperty('releaseGroups', releaseGroups))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcoustIDRecording&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.durationMillis, durationMillis) || other.durationMillis == durationMillis)&&const DeepCollectionEquality().equals(other.releaseGroups, releaseGroups)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,artist,durationMillis,const DeepCollectionEquality().hash(releaseGroups),const DeepCollectionEquality().hash(raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDRecording(id: $id, title: $title, artist: $artist, durationMillis: $durationMillis, releaseGroups: $releaseGroups, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $AcoustIDRecordingCopyWith<$Res>  {
  factory $AcoustIDRecordingCopyWith(AcoustIDRecording value, $Res Function(AcoustIDRecording) _then) = _$AcoustIDRecordingCopyWithImpl;
@useResult
$Res call({
 String id, String title, String artist, int? durationMillis, List<AcoustIDReleaseGroup> releaseGroups, Map<String, dynamic> raw
});




}
/// @nodoc
class _$AcoustIDRecordingCopyWithImpl<$Res>
    implements $AcoustIDRecordingCopyWith<$Res> {
  _$AcoustIDRecordingCopyWithImpl(this._self, this._then);

  final AcoustIDRecording _self;
  final $Res Function(AcoustIDRecording) _then;

/// Create a copy of AcoustIDRecording
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? artist = null,Object? durationMillis = freezed,Object? releaseGroups = null,Object? raw = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,artist: null == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String,durationMillis: freezed == durationMillis ? _self.durationMillis : durationMillis // ignore: cast_nullable_to_non_nullable
as int?,releaseGroups: null == releaseGroups ? _self.releaseGroups : releaseGroups // ignore: cast_nullable_to_non_nullable
as List<AcoustIDReleaseGroup>,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [AcoustIDRecording].
extension AcoustIDRecordingPatterns on AcoustIDRecording {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcoustIDRecording value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcoustIDRecording() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcoustIDRecording value)  $default,){
final _that = this;
switch (_that) {
case _AcoustIDRecording():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcoustIDRecording value)?  $default,){
final _that = this;
switch (_that) {
case _AcoustIDRecording() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String artist,  int? durationMillis,  List<AcoustIDReleaseGroup> releaseGroups,  Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcoustIDRecording() when $default != null:
return $default(_that.id,_that.title,_that.artist,_that.durationMillis,_that.releaseGroups,_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String artist,  int? durationMillis,  List<AcoustIDReleaseGroup> releaseGroups,  Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _AcoustIDRecording():
return $default(_that.id,_that.title,_that.artist,_that.durationMillis,_that.releaseGroups,_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String artist,  int? durationMillis,  List<AcoustIDReleaseGroup> releaseGroups,  Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _AcoustIDRecording() when $default != null:
return $default(_that.id,_that.title,_that.artist,_that.durationMillis,_that.releaseGroups,_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _AcoustIDRecording extends AcoustIDRecording with DiagnosticableTreeMixin {
  const _AcoustIDRecording({required this.id, required this.title, required this.artist, this.durationMillis, final  List<AcoustIDReleaseGroup> releaseGroups = const <AcoustIDReleaseGroup>[], required final  Map<String, dynamic> raw}): _releaseGroups = releaseGroups,_raw = raw,super._();
  

@override final  String id;
@override final  String title;
@override final  String artist;
@override final  int? durationMillis;
 final  List<AcoustIDReleaseGroup> _releaseGroups;
@override@JsonKey() List<AcoustIDReleaseGroup> get releaseGroups {
  if (_releaseGroups is EqualUnmodifiableListView) return _releaseGroups;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_releaseGroups);
}

 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of AcoustIDRecording
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcoustIDRecordingCopyWith<_AcoustIDRecording> get copyWith => __$AcoustIDRecordingCopyWithImpl<_AcoustIDRecording>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDRecording'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('title', title))..add(DiagnosticsProperty('artist', artist))..add(DiagnosticsProperty('durationMillis', durationMillis))..add(DiagnosticsProperty('releaseGroups', releaseGroups))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcoustIDRecording&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.artist, artist) || other.artist == artist)&&(identical(other.durationMillis, durationMillis) || other.durationMillis == durationMillis)&&const DeepCollectionEquality().equals(other._releaseGroups, _releaseGroups)&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,artist,durationMillis,const DeepCollectionEquality().hash(_releaseGroups),const DeepCollectionEquality().hash(_raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDRecording(id: $id, title: $title, artist: $artist, durationMillis: $durationMillis, releaseGroups: $releaseGroups, raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$AcoustIDRecordingCopyWith<$Res> implements $AcoustIDRecordingCopyWith<$Res> {
  factory _$AcoustIDRecordingCopyWith(_AcoustIDRecording value, $Res Function(_AcoustIDRecording) _then) = __$AcoustIDRecordingCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String artist, int? durationMillis, List<AcoustIDReleaseGroup> releaseGroups, Map<String, dynamic> raw
});




}
/// @nodoc
class __$AcoustIDRecordingCopyWithImpl<$Res>
    implements _$AcoustIDRecordingCopyWith<$Res> {
  __$AcoustIDRecordingCopyWithImpl(this._self, this._then);

  final _AcoustIDRecording _self;
  final $Res Function(_AcoustIDRecording) _then;

/// Create a copy of AcoustIDRecording
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? artist = null,Object? durationMillis = freezed,Object? releaseGroups = null,Object? raw = null,}) {
  return _then(_AcoustIDRecording(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,artist: null == artist ? _self.artist : artist // ignore: cast_nullable_to_non_nullable
as String,durationMillis: freezed == durationMillis ? _self.durationMillis : durationMillis // ignore: cast_nullable_to_non_nullable
as int?,releaseGroups: null == releaseGroups ? _self._releaseGroups : releaseGroups // ignore: cast_nullable_to_non_nullable
as List<AcoustIDReleaseGroup>,raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

/// @nodoc
mixin _$AcoustIDResult implements DiagnosticableTreeMixin {

 String get id; double get score; List<AcoustIDRecording> get recordings; Map<String, dynamic> get raw;
/// Create a copy of AcoustIDResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcoustIDResultCopyWith<AcoustIDResult> get copyWith => _$AcoustIDResultCopyWithImpl<AcoustIDResult>(this as AcoustIDResult, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDResult'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('score', score))..add(DiagnosticsProperty('recordings', recordings))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcoustIDResult&&(identical(other.id, id) || other.id == id)&&(identical(other.score, score) || other.score == score)&&const DeepCollectionEquality().equals(other.recordings, recordings)&&const DeepCollectionEquality().equals(other.raw, raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,score,const DeepCollectionEquality().hash(recordings),const DeepCollectionEquality().hash(raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDResult(id: $id, score: $score, recordings: $recordings, raw: $raw)';
}


}

/// @nodoc
abstract mixin class $AcoustIDResultCopyWith<$Res>  {
  factory $AcoustIDResultCopyWith(AcoustIDResult value, $Res Function(AcoustIDResult) _then) = _$AcoustIDResultCopyWithImpl;
@useResult
$Res call({
 String id, double score, List<AcoustIDRecording> recordings, Map<String, dynamic> raw
});




}
/// @nodoc
class _$AcoustIDResultCopyWithImpl<$Res>
    implements $AcoustIDResultCopyWith<$Res> {
  _$AcoustIDResultCopyWithImpl(this._self, this._then);

  final AcoustIDResult _self;
  final $Res Function(AcoustIDResult) _then;

/// Create a copy of AcoustIDResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? score = null,Object? recordings = null,Object? raw = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,recordings: null == recordings ? _self.recordings : recordings // ignore: cast_nullable_to_non_nullable
as List<AcoustIDRecording>,raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}

}


/// Adds pattern-matching-related methods to [AcoustIDResult].
extension AcoustIDResultPatterns on AcoustIDResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcoustIDResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcoustIDResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcoustIDResult value)  $default,){
final _that = this;
switch (_that) {
case _AcoustIDResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcoustIDResult value)?  $default,){
final _that = this;
switch (_that) {
case _AcoustIDResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  double score,  List<AcoustIDRecording> recordings,  Map<String, dynamic> raw)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcoustIDResult() when $default != null:
return $default(_that.id,_that.score,_that.recordings,_that.raw);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  double score,  List<AcoustIDRecording> recordings,  Map<String, dynamic> raw)  $default,) {final _that = this;
switch (_that) {
case _AcoustIDResult():
return $default(_that.id,_that.score,_that.recordings,_that.raw);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  double score,  List<AcoustIDRecording> recordings,  Map<String, dynamic> raw)?  $default,) {final _that = this;
switch (_that) {
case _AcoustIDResult() when $default != null:
return $default(_that.id,_that.score,_that.recordings,_that.raw);case _:
  return null;

}
}

}

/// @nodoc


class _AcoustIDResult extends AcoustIDResult with DiagnosticableTreeMixin {
  const _AcoustIDResult({required this.id, required this.score, final  List<AcoustIDRecording> recordings = const <AcoustIDRecording>[], required final  Map<String, dynamic> raw}): _recordings = recordings,_raw = raw,super._();
  

@override final  String id;
@override final  double score;
 final  List<AcoustIDRecording> _recordings;
@override@JsonKey() List<AcoustIDRecording> get recordings {
  if (_recordings is EqualUnmodifiableListView) return _recordings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_recordings);
}

 final  Map<String, dynamic> _raw;
@override Map<String, dynamic> get raw {
  if (_raw is EqualUnmodifiableMapView) return _raw;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_raw);
}


/// Create a copy of AcoustIDResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcoustIDResultCopyWith<_AcoustIDResult> get copyWith => __$AcoustIDResultCopyWithImpl<_AcoustIDResult>(this, _$identity);


@override
void debugFillProperties(DiagnosticPropertiesBuilder properties) {
  properties
    ..add(DiagnosticsProperty('type', 'AcoustIDResult'))
    ..add(DiagnosticsProperty('id', id))..add(DiagnosticsProperty('score', score))..add(DiagnosticsProperty('recordings', recordings))..add(DiagnosticsProperty('raw', raw));
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcoustIDResult&&(identical(other.id, id) || other.id == id)&&(identical(other.score, score) || other.score == score)&&const DeepCollectionEquality().equals(other._recordings, _recordings)&&const DeepCollectionEquality().equals(other._raw, _raw));
}


@override
int get hashCode => Object.hash(runtimeType,id,score,const DeepCollectionEquality().hash(_recordings),const DeepCollectionEquality().hash(_raw));

@override
String toString({ DiagnosticLevel minLevel = DiagnosticLevel.info }) {
  return 'AcoustIDResult(id: $id, score: $score, recordings: $recordings, raw: $raw)';
}


}

/// @nodoc
abstract mixin class _$AcoustIDResultCopyWith<$Res> implements $AcoustIDResultCopyWith<$Res> {
  factory _$AcoustIDResultCopyWith(_AcoustIDResult value, $Res Function(_AcoustIDResult) _then) = __$AcoustIDResultCopyWithImpl;
@override @useResult
$Res call({
 String id, double score, List<AcoustIDRecording> recordings, Map<String, dynamic> raw
});




}
/// @nodoc
class __$AcoustIDResultCopyWithImpl<$Res>
    implements _$AcoustIDResultCopyWith<$Res> {
  __$AcoustIDResultCopyWithImpl(this._self, this._then);

  final _AcoustIDResult _self;
  final $Res Function(_AcoustIDResult) _then;

/// Create a copy of AcoustIDResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? score = null,Object? recordings = null,Object? raw = null,}) {
  return _then(_AcoustIDResult(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,score: null == score ? _self.score : score // ignore: cast_nullable_to_non_nullable
as double,recordings: null == recordings ? _self._recordings : recordings // ignore: cast_nullable_to_non_nullable
as List<AcoustIDRecording>,raw: null == raw ? _self._raw : raw // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,
  ));
}


}

// dart format on
