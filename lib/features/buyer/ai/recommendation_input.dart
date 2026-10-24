import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/models/order.dart';
import '../../../domain/recommendation.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

/// Construye la entrada del motor de recomendaciones desde el estado actual.
RecommendationInput buildRecommendationInput(
  BuildContext context, {
  int seed = 0,
}) {
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final orders = context.read<OrderService>();
  final user = session.user;
  final history = <String>[
    if (user != null)
      for (final o in orders.forBuyer(user.id))
        if (o.status == OrderStatus.delivered)
          for (final l in o.lines) l.dishId,
  ];
  return RecommendationInput(
    dishes: catalog.reachableDishes,
    restaurantOf: catalog.restaurantById,
    prefs: session.prefs,
    point: session.point,
    historyDishIds: history,
    favoriteDishIds: session.data.favoriteDishes,
    universityId: session.universityId,
    now: catalog.now,
    seed: seed,
  );
}
