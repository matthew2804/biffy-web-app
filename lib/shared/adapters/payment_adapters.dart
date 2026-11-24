import '../../domain/entities/catalog.dart';
import '../../domain/entities/payment.dart';

/// Convierte el nombre del método que guarda la base al enum de la app.
PaymentMethod paymentMethodFromDb(String? value) => switch (value) {
  'nequi' => PaymentMethod.nequi,
  'daviplata' => PaymentMethod.daviplata,
  'pse' => PaymentMethod.pse,
  'cash' => PaymentMethod.cash,
  _ => PaymentMethod.card,
};

/// Convierte el estado de la base al enum de la app.
PaymentStatus paymentStatusFromDb(String? value) => switch (value) {
  'approved' => PaymentStatus.approved,
  'rejected' => PaymentStatus.rejected,
  'expired' => PaymentStatus.expired,
  'refunded' => PaymentStatus.refunded,
  'processing' => PaymentStatus.processing,
  _ => PaymentStatus.pending,
};

/// Fecha opcional de una fila de Supabase.
DateTime? _date(Object? value) =>
    DateTime.tryParse((value ?? '').toString());

/// Convierte una fila de `payments` en la entidad del dominio.
Payment paymentFromRow(Map<String, dynamic> row) => Payment(
  id: (row['id'] ?? '').toString(),
  orderId: (row['order_id'] ?? '').toString(),
  amount: (row['amount'] as num?)?.toInt() ?? 0,
  method: paymentMethodFromDb(row['method'] as String?),
  status: paymentStatusFromDb(row['status'] as String?),
  attempt: (row['attempt'] as num?)?.toInt() ?? 1,
  reference: (row['reference'] as String?) ?? '',
  checkoutUrl: row['checkout_url'] as String?,
  statusDetail: row['status_detail'] as String?,
  providerTransactionId: row['provider_transaction_id'] as String?,
  createdAt: _date(row['created_at']),
  approvedAt: _date(row['approved_at']),
  refundedAt: _date(row['refunded_at']),
);

/// Extrae el pago de la respuesta `{result, payment}` de `payment_for_order`.
Payment? paymentFromRpc(Object? json) {
  if (json is! Map) return null;
  final map = Map<String, dynamic>.from(json);
  if (map['result'] != 'ok') return null;
  final payment = map['payment'];
  if (payment is! Map) return null;
  return paymentFromRow(Map<String, dynamic>.from(payment));
}
