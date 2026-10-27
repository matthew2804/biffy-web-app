import 'address.dart';
import 'cart.dart';
import 'catalog.dart';

/// Estados internos del pedido compartidos por los tres roles.
enum OrderStatus {
  pending, // Confirmado por el comprador, esperando al restaurante.
  preparing, // Aceptado por el restaurante.
  ready, // Listo para recoger (visible en ofertas).
  onTheWay, // Recogido por el repartidor.
  delivered,
  cancelled,
}

extension OrderStatusLabels on OrderStatus {
  /// Etiqueta para el comprador (4 pasos).
  String get buyerLabel => switch (this) {
    OrderStatus.pending => 'Confirmado',
    OrderStatus.preparing || OrderStatus.ready => 'Preparando',
    OrderStatus.onTheWay => 'En camino',
    OrderStatus.delivered => 'Entregado',
    OrderStatus.cancelled => 'Cancelado',
  };

  /// Paso 0..3 de la línea de tiempo del comprador.
  int get buyerStep => switch (this) {
    OrderStatus.pending => 0,
    OrderStatus.preparing || OrderStatus.ready => 1,
    OrderStatus.onTheWay => 2,
    OrderStatus.delivered => 3,
    OrderStatus.cancelled => -1,
  };

  String get kitchenLabel => switch (this) {
    OrderStatus.pending => 'Nuevo',
    OrderStatus.preparing => 'En preparación',
    OrderStatus.ready => 'Listo',
    OrderStatus.onTheWay => 'En camino',
    OrderStatus.delivered => 'Entregado',
    OrderStatus.cancelled => 'Rechazado',
  };

  bool get isFinal =>
      this == OrderStatus.delivered || this == OrderStatus.cancelled;
}

class OrderLine {
  const OrderLine({
    required this.dishId,
    required this.name,
    required this.emoji,
    required this.qty,
    required this.unitPrice,
    required this.selection,
    this.detail = '',
    this.note = '',
  });

  final String dishId;
  final String name;
  final String emoji;
  final int qty;
  final int unitPrice;
  final DishSelection selection;

  /// Resumen legible de la personalización.
  final String detail;
  final String note;

  int get total => unitPrice * qty;
}

class StatusEvent {
  const StatusEvent(this.status, this.at, [this.by = '']);
  final OrderStatus status;
  final DateTime at;
  final String by;
}

class Order {
  Order({
    required this.id,
    required this.buyerId,
    required this.buyerName,
    required this.restaurantId,
    required this.restaurantName,
    required this.lines,
    required this.address,
    required this.pointId,
    required this.payment,
    required this.createdAt,
    required this.subtotal,
    required this.campusDiscount,
    required this.couponDiscount,
    required this.deliveryFee,
    required this.gotasUsed,
    required this.tip,
    required this.total,
    required this.deliveryCode,
    required this.pickupCode,
    required this.etaMin,
    required this.courierPay,
    required this.distanceKm,
    this.scheduledFor,
    this.restaurantNote = '',
    this.status = OrderStatus.pending,
    this.couponId,
  }) : history = [StatusEvent(OrderStatus.pending, createdAt, 'Comprador')];

  final String id;
  final String buyerId;
  final String buyerName;
  final String restaurantId;
  final String restaurantName;
  final List<OrderLine> lines;
  final Address address;
  final String pointId;
  final PaymentMethod payment;
  final DateTime createdAt;
  final DateTime? scheduledFor;
  final String restaurantNote;
  final int subtotal;
  final int campusDiscount;
  final int couponDiscount;
  final int deliveryFee;
  final int gotasUsed;
  final int tip;
  final int total;
  final String deliveryCode;
  final String pickupCode;
  final int etaMin;
  final int courierPay;
  final double distanceKm;
  final String? couponId;

  // Estado mutable: solo lo modifica OrderService.
  OrderStatus status;
  String? courierId;
  String? courierName;
  String? rejectReason;
  String? evidence;
  DateTime? deliveredAt;
  bool gotasCredited = false;
  final Set<String> declinedBy = {};
  final List<StatusEvent> history;

  /// Identificador en Supabase (uuid). `null` en modo demo o hasta que el
  /// RPC `place_order` confirma.
  String? dbId;

  int get gotasDiscount => gotasUsed * 10;
  int get itemCount => lines.fold(0, (s, l) => s + l.qty);

  /// Ingreso del restaurante (productos menos descuento de campus).
  int get restaurantRevenue => subtotal - campusDiscount;

  /// Ganancia del repartidor (pago base + propina íntegra).
  int get courierEarning => courierPay + tip;

  bool get isScheduled => scheduledFor != null;

  String get itemsSummary => lines.map((l) => '${l.qty}× ${l.name}').join(', ');
}
