import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/entities/catalog.dart';
import '../../../../domain/entities/payment.dart';
import '../../../../domain/payment_errors.dart';
import '../../../../domain/repositories/payment_repository.dart';
import '../../../../domain/usecases/payments/check_payment_status.dart';
import '../../../../domain/usecases/payments/retry_payment.dart';
import '../../../../domain/usecases/payments/start_payment.dart';

part 'payment_event.dart';
part 'payment_state.dart';

/// Bloc del pago: inicia, consulta, escucha Realtime y reintenta.
///
/// La pantalla solo reacciona al estado; el servidor (Wompi + RPC) decide el
/// estado real del dinero.
class PaymentBloc extends Bloc<PaymentEvent, PaymentState> {
  PaymentBloc({
    required this.orderId,
    required StartPayment start,
    required CheckPaymentStatus check,
    required RetryPayment retry,
    required Stream<Payment> Function(String) watch,
  }) : _start = start, // ignore: prefer_initializing_formals
       _check = check, // ignore: prefer_initializing_formals
       _retry = retry, // ignore: prefer_initializing_formals
       super(const PaymentState()) {
    on<PaymentStarted>(_onStarted);
    on<PaymentStatusChecked>(_onChecked);
    on<PaymentRetried>(_onRetried);
    on<PaymentChanged>(_onChanged);
    _sub = watch(orderId).listen((payment) => add(PaymentChanged(payment)));
  }

  /// Pedido cuyo pago se está gestionando.
  final String orderId;

  final StartPayment _start;
  final CheckPaymentStatus _check;
  final RetryPayment _retry;
  late final StreamSubscription<Payment> _sub;

  Future<void> _onStarted(
    PaymentStarted event,
    Emitter<PaymentState> emit,
  ) async {
    emit(const PaymentState(step: PaymentStep.processing));
    final result = await _start(
      orderId: event.orderId,
      method: event.method,
      amount: event.amount,
    );
    if (isClosed) return;
    if (result.code == 'already_paid') {
      add(const PaymentStatusChecked());
      return;
    }
    _applyResult(result, emit);
  }

  Future<void> _onChecked(
    PaymentStatusChecked event,
    Emitter<PaymentState> emit,
  ) async {
    final result = await _check(orderId);
    if (isClosed) return;
    _applyResult(result, emit);
  }

  Future<void> _onRetried(
    PaymentRetried event,
    Emitter<PaymentState> emit,
  ) async {
    emit(const PaymentState(step: PaymentStep.processing));
    final result = await _retry(orderId: orderId, method: event.method);
    if (isClosed) return;
    _applyResult(result, emit);
  }

  void _onChanged(PaymentChanged event, Emitter<PaymentState> emit) {
    _applyPayment(event.payment, emit);
  }

  /// Traduce el resultado de una operación al estado de la pantalla.
  void _applyResult(PaymentResult result, Emitter<PaymentState> emit) {
    final payment = result.payment;
    if (payment != null) {
      _applyPayment(payment, emit);
      return;
    }

    final network = result.code == 'network';
    final noRetry = const {
      'amount_mismatch',
      'not_found',
      'forbidden',
      'invalid_state',
      'invalid_method',
      'expired',
      'not_configured',
    }.contains(result.code);
    emit(
      PaymentState(
        step: network ? PaymentStep.networkError : PaymentStep.rejected,
        message: paymentErrorText(
          code: result.code,
          fallback: result.message,
        ),
        canRetry: !noRetry,
      ),
    );
  }

  /// Traduce el pago real al estado visible.
  void _applyPayment(Payment payment, Emitter<PaymentState> emit) {
    switch (payment.status) {
      case PaymentStatus.approved:
        emit(
          PaymentState(
            step: PaymentStep.approved,
            payment: payment,
            checkoutUrl: payment.checkoutUrl,
          ),
        );
      case PaymentStatus.rejected:
        emit(
          PaymentState(
            step: PaymentStep.rejected,
            payment: payment,
            message: paymentErrorText(detail: payment.statusDetail),
            canRetry: true,
            checkoutUrl: payment.checkoutUrl,
          ),
        );
      case PaymentStatus.expired:
        emit(
          PaymentState(
            step: PaymentStep.expired,
            payment: payment,
            message: paymentErrorText(code: 'expired'),
          ),
        );
      case PaymentStatus.refunded:
        emit(
          PaymentState(
            step: PaymentStep.expired,
            payment: payment,
            message: 'El pago fue reembolsado y el pedido se canceló.',
          ),
        );
      case PaymentStatus.pending:
      case PaymentStatus.processing:
        emit(
          PaymentState(
            step: payment.status == PaymentStatus.pending
                ? PaymentStep.pending
                : PaymentStep.processing,
            payment: payment,
            checkoutUrl: payment.checkoutUrl,
          ),
        );
    }
  }

  /// Cierra la escucha de Realtime antes de liberar el bloc.
  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
