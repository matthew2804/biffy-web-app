import '../../data/models/catalog.dart';
import '../../data/models/rewards.dart';
import '../repositories/merchant_boxes_repository.dart';

/// Cajas que el restaurante puede llenar y los platos que ya metió.
class MerchantBoxes {
  const MerchantBoxes({required this.boxes, required this.items});

  final List<GotasBox> boxes;
  final List<BoxItemView> items;

  /// Platos dentro de [box].
  List<BoxItemView> itemsOf(GotasBox box) =>
      items.where((i) => i.rewardCode == box.code).toList();
}

/// Caso de uso: solo las cajas `merchant_managed` aceptan platos de negocios.
class LoadMerchantBoxes {
  const LoadMerchantBoxes(this._repo);
  final MerchantBoxesRepository _repo;

  Future<MerchantBoxes> call() async {
    final boxes = _repo.boxes();
    final items = _repo.merchantItems();
    return MerchantBoxes(
      boxes: (await boxes).where((b) => b.merchantManaged).toList(),
      items: await items,
    );
  }
}

/// Caso de uso: mete un plato activo del menú en una caja.
class AddDishToBox {
  const AddDishToBox(this._repo);
  final MerchantBoxesRepository _repo;

  Future<void> call(GotasBox box, Dish dish) => _repo.addItem(
    rewardCode: box.code,
    branchId: dish.restaurantId,
    dishId: dish.id,
  );
}

/// Caso de uso: valida el código del premio (vacío no llama a la base).
class ClaimBoxPrize {
  const ClaimBoxPrize(this._repo);
  final MerchantBoxesRepository _repo;

  Future<ClaimResult> call(String code) async {
    final clean = code.trim().toUpperCase();
    if (clean.isEmpty) {
      return (ok: false, prize: null, error: 'Escribe el código del premio.');
    }
    return _repo.useRedemption(clean);
  }
}
