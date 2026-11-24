import 'package:biffy/data/repositories/in_memory_payment_repository.dart';
import 'package:biffy/domain/entities/catalog.dart';
import 'package:biffy/domain/entities/payment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del pago simulado (demo y widget tests).
void main() {
  test('aprueba el pago después del tiempo configurado', () async {
    final repo = InMemoryPaymentRepository(autoApproveAfter: Duration.zero);
    addTearDown(repo.dispose);

    final started = await repo.start(
      orderId: 'order-1',
      method: PaymentMethod.card,
      amount: 23910,
    );
    expect(started.ok, isTrue);
    expect(started.payment?.status, PaymentStatus.pending);
    expect(started.payment?.attempt, 1);

    await Future<void>.delayed(const Duration(milliseconds: 10));
    final status = await repo.status('order-1');
    expect(status.payment?.status, PaymentStatus.approved);
  });

  test('publica pendiente y aprobado en el stream', () async {
    final repo = InMemoryPaymentRepository(autoApproveAfter: Duration.zero);
    addTearDown(repo.dispose);
    final seen = <PaymentStatus>[];
    final sub = repo.watch('order-1').listen((p) => seen.add(p.status));

    await repo.start(orderId: 'order-1', method: PaymentMethod.nequi);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(seen, [PaymentStatus.pending, PaymentStatus.approved]);
    await sub.cancel();
  });

  test('rechaza, permite reintentar y luego aprueba', () async {
    final repo = InMemoryPaymentRepository(
      autoApproveAfter: const Duration(milliseconds: 5),
    );
    addTearDown(repo.dispose);
    repo.rejectNext = true;

    await repo.start(orderId: 'order-2', method: PaymentMethod.card);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      (await repo.status('order-2')).payment?.status,
      PaymentStatus.rejected,
    );

    final retry = await repo.retry(
      orderId: 'order-2',
      method: PaymentMethod.card,
    );
    expect(retry.payment?.attempt, 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      (await repo.status('order-2')).payment?.status,
      PaymentStatus.approved,
    );
  });

  test('registra el reembolso y devuelve not_found si no hay pago', () async {
    final repo = InMemoryPaymentRepository();
    addTearDown(repo.dispose);

    expect((await repo.status('nope')).code, 'not_found');

    await repo.start(orderId: 'order-3', method: PaymentMethod.pse);
    final refunded = await repo.refund('order-3', reason: 'Prueba');
    expect(refunded.payment?.status, PaymentStatus.refunded);
  });
}
