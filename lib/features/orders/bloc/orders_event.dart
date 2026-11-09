part of 'orders_bloc.dart';

/// Eventos del ciclo del pedido. La UI solo despacha estos eventos; el
/// resultado vuelve en [OrdersState.outcome].
sealed class OrdersEvent {
  const OrdersEvent();
}

/// El repositorio cambió (Realtime, recarga o una transición): refresca la lista.
final class OrdersChanged extends OrdersEvent {
  const OrdersChanged();
}

/// Comprador: confirmar el pedido. [clientKey] hace seguro el reintento.
final class OrderPlaced extends OrdersEvent {
  const OrderPlaced(this.draft, {this.clientKey});
  final CheckoutDraft draft;
  final String? clientKey;
}

/// Comprador: cancelar antes de que el restaurante acepte.
final class OrderCancelled extends OrdersEvent {
  const OrderCancelled(this.orderId);
  final String orderId;
}

/// Restaurante: aceptar el pedido.
final class OrderAccepted extends OrdersEvent {
  const OrderAccepted(this.orderId);
  final String orderId;
}

/// Restaurante: rechazar con un motivo.
final class OrderRejected extends OrdersEvent {
  const OrderRejected(this.orderId, this.reason);
  final String orderId;
  final String reason;
}

/// Restaurante: el pedido está listo para recoger.
final class OrderMarkedReady extends OrdersEvent {
  const OrderMarkedReady(this.orderId);
  final String orderId;
}

/// Repartidor: aceptar una oferta (asignación atómica).
final class OfferAccepted extends OrdersEvent {
  const OfferAccepted(this.orderId, this.courier, {this.vehicle});
  final String orderId;
  final AppUser courier;
  final Vehicle? vehicle;
}

/// Repartidor: rechazar una oferta.
final class OfferDeclined extends OrdersEvent {
  const OfferDeclined(this.orderId, this.courierId);
  final String orderId;
  final String courierId;
}

/// Repartidor: confirmar la recogida con los tres checks.
final class PickupConfirmed extends OrdersEvent {
  const PickupConfirmed(
    this.orderId,
    this.courierId, {
    required this.codeValidated,
    required this.bagSealed,
    required this.productsVerified,
  });
  final String orderId;
  final String courierId;
  final bool codeValidated;
  final bool bagSealed;
  final bool productsVerified;
}

/// Repartidor: entregar con el código del cliente y la foto de evidencia.
final class DeliveryCompleted extends OrdersEvent {
  const DeliveryCompleted(
    this.orderId,
    this.courierId,
    this.code,
    this.evidence, {
    this.evidenceBytes,
  });
  final String orderId;
  final String courierId;
  final String code;
  final String? evidence;
  final Uint8List? evidenceBytes;
}
