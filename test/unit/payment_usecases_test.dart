import 'package:biffy/domain/entities/catalog.dart';
import 'package:biffy/domain/entities/payment.dart';
import 'package:biffy/domain/repositories/payment_repository.dart';
import 'package:biffy/domain/usecases/payments/check_payment_status.dart';
import 'package:biffy/domain/usecases/payments/retry_payment.dart';
import 'package:biffy/domain/usecases/payments/start_payment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio falso para comprobar que los casos de uso delegan bien.
class _FakeRepo implements PaymentRepository {
  int starts = 0;
  int checks = 0;
  int retries = 0;
  String? lastOrder;
  PaymentMethod? lastMethod;
  int? lastAmount;

  @override
  bool get isRemote => true;

  @override
  Future<PaymentResult> start({
    required String orderId,
    required PaymentMethod method,
    int? amount,
  }) async {
    starts++;
    lastOrder = orderId;
    lastMethod = method;
    lastAmount = amount;
    return PaymentResult.ok(_payment(status: PaymentStatus.pending));
  }

  @override
  Future<PaymentResult> status(String orderId) async {
    checks++;
    lastOrder = orderId;
    return PaymentResult.ok(_payment(status: PaymentStatus.approved));
  }

  @override
  Future<PaymentResult> retry({
    required String orderId,
    required PaymentMethod method,
  }) async {
    retries++;
    lastOrder = orderId;
    lastMethod = method;
    return PaymentResult.ok(_payment(status: PaymentStatus.pending, attempt: 2));
  }

  @override
  Future<PaymentResult> refund(String orderId, {String reason = 'Cancelación'}) async =>
      PaymentResult.ok(_payment(status: PaymentStatus.refunded));

  @override
  Stream<Payment> watch(String orderId) => const Stream.empty();

  @override
  void dispose() {}
}

Payment _payment({PaymentStatus status = PaymentStatus.pending, int attempt = 1}) =>
    Payment(
      id: 'pay-1',
      orderId: 'order-1',
      amount: 23910,
      method: PaymentMethod.card,
      status: status,
      attempt: attempt,
      reference: 'BF-1-1-abc',
    );

void main() {
  late _FakeRepo repo;

  setUp(() => repo = _FakeRepo());

  test('StartPayment delega monto y método', () async {
    final result = await StartPayment(repo)(
      orderId: 'order-1',
      method: PaymentMethod.nequi,
      amount: 23910,
    );

    expect(result.ok, isTrue);
    expect(repo.starts, 1);
    expect(repo.lastOrder, 'order-1');
    expect(repo.lastMethod, PaymentMethod.nequi);
    expect(repo.lastAmount, 23910);
  });

  test('CheckPaymentStatus consulta el pedido', () async {
    final result = await CheckPaymentStatus(repo)('order-1');

    expect(result.payment?.status, PaymentStatus.approved);
    expect(repo.checks, 1);
    expect(repo.lastOrder, 'order-1');
  });

  test('RetryPayment crea el intento 2', () async {
    final result = await RetryPayment(repo)(
      orderId: 'order-1',
      method: PaymentMethod.card,
    );

    expect(result.payment?.attempt, 2);
    expect(repo.retries, 1);
  });
}
