import '../data/models/rewards.dart';

/// Último canje de cada recompensa (por código) según el [history].
Map<String, DateTime> lastRedeemedByReward(Iterable<RewardRedemption> history) {
  final last = <String, DateTime>{};
  for (final r in history) {
    final prev = last[r.rewardCode];
    if (prev == null || r.at.isAfter(prev)) last[r.rewardCode] = r.at;
  }
  return last;
}

/// Cuándo se puede volver a abrir [box]; `null` si ya está disponible.
/// Misma regla que `cooldown_hours` en `redeem_reward`.
DateTime? nextAvailableAt(GotasBox box, DateTime? lastUsed, DateTime now) {
  if (lastUsed == null || box.cooldownHours <= 0) return null;
  final next = lastUsed.add(Duration(hours: box.cooldownHours));
  return next.isAfter(now) ? next : null;
}
