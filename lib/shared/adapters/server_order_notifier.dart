import '../../domain/entities/order.dart';
import '../../domain/entities/user.dart';
import '../../domain/ports/order_ports.dart';

/// Notificador de pedidos con Supabase: no crea avisos en la app porque la
/// base los genera para cada destinatario (trigger de 0022, HU-4) y llegan por
/// Realtime. Así no se duplican.
class ServerOrderNotifier implements OrderNotifier {
  /// No necesita dependencias.
  const ServerOrderNotifier();

  /// La base avisa al comprador y al restaurante.
  @override
  void placed(Order order, {required String businessId}) {}

  /// La base avisa al restaurante.
  @override
  void buyerCancelled(Order order, {required String? businessId}) {}

  /// La base avisa al comprador.
  @override
  void accepted(Order order) {}

  /// La base avisa al comprador.
  @override
  void rejected(Order order) {}

  /// La base avisa al comprador y a los repartidores en línea.
  @override
  void ready(Order order) {}

  /// La base avisa al comprador, al restaurante y al repartidor.
  @override
  void assigned(Order order, AppUser courier, {required String? businessId}) {}

  /// La base avisa al comprador.
  @override
  void pickedUp(Order order) {}

  /// La base avisa al comprador y al restaurante.
  @override
  void delivered(Order order, {required String? businessId}) {}
}
