part of 'payment_bloc.dart';

/// Etapa visible del pago.
enum PaymentStep {
  idle,
  processing,
  pending,
  approved,
  rejected,
  expired,
  networkError,
}

/// Estado del pago para la pantalla.
class PaymentState {
  const PaymentState({
    this.step = PaymentStep.idle,
    this.payment,
    this.message,
    this.checkoutUrl,
    this.canRetry = false,
  });

  final PaymentStep step;
  final Payment? payment;
  final String? message;
  final String? checkoutUrl;
  final bool canRetry;

  /// `true` mientras se crea/consulta el pago.
  bool get isBusy =>
      step == PaymentStep.processing || step == PaymentStep.idle;

  /// `true` si ya no se puede reintentar sobre este pedido.
  bool get isClosed =>
      step == PaymentStep.approved || step == PaymentStep.expired;

  /// Copia el estado cambiando solo lo indicado.
  PaymentState copyWith({
    PaymentStep? step,
    Payment? payment,
    String? message,
    String? checkoutUrl,
    bool? canRetry,
  }) => PaymentState(
    step: step ?? this.step,
    payment: payment ?? this.payment,
    message: message,
    checkoutUrl: checkoutUrl ?? this.checkoutUrl,
    canRetry: canRetry ?? this.canRetry,
  );
}
