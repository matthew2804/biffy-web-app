import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/confetti.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/catalog_rules.dart';
import '../../../domain/pricing.dart';
import '../../../shared/state/cart_controller.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import 'cart_draft.dart';
import 'cart_screen.dart';

/// Resumen final y confirmación del pedido de demostración (sin pagos).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _placing = false;

  @override
  Widget build(BuildContext context) {
    context.watch<CartController>();
    context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final orders = context.read<OrderService>();
    final t = Theme.of(context).textTheme;
    final draft = draftFromCart(context);
    final r = draft.restaurant;
    if (r == null || draft.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: EmptyState(
          emoji: '🛒',
          title: 'No hay productos para confirmar',
          actionLabel: 'Explorar comida',
          onAction: () => context.go('/explorar'),
        ),
      );
    }
    final totals = orders.preview(draft);
    final errors = orders.validate(draft);
    final point = draft.address == null
        ? null
        : pointById(draft.address!.pointId);

    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar pedido')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const DemoBadge('Pedido de demostración · sin cobros reales'),
            const SizedBox(height: 12),
            BiffyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.name, style: t.titleMedium),
                  const SizedBox(height: 8),
                  for (final i in draft.items)
                    if (catalog.dishById(i.dishId) case final d?)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${i.qty}×  ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (selectionDetail(
                                    d,
                                    i.selection,
                                  ).isNotEmpty)
                                    Text(
                                      selectionDetail(d, i.selection),
                                      style: t.bodySmall,
                                    ),
                                  if (i.note.isNotEmpty)
                                    Text('📝 ${i.note}', style: t.bodySmall),
                                ],
                              ),
                            ),
                            Text(cop(lineTotal(d, i.selection, i.qty))),
                          ],
                        ),
                      ),
                  if (draft.restaurantNote.isNotEmpty)
                    Text('Nota: ${draft.restaurantNote}', style: t.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BiffyCard(
              child: Column(
                children: [
                  InfoRow(
                    'Entrega',
                    draft.address == null
                        ? 'Sin dirección'
                        : '${draft.address!.label} · ${draft.address!.line}',
                  ),
                  InfoRow(
                    'Fecha y hora',
                    draft.scheduledFor == null
                        ? 'Ahora'
                        : dateTimeLabel(draft.scheduledFor!),
                  ),
                  InfoRow('Método de pago (simulado)', draft.payment.label),
                  if (point != null)
                    InfoRow(
                      'Tiempo estimado',
                      draft.scheduledFor == null
                          ? '~${etaMinutes(r, point)} min'
                          : 'A la hora programada',
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TotalsCard(totals: totals),
            if (draft.payment.name == 'cash')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'El repartidor te cobrará ${cop(totals.total)} en efectivo (simulado).',
                  style: t.bodySmall,
                ),
              ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 12),
              BiffyCard(
                key: const Key('checkout-errors'),
                color: AppColors.error.withValues(alpha: 0.1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in errors)
                      Text(
                        '• $e',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text('Volver al carrito'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            PrimaryButton(
              key: const Key('confirm-order'),
              label: _placing
                  ? 'Creando pedido…'
                  : 'Confirmar pedido · ${cop(totals.total)}',
              onPressed: errors.isNotEmpty || _placing
                  ? null
                  : () => _place(context),
            ),
            const SizedBox(height: 8),
            Text(
              'No se realizará ningún cobro: la pasarela de pago está fuera del alcance de este sprint.',
              textAlign: TextAlign.center,
              style: t.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  void _place(BuildContext context) {
    setState(() => _placing = true);
    try {
      final order = context.read<OrderService>().placeOrder(
        draftFromCart(context),
      );
      context.read<CartController>().clear();
      showSnack(context, 'Pedido ${order.id} creado · demostración sin cobros');
      celebrate(context);
      context.go('/pedido/${order.id}');
    } on OrderException catch (e) {
      setState(() => _placing = false);
      showSnack(context, e.message, error: true);
    }
  }
}
