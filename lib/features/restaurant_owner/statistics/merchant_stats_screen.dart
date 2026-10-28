import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import '../home/merchant_home_screen.dart';

/// Estadísticas del negocio con ventas por sede y productos top.
class MerchantStatsScreen extends StatelessWidget {
  const MerchantStatsScreen({super.key});

  /// Calcula las métricas y dibuja las barras comparativas.
  @override
  Widget build(BuildContext context) {
    context.watch<SessionController>();
    context.watch<CatalogController>();
    context.watch<OrderService>();
    final t = Theme.of(context).textTheme;
    final m = businessMetrics(context);
    final maxBranch = m.salesByBranch.values.fold<int>(
      1,
      (a, b) => b > a ? b : a,
    );
    final maxTop = m.topProducts.isEmpty ? 1 : m.topProducts.first.qty;

    /// Fila con etiqueta, valor y barra proporcional al máximo.
    Widget bar(String label, String value, double ratio) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 10,
            color: AppColors.primary,
            backgroundColor: context.palette.border,
            borderRadius: BorderRadius.circular(5),
          ),
        ],
      ),
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Estadísticas', style: t.headlineSmall),
            Text(
              'Calculadas con los pedidos y productos de la demostración.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: BigNumber(
                    'Ventas totales',
                    cop(m.salesTotal),
                    highlight: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: BigNumber('Ventas de hoy', cop(m.salesToday))),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: BigNumber('Pedidos', '${m.ordersTotal}')),
                const SizedBox(width: 12),
                Expanded(
                  child: BigNumber('Ticket promedio', cop(m.averageTicket)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: BigNumber('Rechazados', '${m.rejectedCount}')),
                const SizedBox(width: 12),
                Expanded(
                  child: BigNumber('Productos activos', '${m.activeProducts}'),
                ),
              ],
            ),
            const SectionHeader('Ventas por sede'),
            BiffyCard(
              child: Column(
                children: [
                  for (final e in m.salesByBranch.entries)
                    bar(e.key, cop(e.value), e.value / maxBranch),
                ],
              ),
            ),
            const SectionHeader('Productos más vendidos'),
            if (m.topProducts.isEmpty)
              const EmptyState(emoji: '📊', title: 'Aún no hay ventas')
            else
              BiffyCard(
                child: Column(
                  children: [
                    for (final p in m.topProducts)
                      bar(
                        p.name,
                        '${p.qty} uds · ${cop(p.revenue)}',
                        p.qty / maxTop,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
