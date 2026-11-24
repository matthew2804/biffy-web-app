part of 'payment_bloc.dart';

/// Eventos del pago de un pedido.
sealed class PaymentEvent {
  const PaymentEvent();
}

/// Inicia (o reutiliza) el pago del pedido con un método.
final class PaymentStarted extends PaymentEvent {
  const PaymentStarted(this.orderId, this.method, {this.amount});

  final String orderId;
  final PaymentMethod method;

  /// Total que vio el comprador (el servidor lo vuelve a calcular).
  final int? amount;
}

/// Consulta el estado actual (al volver de Wompi o al reabrir la app).
final class PaymentStatusChecked extends PaymentEvent {
  const PaymentStatusChecked();
}

/// Reintenta el pago del mismo pedido.
final class PaymentRetried extends PaymentEvent {
  const PaymentRetried(this.method);

  final PaymentMethod method;
}

/// Llegó un cambio de pago por Realtime o por el propio repositorio.
final class PaymentChanged extends PaymentEvent {
  const PaymentChanged(this.payment);

  final Payment payment;
}
