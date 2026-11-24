import '../../repositories/order_repository.dart';

/// Obtiene el enlace temporal de la foto de evidencia de un pedido entregado.
class GetDeliveryEvidence {
  /// Crea el caso de uso sobre el repositorio de pedidos.
  const GetDeliveryEvidence(this._repo);

  final OrderRepository _repo;

  /// URL para mostrar la foto, o `null` si el pedido no tiene foto guardada.
  /// Lanza si no hay conexión con el servidor.
  Future<String?> call(String orderId) => _repo.evidenceUrl(orderId);
}
