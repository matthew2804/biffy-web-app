import '../../data/models/rewards.dart';

/// Resultado de validar el código de un premio en la sede.
typedef ClaimResult = ({bool ok, String? prize, String? error});

/// Contrato de las cajas de Gotas vistas por el restaurante.
/// La implementación real es `SupabaseRewardsRepository`.
abstract interface class MerchantBoxesRepository {
  /// Cajas y recompensas activas.
  Future<List<GotasBox>> boxes();

  /// Platos del negocio que ya están dentro de alguna caja.
  Future<List<BoxItemView>> merchantItems();

  /// Mete un plato de una sede en la caja [rewardCode].
  Future<void> addItem({
    required String rewardCode,
    required String branchId,
    required String dishId,
  });

  /// Saca un plato de una caja.
  Future<void> removeItem(String id);

  /// Valida el código que dicta el cliente y marca el premio como reclamado.
  Future<ClaimResult> useRedemption(String code);
}
