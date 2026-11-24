import '../../core/utils/format.dart';
import '../../domain/entities/catalog.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/user.dart';
import '../../domain/ports/order_ports.dart';
import '../state/catalog_controller.dart';
import '../state/notification_center.dart';
import '../state/session_controller.dart';

/// Conecta el puerto de catálogo del dominio con `CatalogController`.
class CatalogOrderAdapter implements OrderCatalogPort {
  CatalogOrderAdapter(this._catalog);
  final CatalogController _catalog;

  @override
  Dish? dishById(String id) => _catalog.dishById(id);

  @override
  Restaurant? restaurantById(String id) => _catalog.restaurantById(id);

  @override
  List<Restaurant> branchesOf(String businessId) =>
      _catalog.branchesOf(businessId);

  @override
  void recordSale(String dishId, int qty) => _catalog.recordSale(dishId, qty);
}

/// Conecta los puertos de comprador y billetera con `SessionController`.
class SessionOrderAdapter implements OrderBuyerPort, OrderWalletPort {
  SessionOrderAdapter(this._session);
  final SessionController _session;

  @override
  String? verifiedUniversityId(String userId) =>
      _session.dataFor(userId).verifiedUniversityId;

  @override
  int gotasOf(String userId) => _session.dataFor(userId).gotas;

  @override
  DeliveryPoint get currentPoint => _session.point;

  @override
  void spendGotas(String userId, int amount, String reason) =>
      _session.spendGotas(userId, amount, reason);

  @override
  void creditGotas(String userId, int amount, String reason) =>
      _session.creditGotas(userId, amount, reason);

  @override
  void setCouponUsed(String userId, String couponId, bool used) =>
      _session.setCouponUsed(userId, couponId, used);

  @override
  Future<void> syncBalance() => _session.syncGotas();
}

/// Convierte los hitos del pedido en notificaciones locales.
///
/// [demo] cambia solo el texto del aviso de creación («sin cobros reales»).
class NotificationOrderAdapter implements OrderNotifier {
  NotificationOrderAdapter(this._center, {required this.demo});
  final NotificationCenter _center;
  final bool demo;

  @override
  void placed(Order order, {required String businessId}) {
    final scheduled = order.scheduledFor;
    final when = scheduled == null ? '' : ' para ${dateTimeLabel(scheduled)}';
    _center.push(
      title: 'Pedido ${order.id} creado',
      body: demo
          ? 'Pedido de demostración$when · sin cobros reales.'
          : 'Tu pedido fue enviado a ${order.restaurantName}$when.',
      audience: 'user:${order.buyerId}',
      route: '/pedido/${order.id}',
    );
    _center.push(
      title: 'Nuevo pedido ${order.id}',
      body: '${order.itemsSummary}$when',
      audience: 'business:$businessId',
      route: '/negocio/pedidos',
    );
  }

  @override
  void buyerCancelled(Order o, {required String? businessId}) {
    _center.push(
      title: 'Pedido ${o.id} cancelado por el cliente',
      body: o.itemsSummary,
      audience: 'business:$businessId',
      route: '/negocio/pedidos',
    );
  }

  @override
  void accepted(Order o) {
    _center.push(
      title: 'Pedido aceptado por el restaurante',
      body: '${o.restaurantName} aceptó tu pedido ${o.id}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    _center.push(
      title: 'Pedido en preparación 👩‍🍳',
      body: 'Tu pedido ${o.id} se está preparando.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
  }

  @override
  void rejected(Order o) {
    _center.push(
      title: 'Pedido ${o.id} rechazado',
      body: 'Motivo: ${o.rejectReason}. No se realizó ningún cobro.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
  }

  @override
  void ready(Order o) {
    _center.push(
      title: 'Pedido listo 🛍️',
      body:
          '${o.restaurantName} terminó tu pedido ${o.id}. Buscando repartidor.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    _center.push(
      title: 'Oferta disponible · ${cop(o.courierPay)}',
      body: '${o.restaurantName} → ${o.address.label} (${o.distanceKm} km).',
      audience: 'couriers',
      route: '/repartidor/oferta/${o.id}',
    );
  }

  @override
  void assigned(Order o, AppUser courier, {required String? businessId}) {
    _center.push(
      title: 'Repartidor asignado 🛵',
      body: '${courier.name} recogerá tu pedido ${o.id}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    _center.push(
      title: 'Pedido ${o.id} asignado',
      body: 'Ve a ${o.restaurantName} y muestra el código ${o.pickupCode}.',
      audience: 'courier:${courier.id}',
      route: '/repartidor/recogida/${o.id}',
    );
    _center.push(
      title: 'Repartidor asignado a ${o.id}',
      body: '${courier.name} va en camino a recoger.',
      audience: 'business:$businessId',
      route: '/negocio/pedidos',
    );
  }

  @override
  void pickedUp(Order o) {
    _center.push(
      title: 'Pedido en camino 🛵',
      body:
          '${o.courierName} recogió tu pedido ${o.id}. Ten listo el código ${o.deliveryCode}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
  }

  @override
  void delivered(Order o, {required String? businessId}) {
    _center.push(
      title: 'Pedido entregado ✅',
      body: '¡Buen provecho! Ganaste ${o.subtotal ~/ 1000} Gotas con ${o.id}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    _center.push(
      title: 'Pedido ${o.id} entregado',
      body: 'Entregado por ${o.courierName}.',
      audience: 'business:$businessId',
      route: '/negocio/pedidos',
    );
  }
}
