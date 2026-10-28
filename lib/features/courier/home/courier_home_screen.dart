import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../data/models/user.dart';
import '../../../domain/order_rules.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import '../offers/offer_widgets.dart';

/// Pantalla de inicio del repartidor con estado, ofertas y entrega en curso.
class CourierHomeScreen extends StatelessWidget {
  const CourierHomeScreen({super.key});

  /// Reúne ganancias, metas y ofertas disponibles del día.
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final orders = context.watch<OrderService>();
    final center = context.watch<NotificationCenter>();
    final now = context.read<CatalogController>().now;
    final t = Theme.of(context).textTheme;
    final u = session.user!;
    final d = session.data;
    final profile = d.courierProfile!;
    final active = orders.activeForCourier(u.id);
    final today = orders
        .deliveredBy(u.id)
        .where((o) => o.deliveredAt != null && sameDay(o.deliveredAt!, now));
    final earnings = computeEarnings(today);
    final offers = orders.availableOffers(
      courierId: u.id,
      zone: d.courierZone,
      universityId: session.verifiedUniversityId,
      vehicle: profile.vehicle,
    );
    final next = kCourierGoals.firstWhere(
      (g) => g.$1 > earnings.deliveries,
      orElse: () => kCourierGoals.last,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hola, ${profile.fullName.split(' ').first} 🛵',
                        style: t.headlineSmall,
                      ),
                      Text(
                        '${profile.vehicle.emoji} ${profile.vehicle.label}${profile.plate == null ? '' : ' · ${profile.plate}'}',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Notificaciones',
                  icon: Badge(
                    isLabelVisible: center.unreadFor(u, UserRole.courier) > 0,
                    label: Text('${center.unreadFor(u, UserRole.courier)}'),
                    child: const Icon(Icons.notifications_none),
                  ),
                  onPressed: () => context.push('/notificaciones'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            BiffyCard(
              color: d.courierOnline
                  ? AppColors.success.withValues(alpha: 0.12)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SwitchListTile(
                key: const Key('courier-online'),
                contentPadding: EdgeInsets.zero,
                title: Text(
                  d.courierOnline ? 'CONECTADO' : 'DESCONECTADO',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: d.courierOnline ? AppColors.success : null,
                  ),
                ),
                subtitle: Text(
                  d.courierOnline
                      ? 'Recibes ofertas de pedidos listos'
                      : 'Conéctate para ver ofertas',
                ),
                value: d.courierOnline,
                onChanged: (v) => session.setCourierOnline(v),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final z in CourierZone.values)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: z == CourierZone.general ? 8 : 0,
                      ),
                      child: SelectPill(
                        key: Key('zone-${z.name}'),
                        label: z == CourierZone.general
                            ? '🛵 General'
                            : '🎓 Campus${session.isVerifiedStudent ? '' : ' 🔒'}',
                        selected: d.courierZone == z,
                        onTap: () {
                          if (!session.setCourierZone(z)) {
                            showSnack(
                              context,
                              'El modo Campus requiere universidad verificada (simulada)',
                              error: true,
                            );
                          }
                        },
                      ),
                    ),
                  ),
              ],
            ),
            if (!session.isVerifiedStudent)
              TextButton(
                onPressed: () => context.push('/campus'),
                child: const Text(
                  'Verificar universidad para desbloquear Campus',
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: BigNumber(
                    'Ganancias de hoy',
                    cop(earnings.net),
                    highlight: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BigNumber('Entregas de hoy', '${earnings.deliveries}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            BiffyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '🏆 Meta del día: ${next.$1} entregas',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (earnings.deliveries / next.$1)
                        .clamp(0, 1)
                        .toDouble(),
                    color: AppColors.primary,
                    backgroundColor: context.palette.border,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${earnings.deliveries}/${next.$1} · bono de demostración ${cop(next.$2)} (no se liquida)',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
            const SectionHeader('Demanda cerca de ti'),
            DemandMap(
              labels: d.courierZone == CourierZone.campus
                  ? const ['Plazoleta', 'Biblioteca', 'Edificio D']
                  : const ['Campus Icesi', 'Pance', 'Chapinero'],
            ),
            if (active != null) ...[
              const SectionHeader('Entrega en curso'),
              BiffyCard(
                key: const Key('active-delivery'),
                border: Border.all(color: AppColors.primary, width: 2),
                onTap: () => context.go(
                  active.status == OrderStatus.ready
                      ? '/repartidor/recogida/${active.id}'
                      : '/repartidor/entrega/${active.id}',
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${active.id} · ${active.restaurantName}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            active.status == OrderStatus.ready
                                ? 'Ve a recoger el pedido'
                                : 'Entrega a ${active.buyerName}',
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Text(
                      'Continuar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            ],
            SectionHeader(
              'Pedidos disponibles${d.courierOnline ? ' (${offers.length})' : ''}',
            ),
            if (!d.courierOnline)
              EmptyState(
                emoji: '😴',
                title: 'Estás desconectado',
                body: 'Conéctate para recibir ofertas.',
                actionLabel: 'Conectarme',
                onAction: () => session.setCourierOnline(true),
              )
            else if (active != null)
              Text(
                'Termina tu entrega actual para aceptar otra oferta.',
                style: t.bodySmall,
              )
            else if (offers.isEmpty)
              EmptyState(
                emoji: '📭',
                title: 'No hay ofertas en este momento',
                body:
                    'Las ofertas aparecen cuando un restaurante marca un pedido como listo.',
                actionLabel: d.courierZone == CourierZone.campus
                    ? 'Cambiar a General'
                    : 'Ver modo Campus',
                onAction: () {
                  final ok = session.setCourierZone(
                    d.courierZone == CourierZone.campus
                        ? CourierZone.general
                        : CourierZone.campus,
                  );
                  if (!ok) {
                    showSnack(
                      context,
                      'El modo Campus requiere universidad verificada',
                      error: true,
                    );
                  }
                },
              )
            else
              for (final o in offers) OfferCard(order: o),
          ],
        ),
      ),
    );
  }
}
