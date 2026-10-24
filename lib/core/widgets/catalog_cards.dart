import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../data/models/catalog.dart';
import '../../domain/pricing.dart';
import '../../shared/state/catalog_controller.dart';
import '../../shared/state/session_controller.dart';
import '../utils/format.dart';
import 'actions.dart';
import 'ui.dart';

class _AddButton extends StatelessWidget {
  const _AddButton(this.dish);
  final Dish dish;

  @override
  Widget build(BuildContext context) {
    final enabled = dish.orderable;
    return Semantics(
      label: 'Agregar ${dish.name}',
      button: true,
      child: Material(
        color: enabled ? AppColors.primary : context.palette.border,
        shape: const CircleBorder(),
        child: InkWell(
          key: Key('add-${dish.id}'),
          customBorder: const CircleBorder(),
          onTap: enabled ? () => quickAdd(context, dish) : null,
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.add, color: AppColors.text),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta vertical para carruseles.
class DishCard extends StatelessWidget {
  const DishCard(this.dish, {super.key, this.width = 168});
  final Dish dish;
  final double width;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final r = catalog.restaurantById(dish.restaurantId);
    return SizedBox(
      width: width,
      child: BiffyCard(
        padding: const EdgeInsets.all(10),
        onTap: () => context.push('/plato/${dish.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FoodImage.dish(dish, size: 104, width: width - 20, radius: 14),
            const SizedBox(height: 8),
            Text(
              dish.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              r?.name ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    cop(dish.price),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                _AddButton(dish),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila horizontal para listas y resultados.
class DishTile extends StatelessWidget {
  const DishTile(this.dish, {super.key, this.showRestaurant = true});
  final Dish dish;
  final bool showRestaurant;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final session = context.watch<SessionController>();
    final r = catalog.restaurantById(dish.restaurantId);
    final conflicts = dish.allergens
        .where(session.prefs.allergies.contains)
        .toList();
    final campus = r != null && campusEligible(r, session.verifiedUniversityId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BiffyCard(
        padding: const EdgeInsets.all(10),
        onTap: () => context.push('/plato/${dish.id}'),
        child: Row(
          children: [
            FoodImage.dish(dish, size: 76),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dish.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (showRestaurant && r != null)
                    Text(
                      '${r.name} · ⭐ ${dish.rating.toStringAsFixed(1)} · ${dish.prepMin} min',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(
                      dish.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        cop(dish.price),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (!dish.orderable)
                        const Tag(
                          'Agotado',
                          color: AppColors.error,
                          textColor: Colors.white,
                        ),
                      if (campus)
                        Tag(
                          '-${(r.studentDiscount * 100).round()}% campus',
                          color: AppColors.success,
                          textColor: Colors.white,
                        ),
                      if (conflicts.isNotEmpty)
                        Tag(
                          '⚠️ ${conflicts.join(', ')}',
                          color: AppColors.error.withValues(alpha: 0.15),
                          textColor: AppColors.error,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _AddButton(dish),
          ],
        ),
      ),
    );
  }
}

class RestaurantCard extends StatelessWidget {
  const RestaurantCard(this.restaurant, {super.key, this.width});
  final Restaurant restaurant;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final session = context.watch<SessionController>();
    final r = restaurant;
    final open = catalog.isOpen(r);
    final campus = campusEligible(r, session.verifiedUniversityId);
    final card = BiffyCard(
      padding: const EdgeInsets.all(12),
      onTap: () => context.push('/restaurante/${r.id}'),
      child: Row(
        children: [
          FoodImage(emoji: r.emoji, asset: r.imageAsset, size: 64),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  r.tagline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '⭐ ${r.rating.toStringAsFixed(1)} · ${catalog.etaFor(r)} min · ${catalog.distanceFor(r).toStringAsFixed(1)} km',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Tag(
                      open ? 'Abierto' : 'Cerrado',
                      color: open
                          ? AppColors.success.withValues(alpha: 0.15)
                          : AppColors.error.withValues(alpha: 0.15),
                      textColor: open ? AppColors.success : AppColors.error,
                    ),
                    if (campus) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Tag(
                          '-${(r.studentDiscount * 100).round()}% campus',
                          color: AppColors.success,
                          textColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Carrusel horizontal nativo con separación de 12 px.
class HCarousel extends StatelessWidget {
  const HCarousel({super.key, required this.height, required this.children});
  final double height;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.none,
        itemCount: children.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}
