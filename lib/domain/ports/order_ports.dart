import '../entities/catalog.dart';
import '../entities/order.dart';
import '../entities/user.dart';

/// Lo que los casos de uso de pedidos necesitan saber del catálogo.
/// Lo implementa `CatalogController`.
abstract class OrderCatalogPort {
  Dish? dishById(String id);
  Restaurant? restaurantById(String id);

  /// Sedes de un negocio (para que el restaurante vea solo sus pedidos).
  List<Restaurant> branchesOf(String businessId);

  /// Suma una venta al contador local del plato (porciones del día).
  void recordSale(String dishId, int qty);
}

/// Datos del comprador que afectan al precio. Lo implementa `SessionController`.
abstract class OrderBuyerPort {
  String? verifiedUniversityId(String userId);
  int gotasOf(String userId);

  /// Punto de entrega activo cuando el borrador aún no tiene dirección.
  DeliveryPoint get currentPoint;
}

/// Movimientos locales de Gotas y cupones.
///
/// Con servidor, las Gotas y los cupones los mueve la base de datos; los
/// casos de uso solo piden [syncBalance] para releer el saldo.
abstract class OrderWalletPort {
  void spendGotas(String userId, int amount, String reason);
  void creditGotas(String userId, int amount, String reason);
  void setCouponUsed(String userId, String couponId, bool used);

  /// Vuelve a leer el saldo del servidor. No hace nada en modo demo.
  Future<void> syncBalance();
}

/// Avisos a las personas involucradas en un pedido. Lo implementa un adaptador
/// sobre `NotificationCenter`.
abstract class OrderNotifier {
  void placed(Order order, {required String businessId});
  void buyerCancelled(Order order, {required String? businessId});
  void accepted(Order order);
  void rejected(Order order);
  void ready(Order order);
  void assigned(Order order, AppUser courier, {required String? businessId});
  void pickedUp(Order order);
  void delivered(Order order, {required String? businessId});
}
