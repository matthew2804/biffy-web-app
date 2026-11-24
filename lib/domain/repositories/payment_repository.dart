import '../entities/catalog.dart';
import '../entities/payment.dart';

/// Resultado de una operación de pago.
///
/// [code] usa el mismo vocabulario en memoria y con Wompi: `ok`,
/// `amount_mismatch`, `not_found`, `forbidden`, `invalid_state`, `expired`,
/// `already_paid`, `network`, `server_error`, `not_configured`.
class PaymentResult {
  const PaymentResult(
    this.code, {
    this.payment,
    this.expected,
    this.message,
  });

  /// Resultado correcto con su pago.
  const PaymentResult.ok(this.payment)
    : code = 'ok',
      expected = null,
      message = null;

  final String code;
  final Payment? payment;

  /// Total que esperaba el servidor (solo en `amount_mismatch`).
  final int? expected;

  /// Texto opcional para la UI.
  final String? message;

  /// `true` cuando la operación salió bien.
  bool get ok => code == 'ok';
}

/// Contrato de la pasarela de pagos y del efectivo.
///
/// La app depende de esta interfaz; las implementaciones (memoria y Wompi) viven
/// en `lib/data/repositories/`.
abstract class PaymentRepository {
  /// `true` cuando el pago vive en un backend real (Wompi).
  bool get isRemote;

  /// Inicia o reutiliza un intento de pago para el pedido.
  Future<PaymentResult> start({
    required String orderId,
    required PaymentMethod method,
    int? amount,
  });

  /// Consulta el último intento del pedido.
  Future<PaymentResult> status(String orderId);

  /// Reintenta el pago del mismo pedido (nuevo intento si el anterior falló).
  Future<PaymentResult> retry({
    required String orderId,
    required PaymentMethod method,
  });

  /// Anula/reembolsa el pago aprobado y lo registra.
  Future<PaymentResult> refund(String orderId, {String reason = 'Cancelación'});

  /// Escucha los cambios del pago (Realtime o simulación en demo).
  Stream<Payment> watch(String orderId);

  /// Libera suscripciones (Realtime, timers).
  void dispose();
}
