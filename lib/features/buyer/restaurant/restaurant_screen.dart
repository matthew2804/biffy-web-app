import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/navigation/shells.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/catalog_cards.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/catalog_rules.dart';
import '../../../domain/pricing.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';

/// Menú de un restaurante con portada, filtros de sección y platos.
class RestaurantScreen extends StatefulWidget {
  const RestaurantScreen({super.key, required this.id});
  final String id;

  /// Crea el estado del menú del restaurante.
  @override
  State<RestaurantScreen> createState() => _RestaurantScreenState();
}

/// Estado con la sección del menú seleccionada.
class _RestaurantScreenState extends State<RestaurantScreen> {
  String? _section;

  /// Construye la portada, los datos del local y su menú.
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    final r = catalog.restaurantById(widget.id);
    if (r == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🏚️',
          title: 'Restaurante no encontrado',
          actionLabel: 'Volver al inicio',
          onAction: () => context.go('/'),
        ),
      );
    }
    final menu = catalog.menuOf(r.id);
    final sections = {for (final d in menu) d.section}.toList();
    final shown = _section == null
        ? menu
        : menu.where((d) => d.section == _section).toList();
    final open = catalog.isOpen(r);
    final reachable = catalog.reachable(r);
    final fav = session.data.favoriteRestaurants.contains(r.id);
    final eligible = campusEligible(r, session.verifiedUniversityId);
    final width = MediaQuery.of(context).size.width.clamp(0, 480).toDouble();
    final cardWidth = (width - 32 - 12) / 2;

    return Scaffold(
      bottomNavigationBar: const CartBar(),
      body: MobileFrame(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                height: 220 + MediaQuery.of(context).padding.top,
                color: AppColors.primary,
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top,
                ),
                child: Stack(
                  children: [
                    // Portada a lo ancho; si el local no tiene foto, se ve su emoji.
                    if (r.imageAsset != null)
                      Positioned.fill(
                        child: catalogImage(
                          r.imageAsset!,
                          fallback: Center(
                            child: Text(
                              r.emoji,
                              style: const TextStyle(fontSize: 72),
                            ),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          r.emoji,
                          style: const TextStyle(fontSize: 72),
                        ),
                      ),
                    Positioned(
                      left: 12,
                      top: 8,
                      child: RoundIconButton(
                        icon: Icons.arrow_back,
                        tooltip: 'Volver',
                        onTap: () =>
                            context.canPop() ? context.pop() : context.go('/'),
                      ),
                    ),
                    Positioned(
                      right: 12,
                      top: 8,
                      child: RoundIconButton(
                        key: const Key('fav-restaurant'),
                        icon: fav ? Icons.favorite : Icons.favorite_border,
                        iconColor: fav ? AppColors.error : null,
                        tooltip: fav
                            ? 'Quitar de favoritos'
                            : 'Agregar a favoritos',
                        onTap: () async {
                          if (!await requireLogin(
                            context,
                            reason: 'guardar favoritos',
                          )) {
                            return;
                          }
                          session.toggleFavoriteRestaurant(r.id);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: t.headlineSmall),
                    const SizedBox(height: 4),
                    Text(r.tagline, style: t.bodyMedium),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Tag(
                          '${categoryById(r.cuisine).emoji} ${categoryById(r.cuisine).label}',
                        ),
                        Tag('⭐ ${r.rating.toStringAsFixed(1)}'),
                        Tag('⏱ ${catalog.etaFor(r)} min'),
                        Tag(
                          '📍 ${catalog.distanceFor(r).toStringAsFixed(1)} km',
                        ),
                        Tag(
                          open ? 'Abierto ahora' : 'Cerrado ahora',
                          color: open ? AppColors.success : AppColors.error,
                          textColor: Colors.white,
                        ),
                        if (r.demo) const DemoBadge('Menú de demostración'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('🕒 ${scheduleLabel(r)}', style: t.bodySmall),
                    Text('🏠 ${r.address}', style: t.bodySmall),
                    if (r.campusId != null && r.studentDiscount > 0) ...[
                      const SizedBox(height: 10),
                      BiffyCard(
                        color: AppColors.success.withValues(alpha: 0.12),
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          eligible
                              ? '🎓 Tienes ${(r.studentDiscount * 100).round()}% de descuento universitario (verificación simulada).'
                              : '🎓 ${(r.studentDiscount * 100).round()}% de descuento para estudiantes verificados de ${universityById(r.campusId)?.name}.',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                    if (!reachable) ...[
                      const SizedBox(height: 10),
                      BiffyCard(
                        key: const Key('not-reachable'),
                        color: AppColors.error.withValues(alpha: 0.1),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⚠️ No entrega en ${session.point.name}${r.couriersNearby == 0 ? ' (sin repartidores cerca)' : ''}.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppColors.error,
                              ),
                            ),
                            TextButton(
                              onPressed: () => showDeliveryPointSheet(context),
                              child: const Text('Cambiar punto de entrega'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _groupOrder(context, r.id),
                            icon: const Icon(Icons.group_outlined),
                            label: const Text('Pedido grupal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => copyShareLink(
                              context,
                              'restaurante/${r.id}',
                              r.name,
                            ),
                            icon: const Icon(Icons.share_outlined),
                            label: const Text('Compartir'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectPill(
                        label: 'Todo',
                        selected: _section == null,
                        onTap: () => setState(() => _section = null),
                      ),
                    ),
                    for (final s in sections)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: SelectPill(
                          label: s,
                          selected: _section == s,
                          onTap: () => setState(() => _section = s),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (shown.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  emoji: '🍽️',
                  title: 'Este menú aún no tiene productos publicados',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final d in shown) DishCard(d, width: cardWidth),
                    ],
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// Abre la hoja explicativa del pedido grupal de demostración.
  void _groupOrder(BuildContext context, String id) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pedido grupal (demo)',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Comparte este enlace de demostración con tus amigos para que vean el menú. '
                'No es un carrito colaborativo sincronizado: cada persona arma su pedido en su propio teléfono.',
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Copiar enlace de demostración',
                icon: Icons.link,
                onPressed: () {
                  Navigator.pop(ctx);
                  copyShareLink(context, 'grupo/$id', 'pedido grupal');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
