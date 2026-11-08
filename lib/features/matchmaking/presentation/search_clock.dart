import 'dart:async';
import 'package:flutter/foundation.dart';

/// Anchor once per queue entry; polling latency must not reset the visible second.
class SearchClock extends ValueNotifier<int?> {
  SearchClock({DateTime Function()? now})
    : now = now ?? DateTime.now,
      super(null);
  final DateTime Function() now;
  Timer? _timer;
  DateTime? _deadline;
  String? _entry;
  int total = 20;
  void sync({
    required DateTime joined,
    required DateTime server,
    required int timeout,
  }) {
    final entry = '$joined/$timeout';
    if (_entry == entry) return;
    _entry = entry;
    total = timeout;
    _deadline = now().add(
      joined.add(Duration(seconds: timeout)).difference(server),
    );
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    final ms = _deadline!
        .difference(now())
        .inMilliseconds
        .clamp(0, total * 1000);
    value = (ms + 999) ~/ 1000;
    if (ms > 0) {
      _timer = Timer(Duration(milliseconds: (ms - 1) % 1000 + 1), _tick);
    }
  }

  void stop() => _timer?.cancel();
  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
