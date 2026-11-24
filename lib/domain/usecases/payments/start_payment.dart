import '../../entities/catalog.dart';
import '../../repositories/payment_repository.dart';

/// Inicia (o reutiliza) el pago de un pedido.
class StartPayment {
  StartPayment(this._repo);

  final PaymentRepository _repo;

  /// Crea el intento por el monto del servidor; [amount] solo sirve para
  /// detectar si el total mostrado cambió.
  Future<PaymentResult> call({
    required String orderId,
    required PaymentMethod method,
    int? amount,
  }) => _repo.start(orderId: orderId, method: method, amount: amount);
}
