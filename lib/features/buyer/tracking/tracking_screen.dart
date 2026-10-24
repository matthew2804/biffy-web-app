import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../data/models/user.dart';
import '../../../domain/pricing.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import '../cart/cart_screen.dart';
import '../orders/reorder_flow.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderService>();
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    final o = orders.byId(id);
    if (o == null || (session.user != null && o.buyerId != session.user!.id)) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🔎',
          title: 'Pedido no encontrado',
          actionLabel: 'Volver al historial',
          onAction: () => context.go('/pedidos'),
        ),
      );
    }
    final steps = ['Confirmado', 'Preparando', 'En camino', 'Entregado'];
    final step = o.status.buyerStep;
    final sub = switch (o.status) {
      OrderStatus.pending =>
        o.isScheduled
            ? 'Programado para ${dateTimeLabel(o.scheduledFor!)}. Esperando confirmación del restaurante.'
            : 'Esperando que ${o.restaurantName} acepte tu pedido.',
      OrderStatus.preparing => '${o.restaurantName} está preparando tu pedido.',
      OrderStatus.ready =>
        o.courierName == null
            ? 'Tu pedido está listo. Buscando repartidor…'
            : 'Listo. ${o.courierName} va a recogerlo.',
      OrderStatus.onTheWay => '${o.courierName} va en camino.',
      OrderStatus.delivered =>
        'Entregado ${o.deliveredAt == null ? '' : 'a las ${hourLabel(o.deliveredAt!)}'}. ¡Buen provecho!',
      OrderStatus.cancelled =>
        'Cancelado: ${o.rejectReason ?? 'sin motivo'}. No se realizó ningún cobro.',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Pedido ${o.id}'),
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/pedidos'),
        ),
      ),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            BiffyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(o.restaurantName, style: t.titleMedium),
                      ),
                      StatusChip(o.status, key: const Key('buyer-status')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(sub, style: t.bodyMedium),
                  if (!o.status.isFinal && !o.isScheduled) ...[
                    const SizedBox(height: 6),
                    Text(
                      '⏱ Tiempo estimado: ~${o.etaMin} min',
                      style: t.titleSmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (o.status != OrderStatus.cancelled)
                    Row(
                      children: [
                        for (var i = 0; i < steps.length; i++)
                          Expanded(
                            child: Column(
                              children: [
                                Container(
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i <= step
                                        ? AppColors.primary
                                        : context.palette.border,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  steps[i],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: i == step
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (!o.status.isFinal) ...[
              const SizedBox(height: 12),
              BiffyCard(
                color: AppColors.primary,
                child: Column(
                  children: [
                    const Text(
                      'Código de entrega',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.text,
                      ),
                    ),
                    Text(
                      o.deliveryCode,
                      key: const Key('delivery-code'),
                      style: const TextStyle(
                        fontFamily: AppTypography.heading,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 8,
                        color: AppColors.text,
                      ),
                    ),
                    const Text(
                      'Dáselo al repartidor solo cuando recibas tu pedido.',
                      style: TextStyle(fontSize: 12, color: AppColors.text),
                    ),
                  ],
                ),
              ),
            ],
            if (o.courierName != null) ...[
              const SizedBox(height: 12),
              BiffyCard(
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.surfaceSoft,
                      child: Text('🛵'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.courierName!,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            'Repartidor de demostración · sin GPS en vivo',
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(96, 44),
                      ),
                      onPressed: () => _contact(context, o),
                      child: const Text('Contacto'),
                    ),
                  ],
                ),
              ),
            ],
            const SectionHeader('Resumen del pedido'),
            BiffyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final l in o.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l.qty}× ',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name),
                                if (l.detail.isNotEmpty)
                                  Text(l.detail, style: t.bodySmall),
                                if (l.note.isNotEmpty)
                                  Text('📝 ${l.note}', style: t.bodySmall),
                              ],
                            ),
                          ),
                          Text(cop(l.total)),
                        ],
                      ),
                    ),
                  const Divider(),
                  InfoRow('Dirección', o.address.label),
                  Text(o.address.full, style: t.bodySmall),
                  InfoRow('Creado', dateTimeLabel(o.createdAt)),
                  if (o.isScheduled)
                    InfoRow('Programado', dateTimeLabel(o.scheduledFor!)),
                  InfoRow('Pago (simulado)', o.payment.label),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TotalsCard(
              totals: CartTotals(
                subtotal: o.subtotal,
                campusDiscount: o.campusDiscount,
                couponDiscount: o.couponDiscount,
                deliveryFee: o.deliveryFee,
                gotasUsed: o.gotasUsed,
                tip: o.tip,
              ),
            ),
            const SizedBox(height: 16),
            if (o.status == OrderStatus.pending)
              SecondaryButton(
                key: const Key('cancel-order'),
                label: 'Cancelar pedido',
                foreground: AppColors.error,
                onPressed: () async {
                  final ok = await showConfirm(
                    context,
                    title: '¿Cancelar el pedido?',
                    message:
                        'Solo puedes cancelar antes de que el restaurante lo acepte.',
                    confirm: 'Cancelar pedido',
                    cancel: 'Volver',
                    destructive: true,
                  );
                  if (ok && context.mounted) {
                    final done = context.read<OrderService>().cancelByBuyer(
                      o.id,
                    );
                    showSnack(
                      context,
                      done ? 'Pedido cancelado' : 'El restaurante ya lo aceptó',
                      error: !done,
                    );
                  }
                },
              ),
            if (o.status == OrderStatus.delivered ||
                o.status == OrderStatus.cancelled)
              PrimaryButton(
                label: 'Pedir de nuevo',
                icon: Icons.replay,
                onPressed: () => reorderToCart(context, o),
              ),
            if (!o.status.isFinal) _DemoControls(order: o),
          ],
        ),
      ),
    );
  }

  void _contact(BuildContext context, Order o) {
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
                'Contacto simulado',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'El chat y las llamadas en tiempo real no están disponibles en este sprint. '
                'Puedes copiar los datos de demostración del pedido para compartirlos.',
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Copiar datos del pedido',
                icon: Icons.copy,
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          'Pedido ${o.id} · ${o.restaurantName} · Repartidor: ${o.courierName}',
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (context.mounted) {
                    showSnack(context, 'Datos copiados al portapapeles');
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Atajos de demostración: abren el pedido con las cuentas demo de los otros
/// roles para avanzar el flujo real (no salta validaciones).
class _DemoControls extends StatelessWidget {
  const _DemoControls({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final catalog = context.read<CatalogController>();
    final r = catalog.restaurantById(order.restaurantId);
    final owner = r == null ? null : session.auth.byBusiness(r.businessId);
    final kitchen =
        order.status == OrderStatus.pending ||
        order.status == OrderStatus.preparing;
    final courier =
        order.status == OrderStatus.ready ||
        order.status == OrderStatus.onTheWay;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: BiffyCard(
        color: context.palette.surfaceSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🧪 Modo demostración',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'Sin backend, el pedido avanza cuando el restaurante y el repartidor actúan en esta misma app. '
              'Cambia de cuenta para continuar el flujo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (kitchen && owner != null)
              TextButton.icon(
                key: const Key('demo-open-restaurant'),
                icon: const Icon(Icons.storefront),
                label: Text('Abrir como ${r!.name}'),
                onPressed: () {
                  session.loginAs(owner);
                  context.go('/negocio/pedidos');
                },
              ),
            if (courier && order.courierId == null)
              TextButton.icon(
                icon: const Icon(Icons.delivery_dining),
                label: const Text('Abrir como repartidor demo'),
                onPressed: () {
                  final u = session.auth.byId('u-andres');
                  if (u == null) return;
                  session.loginAs(u);
                  session.setActiveRole(UserRole.courier);
                  context.go('/repartidor');
                },
              ),
            if (courier && order.courierId != null)
              TextButton.icon(
                icon: const Icon(Icons.delivery_dining),
                label: Text('Abrir como ${order.courierName}'),
                onPressed: () {
                  final u = session.auth.byId(order.courierId!);
                  if (u == null) return;
                  session.loginAs(u);
                  context.go('/repartidor');
                },
              ),
          ],
        ),
      ),
    );
  }
}
