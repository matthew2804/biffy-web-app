import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/catalog_cards.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../domain/recommendation.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import '../ai/recommendation_input.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final orders = context.watch<OrderService>();
    final notifications = context.watch<NotificationCenter>();
    final t = Theme.of(context).textTheme;
    final user = session.user;
    final restaurants = catalog.reachableRestaurants;
    final unread = session.settings.notifications
        ? notifications.unreadFor(user, session.activeRole)
        : 0;
    final uni = universityById(session.verifiedUniversityId);
    final myOrders = user == null ? <Order>[] : orders.forBuyer(user.id);
    final active = myOrders.where((o) => !o.status.isFinal).toList();
    final hasProfile = !session.prefs.isEmpty || myOrders.isNotEmpty;
    final recs = recommend(buildRecommendationInput(context), limit: 8);
    final featuredDishes = hasProfile
        ? recs.map((e) => e.dish).toList()
        : catalog.popularDishes;
    final campusPopular = catalog.popularDishes
        .where((d) => catalog.restaurantById(d.restaurantId)?.campusId != null)
        .toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const Key('location-selector'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => showDeliveryPointSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: AppColors.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Entregar en', style: t.labelSmall),
                                  Text(
                                    session.point.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.keyboard_arrow_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                  RoundIconButton(
                    icon: Icons.notifications_none,
                    tooltip: 'Notificaciones',
                    badge: unread,
                    onTap: () => context.push('/notificaciones'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (user != null)
                    Text(
                      'Hola, ${user.name.split(' ').first} 👋',
                      style: t.bodyMedium,
                    ),
                  Text('¿Qué se te antoja hoy? 🐝', style: t.headlineSmall),
                  const SizedBox(height: 12),
                  BiffyCard(
                    key: const Key('qbano-strip'),
                    color: AppColors.surfaceSoft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    onTap: () => context.push('/restaurante/qbano-icesi'),
                    child: Row(
                      children: [
                        const Text('🥪', style: TextStyle(fontSize: 26)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Qbano en Icesi',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.text,
                                ),
                              ),
                              Text(
                                'Compra de demostración · sin cobros reales',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.text,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: AppColors.text),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    key: const Key('home-search'),
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.go('/explorar?focus=1'),
                    child: IgnorePointer(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Busca platos o restaurantes',
                          prefixIcon: Icon(Icons.search),
                        ),
                        readOnly: true,
                      ),
                    ),
                  ),
                  if (user == null && session.settings.promotions) ...[
                    const SizedBox(height: 12),
                    BiffyCard(
                      color: AppColors.primary,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '🎓 Descuentos de estudiante',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: AppColors.text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Inicia sesión y recibe $kWelcomeGotas Gotas de bienvenida en la demostración.',
                            style: TextStyle(color: AppColors.text),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.text,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(160, 44),
                            ),
                            onPressed: () => context.push('/login'),
                            child: const Text('Iniciar sesión'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (user != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: BiffyCard(
                            onTap: () => context.push('/recompensas'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '💧 Gotas Biffy',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  '${session.gotas}',
                                  style: t.headlineSmall?.copyWith(
                                    color: AppColors.secondary,
                                  ),
                                ),
                                Text('Ver recompensas', style: t.bodySmall),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: BiffyCard(
                            onTap: () => context.push('/campus'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '🎓 Campus',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  uni?.name ?? 'Verifica tu universidad',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  uni == null
                                      ? 'Simulación'
                                      : 'Verificado (simulado)',
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!session.data.prefsCompleted) ...[
                    const SizedBox(height: 12),
                    BiffyCard(
                      key: const Key('prefs-invite'),
                      onTap: () => context.push('/preferencias'),
                      child: Row(
                        children: [
                          const Text('✨', style: TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cuéntanos tus gustos (opcional)',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  user == null
                                      ? 'Mejora tus recomendaciones. Con sesión ganas $kSurveyGotas Gotas.'
                                      : 'Gana $kSurveyGotas Gotas al completarlo por primera vez.',
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ],
                  for (final o in active.take(2)) ...[
                    const SizedBox(height: 12),
                    BiffyCard(
                      key: Key('active-order-${o.id}'),
                      border: Border.all(color: AppColors.primary, width: 2),
                      onTap: () => context.push('/pedido/${o.id}'),
                      child: Row(
                        children: [
                          const Text('🛵', style: TextStyle(fontSize: 28)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${o.isScheduled ? 'Pedido programado' : 'Pedido activo'} · ${o.id}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${o.restaurantName} · ${o.itemsSummary}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          StatusChip(o.status),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (restaurants.isNotEmpty &&
                !restaurants.any(catalog.isOpen) &&
                !session.settings.demoLunch)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: BiffyCard(
                  key: const Key('closed-banner'),
                  color: AppColors.secondary.withValues(alpha: 0.2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🌙 Los restaurantes de tu zona están cerrados a esta hora',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Puedes programar tu pedido o activar el horario de demostración (12:00).',
                        style: t.bodySmall,
                      ),
                      TextButton(
                        onPressed: () {
                          session.updateSettings(
                            session.settings.copyWith(demoLunch: true),
                          );
                          showSnack(
                            context,
                            'Horario de demostración activado (12:00)',
                          );
                        },
                        child: const Text('Activar horario de demostración'),
                      ),
                    ],
                  ),
                ),
              ),
            if (restaurants.isEmpty)
              EmptyState(
                emoji: '📍',
                title:
                    'No hay restaurantes que entreguen en ${session.point.name}',
                body: 'Prueba con otro punto de entrega de la demostración.',
                actionLabel: 'Cambiar punto de entrega',
                onAction: () => showDeliveryPointSheet(context),
              )
            else ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: SectionHeader('Categorías'),
              ),
              HCarousel(
                height: 88,
                children: [
                  for (final c in kCategories)
                    InkWell(
                      key: Key('cat-${c.id}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.go('/explorar?cat=${c.id}'),
                      child: SizedBox(
                        width: 72,
                        child: Column(
                          children: [
                            FoodImage(
                              emoji: c.emoji,
                              asset: c.imageAsset,
                              size: 56,
                              radius: 28,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              c.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (uni != null &&
                  catalog.campusRestaurants(uni.id).isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SectionHeader(
                    'Tu campus · ${uni.name}',
                    action: 'Ver todo',
                    onAction: () => context.push('/campus'),
                  ),
                ),
                HCarousel(
                  height: kRestaurantCardHeight,
                  children: [
                    for (final r in catalog.campusRestaurants(uni.id))
                      RestaurantCard(r, width: 290),
                  ],
                ),
              ],
              if (featuredDishes.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SectionHeader(
                    hasProfile ? 'Recomendado para ti' : 'Lo más pedido',
                    action: 'Ver todos',
                    onAction: () =>
                        context.go(hasProfile ? '/ai' : '/explorar'),
                  ),
                ),
                HCarousel(
                  height: 236,
                  children: [for (final d in featuredDishes) DishCard(d)],
                ),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    SectionHeader(
                      'Restaurantes cerca',
                      action: 'Ver todos',
                      onAction: () => context.go('/explorar?view=restaurantes'),
                    ),
                    for (final r in restaurants.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: RestaurantCard(r),
                      ),
                  ],
                ),
              ),
              if (campusPopular.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SectionHeader('Populares en el campus'),
                ),
                HCarousel(
                  height: 236,
                  children: [for (final d in campusPopular) DishCard(d)],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
