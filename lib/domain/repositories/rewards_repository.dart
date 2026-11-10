import '../../data/models/rewards.dart';

/// Contrato de recompensas con Gotas. La implementación real es
/// `SupabaseRewardsRepository` (RPC `redeem_reward`); el dominio no la conoce.
abstract interface class RewardsRepository {
  /// Cajas y recompensas activas.
  Future<List<GotasBox>> boxes();

  /// Canjea la recompensa [code] y devuelve el premio y el saldo nuevo.
  Future<RedeemOutcome> redeem(String code);

  /// Canjes del usuario, del más reciente al más antiguo.
  Future<List<RewardRedemption>> history();

  /// Movimientos de Gotas del usuario (`gotas_ledger`).
  Future<List<GotasMovement>> ledger();
}
