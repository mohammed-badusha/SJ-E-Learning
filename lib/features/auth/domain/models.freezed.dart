// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Profile {

 String get id; String get fullName; String? get phone; String? get avatarUrl; bool get profileCompleted; int get rating; int get trophies; int get xp; int get level; int get currentStreak; int get bestStreak; String? get targetExam; bool get isBanned;
/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileCopyWith<Profile> get copyWith => _$ProfileCopyWithImpl<Profile>(this as Profile, _$identity);

  /// Serializes this Profile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Profile&&(identical(other.id, id) || other.id == id)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.profileCompleted, profileCompleted) || other.profileCompleted == profileCompleted)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.trophies, trophies) || other.trophies == trophies)&&(identical(other.xp, xp) || other.xp == xp)&&(identical(other.level, level) || other.level == level)&&(identical(other.currentStreak, currentStreak) || other.currentStreak == currentStreak)&&(identical(other.bestStreak, bestStreak) || other.bestStreak == bestStreak)&&(identical(other.targetExam, targetExam) || other.targetExam == targetExam)&&(identical(other.isBanned, isBanned) || other.isBanned == isBanned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,fullName,phone,avatarUrl,profileCompleted,rating,trophies,xp,level,currentStreak,bestStreak,targetExam,isBanned);

@override
String toString() {
  return 'Profile(id: $id, fullName: $fullName, phone: $phone, avatarUrl: $avatarUrl, profileCompleted: $profileCompleted, rating: $rating, trophies: $trophies, xp: $xp, level: $level, currentStreak: $currentStreak, bestStreak: $bestStreak, targetExam: $targetExam, isBanned: $isBanned)';
}


}

/// @nodoc
abstract mixin class $ProfileCopyWith<$Res>  {
  factory $ProfileCopyWith(Profile value, $Res Function(Profile) _then) = _$ProfileCopyWithImpl;
@useResult
$Res call({
 String id, String fullName, String? phone, String? avatarUrl, bool profileCompleted, int rating, int trophies, int xp, int level, int currentStreak, int bestStreak, String? targetExam, bool isBanned
});




}
/// @nodoc
class _$ProfileCopyWithImpl<$Res>
    implements $ProfileCopyWith<$Res> {
  _$ProfileCopyWithImpl(this._self, this._then);

  final Profile _self;
  final $Res Function(Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? fullName = null,Object? phone = freezed,Object? avatarUrl = freezed,Object? profileCompleted = null,Object? rating = null,Object? trophies = null,Object? xp = null,Object? level = null,Object? currentStreak = null,Object? bestStreak = null,Object? targetExam = freezed,Object? isBanned = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,profileCompleted: null == profileCompleted ? _self.profileCompleted : profileCompleted // ignore: cast_nullable_to_non_nullable
as bool,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int,trophies: null == trophies ? _self.trophies : trophies // ignore: cast_nullable_to_non_nullable
as int,xp: null == xp ? _self.xp : xp // ignore: cast_nullable_to_non_nullable
as int,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,currentStreak: null == currentStreak ? _self.currentStreak : currentStreak // ignore: cast_nullable_to_non_nullable
as int,bestStreak: null == bestStreak ? _self.bestStreak : bestStreak // ignore: cast_nullable_to_non_nullable
as int,targetExam: freezed == targetExam ? _self.targetExam : targetExam // ignore: cast_nullable_to_non_nullable
as String?,isBanned: null == isBanned ? _self.isBanned : isBanned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [Profile].
extension ProfilePatterns on Profile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Profile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Profile value)  $default,){
final _that = this;
switch (_that) {
case _Profile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Profile value)?  $default,){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String fullName,  String? phone,  String? avatarUrl,  bool profileCompleted,  int rating,  int trophies,  int xp,  int level,  int currentStreak,  int bestStreak,  String? targetExam,  bool isBanned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.id,_that.fullName,_that.phone,_that.avatarUrl,_that.profileCompleted,_that.rating,_that.trophies,_that.xp,_that.level,_that.currentStreak,_that.bestStreak,_that.targetExam,_that.isBanned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String fullName,  String? phone,  String? avatarUrl,  bool profileCompleted,  int rating,  int trophies,  int xp,  int level,  int currentStreak,  int bestStreak,  String? targetExam,  bool isBanned)  $default,) {final _that = this;
switch (_that) {
case _Profile():
return $default(_that.id,_that.fullName,_that.phone,_that.avatarUrl,_that.profileCompleted,_that.rating,_that.trophies,_that.xp,_that.level,_that.currentStreak,_that.bestStreak,_that.targetExam,_that.isBanned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String fullName,  String? phone,  String? avatarUrl,  bool profileCompleted,  int rating,  int trophies,  int xp,  int level,  int currentStreak,  int bestStreak,  String? targetExam,  bool isBanned)?  $default,) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.id,_that.fullName,_that.phone,_that.avatarUrl,_that.profileCompleted,_that.rating,_that.trophies,_that.xp,_that.level,_that.currentStreak,_that.bestStreak,_that.targetExam,_that.isBanned);case _:
  return null;

}
}

}

