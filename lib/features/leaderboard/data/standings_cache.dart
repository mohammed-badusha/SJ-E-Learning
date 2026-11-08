import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

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
    if (item == null && Hive.isBoxOpen('preferences')) {
      final raw = Hive.box('preferences').get(key);
      if (raw is String) {
        try {
          item = Map<String, dynamic>.from(jsonDecode(raw));
        } on FormatException {
          return null;
        }
      }
    }
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
    if (Hive.isBoxOpen('preferences')) {
      try {
        await Hive.box('preferences').put(key, jsonEncode(item));
      } on Exception {
        /* The in-memory copy remains available. */
      }
    }
  }
}
