/// Exponential backoff (seconds) for the nth automatic reconnect attempt,
/// capped at 30s: 1, 2, 4, 8, 16, 30, 30, ... Kept as a pure function so
/// the schedule is unit-testable without touching timers or the network.
int reconnectBackoffSeconds(int attempt) {
  final shift = attempt < 5 ? attempt : 5;
  final raw = 1 << shift; // 1,2,4,8,16,32
  return raw > 30 ? 30 : raw;
}
