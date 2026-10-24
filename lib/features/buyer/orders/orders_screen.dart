import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import 'reorder_flow.dart';

/// Historial separado en activos, programados, anteriores y cancelados.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderService>();
    final session = context.watch<SessionController>();
    final now = context.read<CatalogController>().now;
    if (session.user == null) return const Scaffold();
    final mine = orders.forBuyer(session.user!.id)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    bool scheduled(Order o) =>
        !o.status.isFinal &&
        o.status == OrderStatus.pending &&
        o.isScheduled &&
        o.scheduledFor!.isAfter(now);
    final tabs = <(String, List<Order>)>[
      (
        'Activos',
        mine.where((o) => !o.status.isFinal && !scheduled(o)).toList(),
      ),
      ('Programados', mine.where(scheduled).toList()),
      (
        'Anteriores',
        mine.where((o) => o.status == OrderStatus.delivered).toList(),
      ),
      (
        'Cancelados',
        mine.where((o) => o.status == OrderStatus.cancelled).toList(),
      ),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis pedidos'),
          actions: [
            TextButton.icon(
              onPressed: () => context.push('/frecuentes'),
              icon: const Icon(Icons.bolt),
              label: const Text('Frecuentes'),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final (label, list) in tabs)
                Tab(text: '$label (${list.length})'),
            ],
          ),
        ),
        body: MobileFrame(
          child: TabBarView(
            children: [
              for (final (label, list) in tabs)
                list.isEmpty
                    ? EmptyState(
                        emoji: '🧾',
                        title: 'No tienes pedidos ${label.toLowerCase()}',
                        actionLabel: 'Explorar comida',
                        onAction: () => context.go('/explorar'),
                      )
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [for (final o in list) OrderCard(order: o)],
                      ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BiffyCard(
        key: Key('order-${o.id}'),
        onTap: () => context.push('/pedido/${o.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${o.restaurantName} · ${o.id}',
                    style: t.titleSmall,
                  ),
                ),
                StatusChip(o.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              o.itemsSummary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall,
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    o.isScheduled
                        ? '📅 ${dateTimeLabel(o.scheduledFor!)}'
                        : dateTimeLabel(o.createdAt),
                    style: t.bodySmall,
                  ),
                ),
                Text(
                  cop(o.total),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            if (o.status == OrderStatus.delivered)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => reorderToCart(context, o),
                  icon: const Icon(Icons.replay),
                  label: const Text('Pedir de nuevo'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
