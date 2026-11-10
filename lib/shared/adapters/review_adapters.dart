import '../../domain/entities/order.dart';
import '../../domain/ports/review_ports.dart';
import '../state/catalog_controller.dart';
import '../state/notification_center.dart';

/// Conecta el puerto de promedio de sede con `CatalogController`.
class CatalogRatingAdapter implements BranchRatingPort {
  /// Recibe el catálogo compartido.
  CatalogRatingAdapter(this._catalog);
  final CatalogController _catalog;

  /// Guarda el promedio en la sede del catálogo.
  @override
  void setRestaurantRating(String restaurantId, double rating) =>
      _catalog.setRestaurantRating(restaurantId, rating);
}

/// Avisa al restaurante de una calificación (solo en modo demo).
class LocalReviewNotifier implements ReviewNotifier {
  /// Recibe el centro de avisos y el catálogo para saber el negocio.
  LocalReviewNotifier(this._center, this._catalog);
  final NotificationCenter _center;
  final CatalogController _catalog;

  /// Crea el aviso «Nueva calificación» para el negocio del pedido.
  @override
  void rated(Order order, int stars) {
    final business = _catalog.restaurantById(order.restaurantId)?.businessId;
    _center.push(
      title: 'Nueva calificación ⭐',
      body: '${order.buyerName} calificó ${order.id} con $stars de 5.',
      audience: 'business:$business',
      route: '/negocio/pedidos',
    );
  }
}

/// Con Supabase el aviso lo crea la base (trigger de 0022): aquí no se hace nada.
class ServerReviewNotifier implements ReviewNotifier {
  /// No necesita dependencias.
  const ServerReviewNotifier();

  /// La base ya avisó al restaurante.
  @override
  void rated(Order order, int stars) {}
}
