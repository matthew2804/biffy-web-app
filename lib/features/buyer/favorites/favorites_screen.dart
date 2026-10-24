import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/catalog_cards.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final dishes = [
      for (final id in session.data.favoriteDishes) ?catalog.dishById(id),
    ];
    final restaurants = [
      for (final id in session.data.favoriteRestaurants)
        ?catalog.restaurantById(id),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Favoritos')),
      body: MobileFrame(
        child: dishes.isEmpty && restaurants.isEmpty
            ? EmptyState(
                emoji: '❤️',
                title: 'Aún no tienes favoritos',
                body:
                    'Toca el corazón en un plato o restaurante para guardarlo.',
                actionLabel: 'Explorar',
                onAction: () => context.go('/explorar'),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (dishes.isNotEmpty) ...[
                    const SectionHeader('Platos'),
                    for (final d in dishes) DishTile(d),
                  ],
                  if (restaurants.isNotEmpty) ...[
                    const SectionHeader('Restaurantes'),
                    for (final r in restaurants)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RestaurantCard(r),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
