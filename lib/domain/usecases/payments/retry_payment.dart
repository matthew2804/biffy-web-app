import '../../entities/catalog.dart';
import '../../repositories/payment_repository.dart';

/// Reintenta el pago de un pedido que sigue pendiente o fue rechazado.
class RetryPayment {
  RetryPayment(this._repo);

  final PaymentRepository _repo;

  /// Crea un intento nuevo (o reutiliza el pendiente) sin duplicar el cobro.
  Future<PaymentResult> call({
    required String orderId,
    required PaymentMethod method,
  }) => _repo.retry(orderId: orderId, method: method);
}
