import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/order_rules.dart';
import '../../../domain/usecases/get_courier_earnings.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../orders/bloc/orders_bloc.dart';
import '../../../shared/state/session_controller.dart';
import 'earnings_cubit.dart';

/// Pantalla de ganancias del repartidor con historial, semana y metas.
class EarningsScreen extends StatelessWidget {
  const EarningsScreen({super.key});

  /// Crea el [EarningsCubit] del repartidor y pinta su resumen.
  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    return BlocProvider(
      create: (_) => EarningsCubit(
        orders: context.read<OrdersBloc>(),
        courierId: session.user!.id,
        now: () => catalog.now,
      ),
      child: BlocBuilder<EarningsCubit, EarningsSummary>(
        builder: (context, e) => _EarningsView(
          summary: e,
          now: catalog.now,
          // Con Supabase todo sale de las entregas guardadas en la base.
          real: session.auth.isRemote,
        ),
      ),
    );
  }
}

/// Cuerpo de la pantalla: solo dibuja el [EarningsSummary].
class _EarningsView extends StatelessWidget {
  const _EarningsView({
    required this.summary,
    required this.now,
    required this.real,
  });

  final EarningsSummary summary;
  final DateTime now;
  final bool real;

  /// Dibuja totales, semana, metas e historial.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final today = summary.today;
    final total = summary.total;
    final settlement = summary.settlement;
    final week = summary.week;
    final all = summary.history;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Ganancias', style: t.headlineSmall),
            Text(
              real
                  ? 'Calculado con tus entregas registradas.'
                  : 'Valores simulados de la demostración.',
              key: const Key('earnings-source'),
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            BigNumber('Total de hoy (neto)', cop(today.net), highlight: true),
            const SizedBox(height: 12),
            BiffyCard(
              child: Column(
                children: [
                  InfoRow('Entregas completadas hoy', '${today.deliveries}'),
                  InfoRow('Pagos por entrega', cop(today.gross)),
                  InfoRow(
                    'Tarifa Biffy${real ? '' : ' simulada'} (${(kBiffyFeeRate * 100).round()}%)',
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
            _WeekChart(week: week),
            const SizedBox(height: 12),
            BiffyCard(
              child: Text(
                real
                    ? '📅 Próxima liquidación: ${shortDate(settlement)}. '
                          'Acumulado: ${cop(total.net)} en ${total.deliveries} entregas.'
                    : '📅 Próxima liquidación informativa: ${shortDate(settlement)}. '
                          'La demo no procesa transferencias. Acumulado: ${cop(total.net)} en ${total.deliveries} entregas.',
              ),
            ),
            SectionHeader(
              real ? 'Metas del día' : 'Metas y bonos de demostración',
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, (goal, bonus)) in kCourierGoals.indexed) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _MedalCard(
                        medal: const ['🥉', '🥈', '🥇'][i],
                        name: const ['Bronce', 'Plata', 'Oro'][i],
                        goal: goal,
                        bonus: bonus,
                        done: today.deliveries,
                      ),
                    ),
                  ],
                ],
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

/// Barras con el neto de los últimos 7 días. La barra de hoy va en verde.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.week});
  final List<({DateTime day, int net})> week;

  static const _days = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  /// Dibuja el total y las barras de la semana.
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final max = week.fold<int>(0, (m, d) => d.net > m ? d.net : m);
    final total = week.fold<int>(0, (sum, d) => sum + d.net);
    return BiffyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Últimos 7 días',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                cop(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, d) in week.indexed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Alto proporcional al día que más ganó; mínimo 4 px para que se vea.
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            height: max == 0 ? 4 : 4 + 88 * d.net / max,
                            decoration: BoxDecoration(
                              color: i == week.length - 1
                                  ? AppColors.success
                                  : d.net > 0
                                  ? AppColors.primary
                                  : p.border,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            i == week.length - 1
                                ? 'Hoy'
                                : _days[d.day.weekday - 1],
                            style: TextStyle(fontSize: 11, color: p.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Medalla de una meta diaria: a color si ya se cumplió, gris si no.
class _MedalCard extends StatelessWidget {
  const _MedalCard({
    required this.medal,
    required this.name,
    required this.goal,
    required this.bonus,
    required this.done,
  });

  final String medal;
  final String name;
  final int goal;
  final int bonus;
  final int done;

  /// Muestra la medalla con el progreso hacia su meta.
  @override
  Widget build(BuildContext context) {
    final won = done >= goal;
    final p = context.palette;
    return BiffyCard(
      padding: const EdgeInsets.all(10),
      color: won ? AppColors.secondary.withValues(alpha: 0.25) : null,
      border: won ? Border.all(color: AppColors.secondary, width: 2) : null,
      child: Column(
        children: [
          Opacity(
            opacity: won ? 1 : 0.35,
            child: Text(medal, style: const TextStyle(fontSize: 32)),
          ),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(
            '$goal entregas en el día',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: p.muted),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (done / goal).clamp(0, 1).toDouble(),
            minHeight: 5,
            borderRadius: BorderRadius.circular(3),
            color: AppColors.primary,
            backgroundColor: p.border,
          ),
          const SizedBox(height: 4),
          Text(
            won
                ? 'Meta cumplida · ${cop(bonus)}'
                : 'Faltan ${goal - done} · ${cop(bonus)}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
