import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/order_rules.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

class EarningsScreen extends StatelessWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final orders = context.watch<OrderService>();
    final now = context.read<CatalogController>().now;
    final t = Theme.of(context).textTheme;
    final all = orders.deliveredBy(session.user!.id)
      ..sort(
        (a, b) => (b.deliveredAt ?? b.createdAt).compareTo(
          a.deliveredAt ?? a.createdAt,
        ),
      );
    final today = computeEarnings(
      all.where((o) => o.deliveredAt != null && sameDay(o.deliveredAt!, now)),
    );
    final total = computeEarnings(all);
    final daysToMonday = (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7;
    final settlement = now.add(Duration(days: daysToMonday));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Ganancias', style: t.headlineSmall),
            Text('Valores simulados de la demostración.', style: t.bodySmall),
            const SizedBox(height: 12),
            BigNumber('Total de hoy (neto)', cop(today.net), highlight: true),
            const SizedBox(height: 12),
            BiffyCard(
              child: Column(
                children: [
                  InfoRow('Entregas completadas hoy', '${today.deliveries}'),
                  InfoRow('Pagos por entrega', cop(today.gross)),
                  InfoRow(
                    'Tarifa Biffy simulada (${(kBiffyFeeRate * 100).round()}%)',
                    '-${cop(today.biffyFee)}',
                    valueColor: AppColors.error,
                  ),
                  InfoRow(
                    'Propinas',
                    cop(today.tips),
                    valueColor: AppColors.success,
                  ),
                  const Divider(),
                  InfoRow('Neto de hoy', cop(today.net), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BiffyCard(
              child: Text(
                '📅 Próxima liquidación informativa: ${shortDate(settlement)}. '
                'La demo no procesa transferencias. Acumulado: ${cop(total.net)} en ${total.deliveries} entregas.',
              ),
            ),
            const SectionHeader('Metas y bonos de demostración'),
            for (final (goal, bonus) in kCourierGoals)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  today.deliveries >= goal
                      ? Icons.emoji_events
                      : Icons.emoji_events_outlined,
                  color: today.deliveries >= goal ? AppColors.secondary : null,
                ),
                title: Text('$goal entregas en el día'),
                subtitle: Text(
                  today.deliveries >= goal
                      ? 'Meta cumplida · bono no liquidado'
                      : 'Faltan ${goal - today.deliveries}',
                ),
                trailing: Text(
                  cop(bonus),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            const SectionHeader('Historial de entregas'),
            if (all.isEmpty)
              const EmptyState(emoji: '🛵', title: 'Aún no tienes entregas')
            else
              for (final o in all)
                ListTile(
                  key: Key('earning-${o.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('${o.id} · ${o.restaurantName}'),
                  subtitle: Text(
                    '${relativeDay(o.deliveredAt ?? o.createdAt, now)} · ${o.distanceKm} km'
                    '${o.tip > 0 ? ' · propina ${cop(o.tip)}' : ''}',
                  ),
                  trailing: Text(
                    cop(o.courierEarning),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go('/repartidor'),
              child: const Text('Volver a las ofertas'),
            ),
          ],
        ),
      ),
    );
  }
}
