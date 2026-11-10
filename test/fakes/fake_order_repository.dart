import 'dart:async';
import 'dart:typed_data';

import 'package:biffy/domain/entities/order.dart';
import 'package:biffy/domain/entities/user.dart';
import 'package:biffy/domain/ports/order_ports.dart';
import 'package:biffy/domain/repositories/order_repository.dart';

/// Servidor falso del dominio: registra las llamadas y responde lo que cada
/// prueba indique. No muta pedidos por su cuenta, así que sirve para comprobar
/// que la app NO cambia el estado sin que el servidor lo confirme.
class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({this.remote = true});

  final bool remote;
  final List<Order> orders = [];
  final _changes = StreamController<void>.broadcast();

  /// Respuesta de `place`.
  OrderResult Function(PlaceOrderRequest request) onPlace = (_) =>
      const OrderResult('server_error');

  /// Respuesta por operación (`accept`, `reject`, `acceptOffer`, `deliver`…).
  final Map<String, OrderResult> responses = {};

  /// Si no es null, las operaciones esperan a que se complete.
  Completer<void>? gate;

  /// Si es true, las operaciones lanzan (un bug inesperado).
  bool throws = false;

  final List<PlaceOrderRequest> placed = [];
  final List<String> calls = [];
  int refreshes = 0;

  void notifyChanged() => _changes.add(null);

  @override
  bool get isRemote => remote;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  List<Order> get all => List.unmodifiable(orders);

  @override
  Order? byId(String id) {
    for (final o in orders) {
      if (o.id == id || o.dbId == id) return o;
    }
    return null;
  }

  @override
  Future<void> refresh() async => refreshes++;

  @override
  void insertSeed(Order order) => orders.insert(0, order);

  Future<OrderResult> _op(String name) async {
    calls.add(name);
    if (throws) throw StateError('bug');
    final g = gate;
    if (g != null) await g.future;
    return responses[name] ?? OrderResult.ok(byId(name.split(':').last));
  }

  @override
  Future<OrderResult> place(PlaceOrderRequest request) async {
    placed.add(request);
    return onPlace(request);
  }

  @override
  Future<OrderResult> accept(String orderId) => _op('accept:$orderId');

  @override
  Future<OrderResult> reject(String orderId, String reason) =>
      _op('reject:$orderId');

  @override
  Future<OrderResult> markReady(String orderId) => _op('ready:$orderId');

  @override
  Future<OrderResult> cancelByBuyer(String orderId) => _op('cancel:$orderId');

  @override
  Future<OrderResult> acceptOffer(
    String orderId,
    AppUser courier, {
    Vehicle? vehicle,
  }) => _op('acceptOffer:$orderId');

  @override
  Future<OrderResult> declineOffer(String orderId, String courierId) =>
      _op('declineOffer:$orderId');

  @override
  Future<OrderResult> confirmPickup(String orderId, String courierId) =>
      _op('pickup:$orderId');

  @override
  Future<OrderResult> deliver(
    String orderId,
    String courierId,
    String code,
    String? evidence,
    Uint8List? evidenceBytes,
  ) => _op('deliver:$orderId');

  void dispose() => _changes.close();
}

/// Billetera que anota lo que los casos de uso le piden.
class RecordingWallet implements OrderWalletPort {
  final List<String> log = [];

  @override
  void spendGotas(String userId, int amount, String reason) =>
      log.add('spend:$amount');

  @override
  void creditGotas(String userId, int amount, String reason) =>
      log.add('credit:$amount');

  @override
  void setCouponUsed(String userId, String couponId, bool used) =>
      log.add('coupon:$used');

  @override
  Future<void> syncBalance() async => log.add('sync');
}

/// Notificador que anota los avisos.
class RecordingNotifier implements OrderNotifier {
  final List<String> log = [];

  @override
  void placed(Order order, {required String businessId}) => log.add('placed');
  @override
  void buyerCancelled(Order order, {required String? businessId}) =>
      log.add('buyerCancelled');
  @override
  void accepted(Order order) => log.add('accepted');
  @override
  void rejected(Order order) => log.add('rejected');
  @override
  void ready(Order order) => log.add('ready');
  @override
  void assigned(Order order, AppUser courier, {required String? businessId}) =>
      log.add('assigned');
  @override
  void pickedUp(Order order) => log.add('pickedUp');
  @override
  void delivered(Order order, {required String? businessId}) =>
      log.add('delivered');
}