/// @nodoc

@JsonSerializable(fieldRename: FieldRename.snake)
class _Profile extends Profile {
  const _Profile({required this.id, this.fullName = '', this.phone, this.avatarUrl, this.profileCompleted = false, this.rating = 0, this.trophies = 0, this.xp = 0, this.level = 1, this.currentStreak = 0, this.bestStreak = 0, this.targetExam, this.isBanned = false}): super._();
  factory _Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

@override final  String id;
@override@JsonKey() final  String fullName;
@override final  String? phone;
@override final  String? avatarUrl;
@override@JsonKey() final  bool profileCompleted;
@override@JsonKey() final  int rating;
@override@JsonKey() final  int trophies;
@override@JsonKey() final  int xp;
@override@JsonKey() final  int level;
@override@JsonKey() final  int currentStreak;
@override@JsonKey() final  int bestStreak;
@override final  String? targetExam;
@override@JsonKey() final  bool isBanned;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileCopyWith<_Profile> get copyWith => __$ProfileCopyWithImpl<_Profile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Profile&&(identical(other.id, id) || other.id == id)&&(identical(other.fullName, fullName) || other.fullName == fullName)&&(identical(other.phone, phone) || other.phone == phone)&&(identical(other.avatarUrl, avatarUrl) || other.avatarUrl == avatarUrl)&&(identical(other.profileCompleted, profileCompleted) || other.profileCompleted == profileCompleted)&&(identical(other.rating, rating) || other.rating == rating)&&(identical(other.trophies, trophies) || other.trophies == trophies)&&(identical(other.xp, xp) || other.xp == xp)&&(identical(other.level, level) || other.level == level)&&(identical(other.currentStreak, currentStreak) || other.currentStreak == currentStreak)&&(identical(other.bestStreak, bestStreak) || other.bestStreak == bestStreak)&&(identical(other.targetExam, targetExam) || other.targetExam == targetExam)&&(identical(other.isBanned, isBanned) || other.isBanned == isBanned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,fullName,phone,avatarUrl,profileCompleted,rating,trophies,xp,level,currentStreak,bestStreak,targetExam,isBanned);

@override
String toString() {
  return 'Profile(id: $id, fullName: $fullName, phone: $phone, avatarUrl: $avatarUrl, profileCompleted: $profileCompleted, rating: $rating, trophies: $trophies, xp: $xp, level: $level, currentStreak: $currentStreak, bestStreak: $bestStreak, targetExam: $targetExam, isBanned: $isBanned)';
}


}

/// @nodoc
abstract mixin class _$ProfileCopyWith<$Res> implements $ProfileCopyWith<$Res> {
  factory _$ProfileCopyWith(_Profile value, $Res Function(_Profile) _then) = __$ProfileCopyWithImpl;
@override @useResult
$Res call({
 String id, String fullName, String? phone, String? avatarUrl, bool profileCompleted, int rating, int trophies, int xp, int level, int currentStreak, int bestStreak, String? targetExam, bool isBanned
});




}
/// @nodoc
class __$ProfileCopyWithImpl<$Res>
    implements _$ProfileCopyWith<$Res> {
  __$ProfileCopyWithImpl(this._self, this._then);

  final _Profile _self;
  final $Res Function(_Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? fullName = null,Object? phone = freezed,Object? avatarUrl = freezed,Object? profileCompleted = null,Object? rating = null,Object? trophies = null,Object? xp = null,Object? level = null,Object? currentStreak = null,Object? bestStreak = null,Object? targetExam = freezed,Object? isBanned = null,}) {
  return _then(_Profile(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,fullName: null == fullName ? _self.fullName : fullName // ignore: cast_nullable_to_non_nullable
as String,phone: freezed == phone ? _self.phone : phone // ignore: cast_nullable_to_non_nullable
as String?,avatarUrl: freezed == avatarUrl ? _self.avatarUrl : avatarUrl // ignore: cast_nullable_to_non_nullable
as String?,profileCompleted: null == profileCompleted ? _self.profileCompleted : profileCompleted // ignore: cast_nullable_to_non_nullable
as bool,rating: null == rating ? _self.rating : rating // ignore: cast_nullable_to_non_nullable
as int,trophies: null == trophies ? _self.trophies : trophies // ignore: cast_nullable_to_non_nullable
as int,xp: null == xp ? _self.xp : xp // ignore: cast_nullable_to_non_nullable
as int,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,currentStreak: null == currentStreak ? _self.currentStreak : currentStreak // ignore: cast_nullable_to_non_nullable
as int,bestStreak: null == bestStreak ? _self.bestStreak : bestStreak // ignore: cast_nullable_to_non_nullable
as int,targetExam: freezed == targetExam ? _self.targetExam : targetExam // ignore: cast_nullable_to_non_nullable
as String?,isBanned: null == isBanned ? _self.isBanned : isBanned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
