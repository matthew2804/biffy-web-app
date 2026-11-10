import '../../data/models/order.dart';
import '../order_rules.dart';

/// Resultado de guardar una reseña: el código y el promedio nuevo de la sede.
class ReviewOutcome {
  const ReviewOutcome(this.result, {this.branchRating});

  final RateResult result;

  /// Promedio de la sede después de la reseña (`null` si no se conoce).
  final double? branchRating;

  /// `true` si la reseña quedó guardada.
  bool get ok => result == RateResult.ok;
}

/// Contrato para guardar reseñas. El dominio no sabe si detrás hay Supabase
/// (`rate_order`) o la memoria del modo demo.
abstract interface class ReviewRepository {
  /// Guarda [stars] y [comment] para [order] (ya validado por el caso de uso).
  Future<ReviewOutcome> submit(Order order, int stars, String comment);
}
