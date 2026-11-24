import 'package:biffy/domain/entities/payment.dart';
import 'package:biffy/domain/payment_errors.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de los mensajes de rechazo en español.
void main() {
  test('traduce los códigos de la app', () {
    expect(
      paymentErrorText(code: 'amount_mismatch'),
      contains('total'),
    );
    expect(paymentErrorText(code: 'expired'), contains('venció'));
    expect(paymentErrorText(code: 'network'), contains('conexión'));
  });

  test('traduce los detalles de tarjeta de Wompi', () {
    expect(
      paymentErrorText(detail: 'cc_rejected_insufficient_amount'),
      contains('fondos'),
    );
    expect(
      paymentErrorText(detail: 'cc_rejected_bad_filled_card_number'),
      contains('número'),
    );
    expect(
      paymentErrorText(detail: 'cc_rejected_call_for_authorize'),
      contains('banco'),
    );
    expect(
      paymentErrorText(detail: 'pse_rejected'),
      contains('PSE'),
    );
  });

  test('usa el detalle o el mensaje genérico si no lo conoce', () {
    expect(paymentErrorText(detail: 'Algo raro'), 'Algo raro');
    expect(
      paymentErrorText(detail: ''),
      'No pudimos completar el pago. Inténtalo de nuevo.',
    );
  });

  test('etiqueta los estados del pago', () {
    expect(paymentStatusLabel(PaymentStatus.approved), 'Pago aprobado');
    expect(paymentStatusLabel(PaymentStatus.rejected), 'Pago rechazado');
    expect(paymentStatusLabel(PaymentStatus.expired), 'Pago vencido');
  });
}
