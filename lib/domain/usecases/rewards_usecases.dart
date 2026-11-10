import '../../data/models/rewards.dart';
import '../repositories/rewards_repository.dart';

/// Todo lo que muestra la pantalla de Gotas en una sola carga.
class RewardsSnapshot {
  const RewardsSnapshot({
    required this.boxes,
    required this.history,
    required this.ledger,
  });

  final List<GotasBox> boxes;
  final List<RewardRedemption> history;
  final List<GotasMovement> ledger;
}

/// Caso de uso: carga cajas, canjes y movimientos en paralelo.
class LoadRewards {
  const LoadRewards(this._repo);
  final RewardsRepository _repo;

  Future<RewardsSnapshot> call() async {
    final boxes = _repo.boxes();
    final history = _repo.history();
    final ledger = _repo.ledger();
    return RewardsSnapshot(
      boxes: await boxes,
      history: await history,
      ledger: await ledger,
    );
  }
}

/// Caso de uso: canjea una caja. El saldo y el sorteo los decide la base
/// (`redeem_reward`); la app nunca descuenta Gotas por su cuenta.
class RedeemReward {
  const RedeemReward(this._repo);
  final RewardsRepository _repo;

  Future<RedeemOutcome> call(GotasBox box) => _repo.redeem(box.code);
}
