import 'package:flutter/widgets.dart';

import '../../../data/models/order.dart';
import '../../../domain/recommendation.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../features/orders/bloc/orders_bloc.dart';
import '../../../shared/state/session_controller.dart';
import '../../../app/di/injection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Construye la entrada del motor de recomendaciones desde el estado actual.
RecommendationInput buildRecommendationInput(
  BuildContext context, {
  int seed = 0,
}) {
  final session = getIt<SessionController>();
  final catalog = getIt<CatalogController>();
  final orders = context.read<OrdersBloc>();
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
