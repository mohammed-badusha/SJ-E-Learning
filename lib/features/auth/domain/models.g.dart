// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Profile _$ProfileFromJson(Map<String, dynamic> json) => _Profile(
  id: json['id'] as String,
  fullName: json['full_name'] as String? ?? '',
  phone: json['phone'] as String?,
  avatarUrl: json['avatar_url'] as String?,
  profileCompleted: json['profile_completed'] as bool? ?? false,
  rating: (json['rating'] as num?)?.toInt() ?? 1000,
  xp: (json['xp'] as num?)?.toInt() ?? 0,
  level: (json['level'] as num?)?.toInt() ?? 1,
  currentStreak: (json['current_streak'] as num?)?.toInt() ?? 0,
  bestStreak: (json['best_streak'] as num?)?.toInt() ?? 0,
  targetExam: json['target_exam'] as String?,
  isBanned: json['is_banned'] as bool? ?? false,
);

Map<String, dynamic> _$ProfileToJson(_Profile instance) => <String, dynamic>{
  'id': instance.id,
  'full_name': instance.fullName,
  'phone': instance.phone,
  'avatar_url': instance.avatarUrl,
  'profile_completed': instance.profileCompleted,
  'rating': instance.rating,
  'xp': instance.xp,
  'level': instance.level,
  'current_streak': instance.currentStreak,
  'best_streak': instance.bestStreak,
  'target_exam': instance.targetExam,
  'is_banned': instance.isBanned,
};
