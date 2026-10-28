import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../domain/pricing.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import 'reorder_flow.dart';

/// Grupo de pedidos repetidos con su última versión y el número de veces.
class FrequentOrder {
  /// Crea el grupo con el pedido más reciente y su conteo.
  FrequentOrder(this.latest, this.times);
  final Order latest;
  int times;
}

/// Agrupa pedidos entregados idénticos (restaurante + platos + personalización).
List<FrequentOrder> frequentOrders(List<Order> orders) {
  final groups = <String, FrequentOrder>{};
  final sorted = [...orders.where((o) => o.status == OrderStatus.delivered)]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  for (final o in sorted) {
    final key =
        '${o.restaurantId}#${(o.lines.map((l) => '${l.dishId}x${l.qty}:${l.selection.signature}').toList()..sort()).join(';')}';
    final g = groups[key];
    if (g == null) {
      groups[key] = FrequentOrder(o, 1);
    } else {
      g.times++;
    }
  }
  return groups.values.toList()..sort((a, b) => b.times.compareTo(a.times));
}

/// Pantalla con los pedidos que el comprador repite más.
class FrequentOrdersScreen extends StatelessWidget {
  const FrequentOrdersScreen({super.key});

  /// Construye la lista de pedidos frecuentes o el estado vacío.
  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderService>();
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final t = Theme.of(context).textTheme;
    if (session.user == null) return const Scaffold();
    final list = frequentOrders(orders.forBuyer(session.user!.id));
    return Scaffold(
      appBar: AppBar(title: const Text('Pedidos frecuentes')),
      body: MobileFrame(
        child: list.isEmpty
            ? EmptyState(
                emoji: '⚡',
                title: 'Aún no tienes pedidos frecuentes',
                body:
                    'Cuando recibas pedidos aparecerán aquí para repetirlos rápido.',
                actionLabel: 'Explorar comida',
                onAction: () => context.go('/explorar'),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final f in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: BiffyCard(
                        key: Key('frequent-${f.latest.id}'),
                        onTap: () => _detail(context, f),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    f.latest.restaurantName,
                                    style: t.titleSmall,
                                  ),
                                ),
                                Tag(
                                  '${f.times} ${f.times == 1 ? 'vez' : 'veces'}',
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            for (final l in f.latest.lines)
                              Text(
                                '${l.qty}× ${l.name}${l.detail.isEmpty ? '' : ' · ${l.detail}'}',
                                style: t.bodySmall,
                              ),
                            const SizedBox(height: 6),
                            Text(
                              'Precio estimado hoy: ${cop(_estimate(catalog, f.latest))}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(44),
                                    ),
                                    onPressed: () =>
                                        reorderToCart(context, f.latest),
                                    child: const Text('Ajustar'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: FilledButton(
                                    key: Key('order-now-${f.latest.id}'),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size.fromHeight(44),
                                    ),
                                    onPressed: () =>
                                        orderNow(context, f.latest),
                                    child: const Text('Pedir ya'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// Calcula el precio estimado del pedido con el catálogo actual.
  int _estimate(CatalogController catalog, Order o) {
    var sum = 0;
    for (final l in o.lines) {
      final d = catalog.dishById(l.dishId);
      sum += d == null ? l.total : unitPrice(d, l.selection) * l.qty;
    }
    return sum;
  }

  /// Abre la hoja con el detalle del último pedido del grupo.
  void _detail(BuildContext context, FrequentOrder f) {
    final o = f.latest;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(o.restaurantName, style: Theme.of(ctx).textTheme.titleLarge),
            Text(
              'Último: ${dateTimeLabel(o.createdAt)} · pedido ${f.times} ${f.times == 1 ? 'vez' : 'veces'}',
            ),
            const Divider(height: 24),
            for (final l in o.lines)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(l.emoji, style: const TextStyle(fontSize: 26)),
                title: Text('${l.qty}× ${l.name}'),
                subtitle: Text(
                  [
                    if (l.detail.isNotEmpty) l.detail,
                    if (l.note.isNotEmpty) '📝 ${l.note}',
                  ].join('\n'),
                ),
                trailing: Text(cop(l.total)),
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/pedido/${o.id}');
              },
              child: const Text('Ver último pedido'),
            ),
          ],
        ),
      ),
    );
  }
}
