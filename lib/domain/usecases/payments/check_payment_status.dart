import '../../repositories/payment_repository.dart';

/// Consulta el estado del último intento de pago de un pedido.
class CheckPaymentStatus {
  CheckPaymentStatus(this._repo);

  final PaymentRepository _repo;

  /// Devuelve el pago actual para pintar la pantalla.
  Future<PaymentResult> call(String orderId) => _repo.status(orderId);
}
