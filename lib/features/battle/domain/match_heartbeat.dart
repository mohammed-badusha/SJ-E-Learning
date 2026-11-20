/// Whether a lightweight heartbeat revealed state that a missed broadcast
/// would otherwise leave stale on screen.
bool matchHeartbeatNeedsRefresh(
  Map<String, dynamic> heartbeat,
  Map<String, dynamic>? state,
  String ownPlayerId,
) {
  if (state == null) return true;
  if (heartbeat['status'] != state['status'] ||
      heartbeat['phase'] != state['phase'] ||
      heartbeat['question_index'] != state['question_index'] ||
      heartbeat['answered_count'] != (state['answered'] as List?)?.length) {
    return true;
  }
  final players = state['players'];
  if (players is! List) return true;
  for (final player in players) {
    if (player is Map && player['id'] != ownPlayerId) {
      return heartbeat['opponent_connected'] != player['connected'];
    }
  }
  return true;
}
