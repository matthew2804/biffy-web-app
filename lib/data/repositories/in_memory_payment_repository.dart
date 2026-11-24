import 'dart:async';

import '../../domain/entities/catalog.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payment_repository.dart';

/// Pago simulado para la demo y las pruebas: no hay red ni cobros reales.
///
/// Al iniciar crea un intento `pending` y, tras [autoApproveAfter], lo aprueba
/// (o lo rechaza si [rejectNext] está activo). Así el flujo del carrito se
/// puede probar completo sin Wompi.
class InMemoryPaymentRepository implements PaymentRepository {
  InMemoryPaymentRepository({
    this.autoApproveAfter = const Duration(seconds: 2),
  });

  /// Tiempo antes de resolver el pago simulado.
  final Duration autoApproveAfter;

  /// Cuando es `true`, el próximo intento se rechaza (para demo/pruebas).
  bool rejectNext = false;

  final Map<String, Payment> _latest = {};
  final StreamController<Payment> _changes =
      StreamController<Payment>.broadcast();
  final Map<String, Timer> _timers = {};
  int _seq = 0;

  @override
  bool get isRemote => false;

  @override
  Future<PaymentResult> start({
    required String orderId,
    required PaymentMethod method,
    int? amount,
  }) async {
    final current = _latest[orderId];
    if (current != null && current.status == PaymentStatus.approved) {
      return PaymentResult.ok(current);
    }

    final attempt = (current?.attempt ?? 0) + 1;
    final payment = Payment(
      id: 'demo-${++_seq}',
      orderId: orderId,
      amount: amount ?? current?.amount ?? 0,
      method: method,
      status: PaymentStatus.pending,
      attempt: attempt,
      reference: 'demo-$orderId-$attempt',
      createdAt: DateTime.now(),
    );
    _latest[orderId] = payment;
    _changes.add(payment);

    _timers[orderId]?.cancel();
    _timers[orderId] = Timer(autoApproveAfter, () {
      final latest = _latest[orderId];
      if (latest == null || latest.id != payment.id) return;
      final rejected = rejectNext;
      rejectNext = false;
      final next = latest.copyWith(
        status: rejected ? PaymentStatus.rejected : PaymentStatus.approved,
        statusDetail: rejected ? 'cc_rejected_insufficient_amount' : null,
        approvedAt: rejected ? null : DateTime.now(),
      );
      _latest[orderId] = next;
      _changes.add(next);
    });

    return PaymentResult.ok(payment);
  }

  @override
  Future<PaymentResult> status(String orderId) {
    final payment = _latest[orderId];
    if (payment == null) return Future.value(const PaymentResult('not_found'));
    return Future.value(PaymentResult.ok(payment));
  }

  @override
  Future<PaymentResult> retry({
    required String orderId,
    required PaymentMethod method,
  }) => start(orderId: orderId, method: method);

  @override
  Future<PaymentResult> refund(
    String orderId, {
    String reason = 'Cancelación',
  }) {
    final payment = _latest[orderId];
    if (payment == null) return Future.value(const PaymentResult('not_found'));
    final next = payment.copyWith(
      status: PaymentStatus.refunded,
      refundedAt: DateTime.now(),
    );
    _latest[orderId] = next;
    _changes.add(next);
    return Future.value(PaymentResult.ok(next));
  }

  @override
  Stream<Payment> watch(String orderId) => _changes.stream;

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _changes.close();
  }
}
