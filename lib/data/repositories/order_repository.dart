import '../models/order.dart';

/// Contrato de persistencia de pedidos compartido por los tres roles.
abstract class OrderRepository {
  /// Todos los pedidos conocidos (solo lectura).
  List<Order> get all;
  /// Pedido por código o uuid.
  Order? byId(String id);
  /// `true` si el pedido ya está registrado.
  bool exists(String id);
  /// Inserta un pedido nuevo.
  void insert(Order order);
}

/// Pedidos de demostración guardados en memoria.
class InMemoryOrderRepository implements OrderRepository {
  final List<Order> _orders = [];

  /// Pedidos registrados (solo lectura).
  @override
  List<Order> get all => List.unmodifiable(_orders);

  /// Busca un pedido por código o uuid.
  @override
  Order? byId(String id) {
    for (final o in _orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Comprueba si el código ya existe.
  @override
  bool exists(String id) => byId(id) != null;

  /// Inserta el pedido al inicio y rechaza duplicados.
  @override
  void insert(Order order) {
    if (exists(order.id)) {
      throw StateError('El pedido ${order.id} ya existe');
    }
    _orders.insert(0, order);
  }
}
