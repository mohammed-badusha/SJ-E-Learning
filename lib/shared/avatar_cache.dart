import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A bounded cache for the small portraits used throughout the app.
/// Photo UUIDs change when a gallery portrait is replaced, so a changed
/// reference never resolves to an old cached file.
class AvatarCache {
  AvatarCache._();

  static final instance = AvatarCache._();

  final disk = CacheManager(
    Config(
      'sj-player-avatars-v1',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 120,
    ),
  );

  final _memory = <String, Uint8List>{};
  final _pending = <String, Future<Uint8List?>>{};
  final _writes = <Future<void>>{};
  int _memoryBytes = 0;
  int _generation = 0;
  Future<void>? _clearing;

  String networkKey(String url, int revision) => '$url|$revision';

  Uint8List? peek(String reference) {
    final bytes = _memory.remove(reference);
    if (bytes != null) _memory[reference] = bytes;
    return bytes;
  }

  Future<Uint8List?> gallery(String reference, SupabaseClient? client) {
    if (!reference.startsWith('photo:') ||
        client?.auth.currentSession == null) {
      return Future.value(null);
    }
    final ready = peek(reference);
    if (ready != null) return Future.value(ready);
    return _pending.putIfAbsent(reference, () {
      final generation = _generation;
      final request = _loadGallery(reference, client!, generation);
      request.then(
        (_) => _pending.remove(reference),
        onError: (Object _) => _pending.remove(reference),
      );
      return request;
    });
  }

  Future<Uint8List?> _loadGallery(
    String reference,
    SupabaseClient client,
    int generation,
  ) async {
    if (!kIsWeb) {
      try {
        final stored = await disk.getFileFromCache(reference);
        if (stored != null) {
          final bytes = await stored.file.readAsBytes();
          if (generation == _generation && client.auth.currentSession != null) {
            _remember(reference, bytes);
            return bytes;
          }
        }
      } catch (_) {
        // A cleared or damaged cache file is a miss; the server remains source.
      }
    }
    if (generation != _generation || client.auth.currentSession == null) {
      return null;
    }
    final encoded = await client.rpc(
      'get_player_photo',
      params: {'photo_id': reference.substring(6)},
    );
    if (encoded is! String || encoded.isEmpty) return null;
    final bytes = base64Decode(encoded);
    if (generation != _generation || client.auth.currentSession == null) {
      return null;
    }
    _remember(reference, bytes);
    if (!kIsWeb) {
      final write = _store(reference, bytes, generation);
      _writes.add(write);
      write.then(
        (_) => _writes.remove(write),
        onError: (Object _) => _writes.remove(write),
      );
    }
    return bytes;
  }

  Future<void> _store(String reference, Uint8List bytes, int generation) async {
    try {
      if (generation == _generation) {
        await disk.putFile(
          reference,
          bytes,
          key: reference,
          fileExtension: 'png',
          maxAge: const Duration(days: 7),
        );
      }
    } catch (_) {
      // A failed disk write must not hide a successfully fetched portrait.
    }
  }

  void _remember(String key, Uint8List bytes) {
    final previous = _memory.remove(key);
    if (previous != null) _memoryBytes -= previous.lengthInBytes;
    _memory[key] = bytes;
    _memoryBytes += bytes.lengthInBytes;
    while (_memory.length > 32 || _memoryBytes > 3 * 1024 * 1024) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)!.lengthInBytes;
    }
  }

  Future<void> remove(String reference) async {
    final previous = _memory.remove(reference);
    if (previous != null) _memoryBytes -= previous.lengthInBytes;
    if (!kIsWeb) {
      try {
        await Future.wait(_writes.toList());
        await disk.removeFile(reference);
      } catch (_) {}
    }
  }

  Future<void> clear() => _clearing ??= _clear().whenComplete(() {
    _clearing = null;
  });

  Future<void> _clear() async {
    _generation++;
    _memory.clear();
    _memoryBytes = 0;
    _pending.clear();
    PaintingBinding.instance.imageCache.clear();
    try {
      await Future.wait(_writes.toList());
      await disk.emptyCache();
    } catch (_) {}
  }
}
