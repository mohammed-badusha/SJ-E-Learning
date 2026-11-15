import 'package:flutter_riverpod/flutter_riverpod.dart';

final standingsCacheProvider = Provider((_) => StandingsCache());

class _BoardEntry {
  _BoardEntry(this.period, this.data, this.fetchedAt);
  final String period;
  final Map<String, dynamic> data;
  DateTime fetchedAt;
}

/// Small in-memory stale-while-revalidate cache. Rankings are never persisted
/// on the device; only the bounded avatar thumbnails use disk storage.
class StandingsCache {
  static const freshness = Duration(seconds: 20);
  final _memory = <String, _BoardEntry>{};
  final _active = <String, Future<Map<String, dynamic>>>{};
  final _requests = <String, int>{};

  String period(String type, DateTime now) {
    if (type == 'all_time') return type;
    var day = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    if (type == 'weekly') day = day.subtract(Duration(days: day.weekday - 1));
    return day.toIso8601String().substring(0, 10);
  }

  Map<String, dynamic>? read(String key, String period) {
    final item = _memory[key];
    return item?.period == period ? item!.data : null;
  }

  void invalidate(String key) {
    final item = _memory[key];
    if (item != null) item.fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<Map<String, dynamic>> load(
    String key,
    String period,
    Future<Map<String, dynamic>> Function() fetch, {
    bool force = false,
  }) {
    final activeKey = '$key:$period';
    final pending = _active[activeKey];
    if (pending != null) return pending;
    final item = _memory[key];
    if (!force &&
        item?.period == period &&
        DateTime.now().difference(item!.fetchedAt) < freshness) {
      return Future.value(item.data);
    }
    final request = _requests.update(key, (n) => n + 1, ifAbsent: () => 1);
    final result = fetch().then((data) {
      if (_requests[key] == request) {
        _memory[key] = _BoardEntry(period, data, DateTime.now());
        if (_memory.length > 12) _memory.remove(_memory.keys.first);
      }
      return data;
    });
    _active[activeKey] = result;
    result.then(
      (_) {
        _active.remove(activeKey);
      },
      onError: (Object _) {
        _active.remove(activeKey);
      },
    );
    return result;
  }
}
