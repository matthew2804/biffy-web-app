import 'catalog.dart';

/// Estado del dinero de un pedido (espejo de `public.payment_status`).
enum PaymentStatus {
  pending,
  processing,
  approved,
  rejected,
  expired,
  refunded;

  /// `true` cuando el pago ya se puede dar por cobrado.
  bool get isApproved => this == PaymentStatus.approved;

  /// `true` cuando el intento terminó sin cobrar y se puede reintentar.
  bool get allowsRetry =>
      this == PaymentStatus.pending ||
      this == PaymentStatus.processing ||
      this == PaymentStatus.rejected;
}

/// Intento de pago de un pedido.
///
/// Cada reintento crea otro [Payment]: el historial completo queda auditable.
class Payment {
  const Payment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.method,
    required this.status,
    required this.attempt,
    required this.reference,
    this.checkoutUrl,
    this.statusDetail,
    this.providerTransactionId,
    this.providerMethod,
    this.createdAt,
    this.approvedAt,
    this.refundedAt,
  });

  final String id;
  final String orderId;
  final int amount;
  final PaymentMethod method;
  final PaymentStatus status;
  final int attempt;
  final String reference;
  final String? checkoutUrl;
  final String? statusDetail;
  final String? providerTransactionId;

  /// Método real que reportó Wompi (CARD, NEQUI, PSE…), no la preferencia.
  final String? providerMethod;

  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? refundedAt;

  /// `true` si el pago ya está aprobado.
  bool get isApproved => status.isApproved;

  /// Copia el pago cambiando solo lo indicado.
  Payment copyWith({
    PaymentStatus? status,
    String? checkoutUrl,
    String? statusDetail,
    String? providerTransactionId,
    String? providerMethod,
    DateTime? approvedAt,
    DateTime? refundedAt,
  }) => Payment(
    id: id,
    orderId: orderId,
    amount: amount,
    method: method,
    status: status ?? this.status,
    attempt: attempt,
    reference: reference,
    checkoutUrl: checkoutUrl ?? this.checkoutUrl,
    statusDetail: statusDetail ?? this.statusDetail,
    providerTransactionId: providerTransactionId ?? this.providerTransactionId,
    providerMethod: providerMethod ?? this.providerMethod,
    createdAt: createdAt,
    approvedAt: approvedAt ?? this.approvedAt,
    refundedAt: refundedAt ?? this.refundedAt,
  );
}
