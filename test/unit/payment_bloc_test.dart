import 'package:biffy/data/repositories/in_memory_payment_repository.dart';
import 'package:biffy/domain/entities/catalog.dart';
import 'package:biffy/domain/usecases/payments/check_payment_status.dart';
import 'package:biffy/domain/usecases/payments/retry_payment.dart';
import 'package:biffy/domain/usecases/payments/start_payment.dart';
import 'package:biffy/features/buyer/payment/bloc/payment_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del PaymentBloc con el repositorio simulado.
void main() {
  late InMemoryPaymentRepository repo;
  late PaymentBloc bloc;

  setUp(() {
    repo = InMemoryPaymentRepository(
      autoApproveAfter: const Duration(milliseconds: 5),
    );
    bloc = PaymentBloc(
      orderId: 'order-1',
      start: StartPayment(repo),
      check: CheckPaymentStatus(repo),
      retry: RetryPayment(repo),
      watch: repo.watch,
    );
  });

  tearDown(() async {
    await bloc.close();
    repo.dispose();
  });

  test('aprueba el pago y guarda el monto del servidor', () async {
    bloc.add(
      const PaymentStarted('order-1', PaymentMethod.card, amount: 23910),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(bloc.state.step, PaymentStep.approved);
    expect(bloc.state.payment?.amount, 23910);
  });

  test('rechaza con motivo y permite reintentar', () async {
    repo.rejectNext = true;
    bloc.add(const PaymentStarted('order-1', PaymentMethod.card));
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(bloc.state.step, PaymentStep.rejected);
    expect(bloc.state.message, isNotEmpty);
    expect(bloc.state.canRetry, isTrue);

    bloc.add(const PaymentRetried(PaymentMethod.card));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(bloc.state.step, PaymentStep.approved);
  });

  test('consulta el estado del pago existente', () async {
    await repo.start(
      orderId: 'order-1',
      method: PaymentMethod.nequi,
      amount: 10000,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    bloc.add(const PaymentStatusChecked());
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bloc.state.step, PaymentStep.approved);
  });
}
