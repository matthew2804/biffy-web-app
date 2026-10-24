import '../models/order.dart';

/// Contrato de persistencia de pedidos compartido por los tres roles.
abstract class OrderRepository {
  List<Order> get all;
  Order? byId(String id);
  bool exists(String id);
  void insert(Order order);
}

class InMemoryOrderRepository implements OrderRepository {
  final List<Order> _orders = [];

  @override
  List<Order> get all => List.unmodifiable(_orders);

  @override
  Order? byId(String id) {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  @override
  bool exists(String id) => byId(id) != null;

  @override
  void insert(Order order) {
    if (exists(order.id)) {
      throw StateError('El pedido ${order.id} ya existe');
    }
    _orders.insert(0, order);
  }
}
