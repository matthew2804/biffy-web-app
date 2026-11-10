import '../entities/order.dart';
import '../order_rules.dart';
import '../ports/review_ports.dart';
import '../repositories/review_repository.dart';

/// Caso de uso: el comprador califica su pedido entregado.
///
/// Aplica la regla [checkRating] (la misma que `rate_order` en la base); si
/// pasa, guarda la reseña en el [ReviewRepository], marca el pedido como
/// calificado, actualiza el promedio de la sede y avisa al restaurante.
class RateOrder {
  /// Recibe dónde se guardan las reseñas y los puertos de catálogo y avisos.
  const RateOrder(this._reviews, this._ratings, this._notifier);

  final ReviewRepository _reviews;
  final BranchRatingPort _ratings;
  final ReviewNotifier _notifier;

  /// Valida, guarda y refleja la calificación.
  Future<ReviewOutcome> call({
    required Order? order,
    required String userId,
    required int stars,
    String comment = '',
  }) async {
    final check = checkRating(order, userId, stars, comment);
    if (check != RateResult.ok) return ReviewOutcome(check);
    final o = order!;
    final text = comment.trim();
    final out = await _reviews.submit(o, stars, text);
    if (!out.ok) return out;

    o.rating = stars;
    o.review = text;
    final avg = out.branchRating;
    if (avg != null) _ratings.setRestaurantRating(o.restaurantId, avg);
    _notifier.rated(o, stars);
    return out;
  }
}
