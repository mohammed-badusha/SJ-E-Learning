import 'package:flutter_riverpod/flutter_riverpod.dart';

final standingsCacheProvider = Provider((_) => StandingsCache());

class StandingsCache {
  final _memory = <String, Map<String, dynamic>>{};
  final _requests = <String, int>{};
  String period(String type, DateTime utc) {
    if (type == 'all_time') return type;
    var day = utc.toUtc().add(const Duration(hours: 5, minutes: 30));
    if (type == 'weekly') day = day.subtract(Duration(days: day.weekday - 1));
    return day.toIso8601String().substring(0, 10);
  }

  int begin(String key) =>
      _requests.update(key, (n) => n + 1, ifAbsent: () => 1);
  Map<String, dynamic>? read(String key, String period) {
    var item = _memory[key];

    if (item == null || item['period'] != period) return null;
    return item['data'] as Map<String, dynamic>?;
  }

  Future<void> write(
    String key,
    String period,
    int request,
    Map<String, dynamic> data,
  ) async {
    if (request != _requests[key]) return;
    final item = {'period': period, 'data': data};
    _memory[key] = item;
  }
}
