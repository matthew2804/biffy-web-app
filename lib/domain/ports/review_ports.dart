import '../entities/order.dart';

/// Lo que el caso de uso de calificar necesita del catálogo: actualizar el
/// promedio de la sede. Lo implementa un adaptador sobre `CatalogController`.
abstract interface class BranchRatingPort {
  /// Guarda el promedio nuevo de [restaurantId].
  void setRestaurantRating(String restaurantId, double rating);
}

/// Aviso al restaurante cuando le califican un pedido.
/// Con Supabase lo crea la base (0022) y este puerto no hace nada.
abstract interface class ReviewNotifier {
  /// Avisa que [order] recibió [stars] estrellas.
  void rated(Order order, int stars);
}
