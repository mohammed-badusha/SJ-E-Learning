import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_arena/features/leaderboard/data/standings_cache.dart';

void main() {
  test('deduplicates simultaneous refreshes and keeps cached rows visible', () async {
    final cache = StandingsCache();
    const key = 'standings:user:weekly';
    const period = '2026-11-09';
    final first = Completer<Map<String, dynamic>>();
    var calls = 0;

    Future<Map<String, dynamic>> fetch() {
      calls++;
      return first.future;
    }

    final a = cache.load(key, period, fetch);
    final b = cache.load(key, period, fetch);
    expect(identical(a, b), isTrue);
    expect(calls, 1);
    expect(cache.read(key, period), isNull);

    first.complete({'rows': [1]});
    await a;
    expect(cache.read(key, period), {'rows': [1]});
    await cache.load(key, period, fetch);
    expect(calls, 1);

    cache.invalidate(key);
    final next = Completer<Map<String, dynamic>>();
    final refreshing = cache.load(key, period, () {
      calls++;
      return next.future;
    });
    expect(cache.read(key, period), {'rows': [1]});
    next.complete({'rows': [2]});
    await refreshing;
    expect(cache.read(key, period), {'rows': [2]});
    expect(calls, 2);
    expect(cache.read(key, '2026-11-16'), isNull);
  });
}
