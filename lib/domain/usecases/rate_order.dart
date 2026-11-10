import '../../data/models/order.dart';
import '../order_rules.dart';
import '../repositories/review_repository.dart';

/// Caso de uso: el comprador califica su pedido entregado.
///
/// Aplica la regla [checkRating] (la misma que `rate_order` en la base) y solo
/// si pasa le pide al [ReviewRepository] que guarde la reseña.
class RateOrder {
  const RateOrder(this._reviews);

  final ReviewRepository _reviews;

  /// Valida y guarda la calificación.
  Future<ReviewOutcome> call({
    required Order? order,
    required String userId,
    required int stars,
    String comment = '',
  }) async {
    final check = checkRating(order, userId, stars, comment);
    if (check != RateResult.ok) return ReviewOutcome(check);
    return _reviews.submit(order!, stars, comment.trim());
  }
}
