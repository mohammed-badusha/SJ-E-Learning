import 'dart:typed_data';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/data/session.dart';
import 'avatar_cache.dart';
import 'widgets.dart';

const portraits = {
  'einstein': 'Einstein',
  'curie': 'Marie Curie',
  'raman': 'C. V. Raman',
  'explorer': 'Astronomer',
};
final _photoProvider = FutureProvider.autoDispose.family<Uint8List?, String>(
  (ref, photoId) => AvatarCache.instance.gallery(
    'photo:$photoId',
    ref.watch(sessionProvider).client,
  ),
);

class PlayerAvatar extends ConsumerWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    this.reference,
    this.matchId,
    this.size = 48,
    this.draft,
    this.avatarRevision = 0,
  });
  final String name;
  final String? reference, matchId;
  final double size;
  final Uint8List? draft;
  final int avatarRevision;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = reference ?? '';
    final cache = AvatarCache.instance;
    ImageProvider? image;
    if (draft != null) {
      image = MemoryImage(draft!);
    } else if (key.startsWith('preset:') &&
        portraits.containsKey(key.substring(7))) {
      image = AssetImage('assets/avatars/${key.substring(7)}.webp');
    } else if (key.startsWith('photo:')) {
      final session = ref.watch(sessionProvider);
      final data = session.client?.auth.currentSession == null
          ? null
          : cache.peek(key) ??
                ref.watch(_photoProvider(key.substring(6))).asData?.value;
      if (data != null) {
        image = ResizeImage(
          MemoryImage(data),
          width: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
            48,
            192,
          ),
        );
      }
    }
    final colorCode = key.startsWith('color:#')
        ? int.tryParse('FF${key.substring(7)}', radix: 16)
        : null;
    final fallback = colorCode == null
        ? AvatarBadge(name: name, size: size)
        : CircleAvatar(
            radius: size / 2,
            backgroundColor: Color(colorCode),
            foregroundColor: Colors.white,
            child: Text(name.isEmpty ? '?' : name.substring(0, 1)),
          );
    return Semantics(
      image: true,
      label: 'Profile picture for $name',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child:
              draft == null &&
                  key.startsWith('https://') &&
                  Uri.tryParse(key)?.host.endsWith('.googleusercontent.com') ==
                      true
              ? CachedNetworkImage(
                  imageUrl: key,
                  cacheKey: cache.networkKey(key, avatarRevision),
                  cacheManager: cache.disk,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  memCacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .round()
                      .clamp(48, 192),
                  maxWidthDiskCache: 192,
                  fadeInDuration: Duration.zero,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                )
              : image == null
              ? fallback
              : Image(
                  image: image,
                  fit: BoxFit.cover,
                  frameBuilder: (_, child, frame, sync) =>
                      sync || frame != null ? child : fallback,
                  errorBuilder: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}
