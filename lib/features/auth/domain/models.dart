import 'package:freezed_annotation/freezed_annotation.dart';
import '../../profile/domain/rank_tier.dart';
part 'models.freezed.dart';
part 'models.g.dart';

enum AdminRole {
  student,
  viewer,
  editor,
  superAdmin;

  static AdminRole parse(String value) => switch (value) {
    'super_admin' => superAdmin,
    'editor' => editor,
    'viewer' => viewer,
    _ => student,
  };
  bool get isAdmin => this != student;
  bool get canEdit => this == editor || this == superAdmin;
}

@freezed
abstract class Profile with _$Profile {
  const Profile._();
  // ignore: invalid_annotation_target
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Profile({
    required String id,
    @Default('') String fullName,
    String? phone,
    String? avatarUrl,
    @Default(false) bool profileCompleted,
    @Default(0) int rating,
    @Default(0) int trophies,
    @Default(0) int xp,
    @Default(1) int level,
    @Default(0) int currentStreak,
    @Default(0) int bestStreak,
    String? targetExam,
    @Default(false) bool isBanned,
  }) = _Profile;
  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
  String get firstName => fullName.trim().split(' ').first;
  String get tier => RankTier.forTrophies(trophies).label;
}

String? validateName(String value) =>
    value.trim().length < 2 || value.trim().length > 50
    ? 'Enter your full name (2–50 characters).'
    : null;
String normalizePhone(String value) =>
    value.replaceAll(RegExp(r'[\s()-]'), '').replaceFirst(RegExp(r'^\+91'), '');
String? validatePhone(String value) =>
    RegExp(r'^[6-9][0-9]{9}$').hasMatch(normalizePhone(value))
    ? null
    : 'Enter a valid 10-digit Indian mobile number.';

String? routeRedirect({
  required bool signedIn,
  required bool completed,
  required AdminRole role,
  required String path,
}) {
  if (!signedIn) return path == '/login' ? null : '/login';
  if (!completed) {
    return path == '/complete-profile' ? null : '/complete-profile';
  }
  if (path == '/login' || path == '/complete-profile') return '/';
  if (path.startsWith('/admin') && !role.isAdmin) return '/';
  return null;
}
