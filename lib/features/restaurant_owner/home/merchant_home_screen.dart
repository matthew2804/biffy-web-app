import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/user.dart';
import '../../../domain/order_rules.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

/// Métricas del negocio actual derivadas de pedidos y productos locales.
RestaurantMetrics businessMetrics(BuildContext context) {
  final session = context.read<SessionController>();
  final catalog = context.read<CatalogController>();
  final orders = context.read<OrderService>();
  final id = session.businessId!;
  return computeMetrics(
    orders: orders.forBusiness(id),
    dishes: catalog.productsOf(id),
    branches: catalog.branchesOf(id),
    now: catalog.now,
  );
}

/// Panel del negocio con ventas, pedidos recientes y productos destacados.
class MerchantHomeScreen extends StatelessWidget {
  const MerchantHomeScreen({super.key});

  /// Muestra el estado del negocio y atajos a pedidos y menú.
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final orders = context.watch<OrderService>();
    final center = context.watch<NotificationCenter>();
    final t = Theme.of(context).textTheme;
    final b = catalog.businessById(session.businessId!)!;
    final m = businessMetrics(context);
    final paused = catalog.isBusinessPaused(b.id);
    final recent = orders.forBusiness(b.id)
      ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    final featured = catalog
        .productsOf(b.id)
        .where((d) => d.featured || d.popular)
        .take(4)
        .toList();
    final unread = center.unreadFor(session.user, UserRole.restaurant);

    /// Tarjeta de contador que abre los pedidos con ese filtro.
    Widget stat(String label, int n, String filter) => Expanded(
      child: InkWell(
        onTap: () => context.go('/negocio/pedidos?f=$filter'),
        child: BiffyCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text('$n', style: t.headlineSmall),
              Text(label, style: t.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(child: Text(b.brand, style: t.headlineSmall)),
                IconButton(
                  tooltip: 'Notificaciones',
                  icon: Badge(
                    isLabelVisible: unread > 0,
                    label: Text('$unread'),
                    child: const Icon(Icons.notifications_none),
                  ),
                  onPressed: () => context.push('/notificaciones'),
                ),
              ],
            ),
            if (b.isDemo)
              const Align(
                alignment: Alignment.centerLeft,
                child: DemoBadge('Negocio ficticio de demostración'),
              ),
            const SizedBox(height: 12),
            BiffyCard(
              color: paused
                  ? AppColors.error.withValues(alpha: 0.1)
                  : AppColors.success.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SwitchListTile(
                key: const Key('business-open'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  paused ? 'Pausado' : 'Abierto para pedidos',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  paused
                      ? 'Los clientes no pueden pedir ahora'
                      : 'Visible para clientes dentro del radio',
                ),
                value: !paused,
                onChanged: (v) async {
                  try {
                    await catalog.setBusinessPaused(b.id, !v);
                  } on Object {
                    if (!context.mounted) return;
                    showSnack(
                      context,
                      'No pudimos cambiar el estado.',
                      error: true,
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            BigNumber(
              'Ventas de hoy (simuladas)',
              cop(m.salesToday),
              highlight: true,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                stat('Nuevos', m.newCount, 'nuevos'),
                const SizedBox(width: 8),
                stat('En preparación', m.preparingCount, 'preparacion'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                stat('Listos', m.readyCount, 'listos'),
                const SizedBox(width: 8),
                stat('Completados', m.completedCount, 'finalizados'),
              ],
            ),
            SectionHeader(
              'Pedidos recientes',
              action: 'Ver todos',
              onAction: () => context.go('/negocio/pedidos'),
            ),
            if (recent.isEmpty)
              const EmptyState(emoji: '🧾', title: 'Aún no hay pedidos')
            else
              for (final o in recent.take(4))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BiffyCard(
                    padding: const EdgeInsets.all(12),
                    onTap: () => context.go('/negocio/pedidos'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${o.id} · ${o.buyerName}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                o.itemsSummary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        StatusChip(o.status, kitchen: true),
                      ],
                    ),
                  ),
                ),
            SectionHeader(
              'Productos destacados',
              action: 'Menú',
              onAction: () => context.go('/negocio/menu'),
            ),
            if (featured.isEmpty)
              EmptyState(
                emoji: '🍽️',
                title: 'Sin productos destacados',
                actionLabel: 'Crear producto',
                onAction: () => context.push('/negocio/producto/nuevo'),
              )
            else
              for (final d in featured)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: FoodImage.dish(d, size: 48),
                  title: Text(d.name),
                  subtitle: Text(cop(d.price)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/negocio/producto/${d.id}'),
                ),
          ],
        ),
      ),
    );
  }
}
