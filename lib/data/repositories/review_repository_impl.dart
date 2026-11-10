import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/order_rules.dart';
import '../../domain/repositories/review_repository.dart';
import '../models/order.dart';
import 'order_repository.dart';

/// Reseñas del modo demo: el promedio se calcula con los pedidos en memoria.
class InMemoryReviewRepository implements ReviewRepository {
  InMemoryReviewRepository(this._orders);

  final OrderRepository _orders;

  /// Devuelve el promedio de la sede contando la reseña nueva.
  @override
  Future<ReviewOutcome> submit(Order order, int stars, String comment) async {
    final others = _orders.all
        .where((o) => o.restaurantId == order.restaurantId && o.id != order.id)
        .map((o) => o.rating)
        .whereType<int>();
    return ReviewOutcome(
      RateResult.ok,
      branchRating: averageRating([...others, stars]),
    );
  }
}

/// Reseñas en Supabase con el RPC `rate_order` (la base recalcula el promedio).
class SupabaseReviewRepository implements ReviewRepository {
  SupabaseReviewRepository([sb.SupabaseClient? client])
    : _client = client ?? sb.Supabase.instance.client;

  final sb.SupabaseClient _client;

  /// Llama a `rate_order` y traduce su `result`.
  @override
  Future<ReviewOutcome> submit(Order order, int stars, String comment) async {
    final dbId = order.dbId;
    if (dbId == null) return const ReviewOutcome(RateResult.offline);
    try {
      final res = await _client.rpc(
        'rate_order',
        params: {
          'p_payload': {'order_id': dbId, 'rating': stars, 'comment': comment},
        },
      );
      final map = res is Map ? res : const {};
      return ReviewOutcome(
        rateResultFrom(map['result'] as String?),
        branchRating: (map['branch_rating'] as num?)?.toDouble(),
      );
    } on Object {
      return const ReviewOutcome(RateResult.offline);
    }
  }
}
