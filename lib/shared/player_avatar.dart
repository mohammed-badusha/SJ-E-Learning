import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/auth/data/session.dart';
import 'widgets.dart';

const portraits = {
  'einstein': 'Einstein',
  'curie': 'Marie Curie',
  'raman': 'C. V. Raman',
  'explorer': 'Astronomer',
};
final _photoProvider = FutureProvider.autoDispose.family<Uint8List?, String>((
  ref,
  photoId,
) async {
  final encoded = await ref
      .watch(sessionProvider)
      .client
      ?.rpc('get_player_photo', params: {'photo_id': photoId});
  return encoded is String ? base64Decode(encoded) : null;
});

class PlayerAvatar extends ConsumerWidget {
  const PlayerAvatar({
    super.key,
    required this.name,
    this.reference,
    this.matchId,
    this.size = 48,
    this.draft,
  });
  final String name;
  final String? reference, matchId;
  final double size;
  final Uint8List? draft;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = reference ?? '';
    ImageProvider? image;
    if (draft != null) {
      image = MemoryImage(draft!);
    } else if (key.startsWith('preset:') &&
        portraits.containsKey(key.substring(7))) {
      image = AssetImage('assets/avatars/${key.substring(7)}.webp');
    } else if (key.startsWith('photo:')) {
      final data = ref.watch(_photoProvider(key.substring(6))).asData?.value;
      if (data != null) image = MemoryImage(data);
    } else if (key.startsWith('https://') &&
        Uri.tryParse(key)?.host.endsWith('.googleusercontent.com') == true) {
      image = NetworkImage(key);
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
          child: image == null
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
