import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/utils/clock.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/user.dart';
import '../../domain/order_rules.dart';
import '../../domain/repositories/order_repository.dart';

/// Pedidos en memoria para el modo demo y las pruebas.
///
/// Hace de «servidor falso»: aplica las mismas reglas de transición que los RPC
/// de Supabase y devuelve los mismos códigos (`invalid_state`,
/// `already_assigned`, `busy`, `wrong_code`…), así los casos de uso y la UI se
/// comportan igual en ambos modos.
class InMemoryOrderRepository implements OrderRepository {
  InMemoryOrderRepository(this._clock, {math.Random? random})
    : _rnd = random ?? math.Random();

  final Clock _clock;
  final math.Random _rnd;
  final List<Order> _orders = [];
  final Map<String, Order> _byClientKey = {};
  final _changes = StreamController<void>.broadcast();
  int _counter = 2041;

  @override
  bool get isRemote => false;

  @override
  Stream<void> get changes => _changes.stream;

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
  Future<void> refresh() async {}

  @override
  void insertSeed(Order order) {
    if (byId(order.id) != null) {
      throw StateError('El pedido ${order.id} ya existe');
    }
    _orders.insert(0, order);
    _emit();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  String _nextId() {
    String id;
    do {
      id = 'BF-${_counter++}';
    } while (byId(id) != null);
    return id;
  }

  // ------------------------------------------------------------- Comprador

  @override
  Future<OrderResult> place(PlaceOrderRequest r) async {
    final previous = _byClientKey[r.clientKey];
    if (previous != null) return OrderResult.ok(previous);

    final t = r.totals;
    final order = Order(
      id: _nextId(),
      buyerId: r.buyer.id,
      buyerName: r.buyer.name,
      restaurantId: r.restaurant.id,
      restaurantName: r.restaurant.name,
      lines: r.lines,
      address: r.address,
      pointId: r.pointId,
      payment: r.payment,
      createdAt: _clock.now(),
      scheduledFor: r.scheduledFor,
      restaurantNote: r.restaurantNote,
      subtotal: t.subtotal,
      campusDiscount: t.campusDiscount,
      couponDiscount: t.couponDiscount,
      deliveryFee: t.deliveryFee,
      gotasUsed: t.gotasUsed,
      tip: t.tip,
      total: t.total,
      deliveryCode: fourDigitCode(_rnd),
      pickupCode: fourDigitCode(_rnd),
      etaMin: r.etaMin,
      courierPay: r.courierPay,
      distanceKm: r.distanceKm,
      couponId: r.couponId,
    );
    _orders.insert(0, order);
    _byClientKey[r.clientKey] = order;
    _emit();
    return OrderResult.ok(order);
  }

  @override
  Future<OrderResult> cancelByBuyer(String orderId) async {
    final o = byId(orderId);
    if (o == null) return const OrderResult('not_found');
    if (o.status != OrderStatus.pending) {
      return const OrderResult('invalid_state');
    }
    _move(o, OrderStatus.cancelled, 'Comprador');
    o.rejectReason = 'Cancelado por el comprador';
    _emit();
    return OrderResult.ok(o);
  }

  // ----------------------------------------------------------- Restaurante

  @override
  Future<OrderResult> accept(String orderId) =>
      _transition(orderId, OrderStatus.preparing, 'Restaurante');

  @override
  Future<OrderResult> markReady(String orderId) =>
      _transition(orderId, OrderStatus.ready, 'Restaurante');

  @override
  Future<OrderResult> reject(String orderId, String reason) async {
    final res = await _transition(
      orderId,
      OrderStatus.cancelled,
      'Restaurante',
      afterMove: (o) => o.rejectReason = reason,
    );
    return res;
  }

  // ------------------------------------------------------------ Repartidor

  @override
  Future<OrderResult> acceptOffer(
    String orderId,
    AppUser courier, {
    Vehicle? vehicle,
  }) async {
    final o = byId(orderId);
    if (o == null || o.status != OrderStatus.ready) {
      return const OrderResult('not_available');
    }
    if (o.courierId != null) return const OrderResult('already_assigned');
    if (_activeFor(courier.id) != null) return const OrderResult('busy');
    if (vehicle != null && !courierCanTake(o, vehicle)) {
      return const OrderResult('out_of_range');
    }
    o.courierId = courier.id;
    o.courierName = courier.name;
    o.history.add(StatusEvent(o.status, _clock.now(), 'Repartidor asignado'));
    _emit();
    return OrderResult.ok(o);
  }

  @override
  Future<OrderResult> declineOffer(String orderId, String courierId) async {
    final o = byId(orderId);
    if (o == null) return const OrderResult('not_found');
    o.declinedBy.add(courierId);
    _emit();
    return OrderResult.ok(o);
  }

  @override
  Future<OrderResult> confirmPickup(String orderId, String courierId) async {
    final o = byId(orderId);
    if (o == null) return const OrderResult('not_found');
    if (o.courierId != courierId) return const OrderResult('forbidden');
    if (o.status != OrderStatus.ready) {
      return const OrderResult('invalid_state');
    }
    _move(o, OrderStatus.onTheWay, 'Repartidor');
    _emit();
    return OrderResult.ok(o);
  }

  @override
  Future<OrderResult> deliver(
    String orderId,
    String courierId,
    String code,
    String? evidence,
    Uint8List? evidenceBytes,
  ) async {
    final o = byId(orderId);
    if (o == null ||
        o.courierId != courierId ||
        o.status != OrderStatus.onTheWay) {
      return const OrderResult('invalid_state');
    }
    if (!validateDeliveryCode(o, code)) return const OrderResult('wrong_code');
    if (!validateEvidence(evidence)) {
      return const OrderResult('missing_evidence');
    }
    _move(o, OrderStatus.delivered, 'Repartidor');
    o.evidence = evidence;
    o.deliveredAt = _clock.now();
    o.gotasCredited = true;
    _emit();
    return OrderResult.ok(o);
  }

  // --------------------------------------------------------------- Helpers

  Order? _activeFor(String courierId) {
    for (final o in _orders) {
      if (o.courierId == courierId &&
          (o.status == OrderStatus.ready || o.status == OrderStatus.onTheWay)) {
        return o;
      }
    }
    return null;
  }

  Future<OrderResult> _transition(
    String orderId,
    OrderStatus to,
    String by, {
    void Function(Order o)? afterMove,
  }) async {
    final o = byId(orderId);
    if (o == null) return const OrderResult('not_found');
    if (!canTransition(o.status, to)) return const OrderResult('invalid_state');
    _move(o, to, by);
    afterMove?.call(o);
    _emit();
    return OrderResult.ok(o);
  }

  void _move(Order o, OrderStatus to, String by) {
    o.status = to;
    o.history.add(StatusEvent(to, _clock.now(), by));
  }

  void dispose() => _changes.close();
}
