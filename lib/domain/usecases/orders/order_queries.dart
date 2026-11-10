import '../../entities/order.dart';
import '../../entities/user.dart';
import '../../order_rules.dart';
import '../../ports/order_ports.dart';
import '../../repositories/order_repository.dart';

/// Consultas de lectura sobre los pedidos visibles para cada rol.
class OrderQueries {
  OrderQueries(this._repo, this._catalog);

  final OrderRepository _repo;
  final OrderCatalogPort _catalog;

  List<Order> get all => _repo.all;

  Order? byId(String id) => _repo.byId(id);

  List<Order> forBuyer(String userId) =>
      all.where((o) => o.buyerId == userId).toList();

  List<Order> forBusiness(String businessId) {
    final ids = _catalog.branchesOf(businessId).map((r) => r.id).toSet();
    return all.where((o) => ids.contains(o.restaurantId)).toList();
  }

  Order? activeForCourier(String courierId) {
    for (final o in all) {
      if (o.courierId == courierId &&
          (o.status == OrderStatus.ready || o.status == OrderStatus.onTheWay)) {
        return o;
      }
    }
    return null;
  }

  List<Order> deliveredBy(String courierId) => all
      .where(
        (o) => o.courierId == courierId && o.status == OrderStatus.delivered,
      )
      .toList();

  /// Pedidos listos sin repartidor, compatibles con zona y medio de transporte.
  List<Order> availableOffers({
    required String courierId,
    required CourierZone zone,
    String? universityId,
    Vehicle? vehicle,
  }) {
    return all.where((o) {
      if (o.status != OrderStatus.ready || o.courierId != null) return false;
      if (o.declinedBy.contains(courierId)) return false;
      if (vehicle != null && !courierCanTake(o, vehicle)) return false;
      if (zone == CourierZone.campus) {
        final r = _catalog.restaurantById(o.restaurantId);
        return universityId != null && r?.campusId == universityId;
      }
      return true;
    }).toList();
  }
}
