import 'dart:typed_data';

import '../entities/address.dart';
import '../entities/catalog.dart';
import '../entities/order.dart';
import '../entities/user.dart';
import '../order_errors.dart' as errors;
import '../pricing.dart';

/// Resultado de una operación de pedidos, igual en modo demo y con servidor.
///
/// [code] usa el mismo vocabulario que los RPC de Supabase (`ok`,
/// `invalid_state`, `forbidden`, `already_assigned`, `wrong_code`, …) más
/// `validation` para errores detectados antes de llamar al repositorio.
class OrderResult {
  const OrderResult(this.code, {this.order, this.data = const {}});

  const OrderResult.ok([Order? order]) : this('ok', order: order);

  /// Error de validación local con un mensaje ya listo para la persona.
  factory OrderResult.validation(String message) =>
      OrderResult('validation', data: {'message': message});

  final String code;
  final Order? order;
  final Map<String, dynamic> data;

  bool get ok => code == 'ok';

  /// Mensaje en español para mostrar; nunca expone el código crudo.
  String get message => (data['message'] as String?) ?? errors.orderErrorMessage(code, data);

  /// Falló la conexión: el servidor pudo o no procesar la petición.
  bool get isTransportError => errors.isTransportError(code);

  @override
  String toString() => 'OrderResult($code)';
}

/// Todo lo necesario para crear un pedido, ya calculado por el caso de uso.
///
/// Con servidor, `place_order` recalcula precios y descuentos y rechaza si no
/// coinciden con [totals]; en modo demo el repositorio en memoria usa estos
/// valores tal cual.
class PlaceOrderRequest {
  const PlaceOrderRequest({
    required this.buyer,
    required this.restaurant,
    required this.address,
    required this.payment,
    required this.lines,
    required this.totals,
    required this.pointId,
    required this.distanceKm,
    required this.etaMin,
    required this.courierPay,
    required this.clientKey,
    this.scheduledFor,
    this.restaurantNote = '',
    this.couponId,
  });

  final AppUser buyer;
  final Restaurant restaurant;
  final Address address;
  final PaymentMethod payment;
  final List<OrderLine> lines;
  final CartTotals totals;
  final String pointId;
  final double distanceKm;
  final int etaMin;
  final int courierPay;

  /// Clave de idempotencia: reintentar con la misma clave no duplica el pedido.
  final String clientKey;
  final DateTime? scheduledFor;
  final String restaurantNote;
  final String? couponId;
}

/// Persistencia y reglas de transición de pedidos, compartidas por los tres
/// roles. Hay dos implementaciones: en memoria (demo, tests) y Supabase.
///
/// Las lecturas son síncronas sobre una caché; las escrituras son asíncronas y
/// devuelven un [OrderResult] con el mismo vocabulario en ambos modos.
abstract class OrderRepository {
  /// Pedidos visibles para el usuario actual, el más reciente primero.
  List<Order> get all;

  /// Busca por código visible (`BF-2041`) o por identificador interno.
  Order? byId(String id);

  /// Avisa cuando la caché cambió (Realtime, recarga o una transición).
  Stream<void> get changes;

  /// `true` cuando los pedidos viven en un servidor. Implica que el servidor
  /// mueve las Gotas y los cupones, y que las direcciones y cupones deben
  /// existir en la cuenta (identificados con uuid).
  bool get isRemote;

  /// Relee desde la fuente (no hace nada en memoria). Nunca lanza.
  Future<void> refresh();

  Future<OrderResult> place(PlaceOrderRequest request);

  // Restaurante
  Future<OrderResult> accept(String orderId);
  Future<OrderResult> reject(String orderId, String reason);
  Future<OrderResult> markReady(String orderId);

  // Comprador
  Future<OrderResult> cancelByBuyer(String orderId);

  // Repartidor
  Future<OrderResult> acceptOffer(
    String orderId,
    AppUser courier, {
    Vehicle? vehicle,
  });
  Future<OrderResult> declineOffer(String orderId, String courierId);
  Future<OrderResult> confirmPickup(String orderId, String courierId);
  Future<OrderResult> deliver(
    String orderId,
    String courierId,
    String code,
    String? evidence,
    Uint8List? evidenceBytes,
  );

  /// Inserta un pedido semilla (solo datos de demostración).
  void insertSeed(Order order);
}
