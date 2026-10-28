import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../domain/reorder.dart';
import '../../../shared/state/cart_controller.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import '../cart/cart_screen.dart';

/// Evalúa si un pedido anterior se puede repetir en el catálogo actual.
ReorderCheck _check(BuildContext context, Order order) {
  final catalog = context.read<CatalogController>();
  final cart = context.read<CartController>();
  final r = catalog.restaurantById(order.restaurantId);
  return checkReorder(
    order,
    dishOf: catalog.dishById,
    restaurant: r,
    reachable: r != null && catalog.reachable(r),
    newLineId: cart.newLineId,
  );
}

/// Muestra los avisos del reorden y devuelve si se debe continuar.
Future<bool> _showWarnings(
  BuildContext context,
  ReorderCheck c, {
  required String confirm,
}) async {
  if (!c.canReorder) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No se puede repetir este pedido'),
        content: Text(c.warnings.join('\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    return false;
  }
  if (c.warnings.isEmpty) return true;
  return showConfirm(
    context,
    title: 'Revisa antes de continuar',
    message: c.warnings.join('\n'),
    confirm: confirm,
  );
}

/// «Pedir de nuevo»: reconstruye el carrito comprobando disponibilidad y precios.
Future<void> reorderToCart(BuildContext context, Order order) async {
  final c = _check(context, order);
  if (!await _showWarnings(context, c, confirm: 'Agregar al carrito')) return;
  if (!context.mounted) return;
  final cart = context.read<CartController>();
  if (!cart.isEmpty) {
    final ok = await showConfirm(
      context,
      title: '¿Reemplazar tu carrito?',
      message: 'Tu carrito actual se vaciará para cargar este pedido.',
      confirm: 'Reemplazar',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
  }
  cart.loadItems(c.items);
  showSnack(context, 'Carrito listo para ajustar');
  context.push('/carrito');
}

/// «Pedir ya»: muestra resumen y exige confirmación explícita antes de crear
/// el pedido de demostración. Nunca crea pedidos en silencio.
Future<void> orderNow(BuildContext context, Order order) async {
  final c = _check(context, order);
  if (!await _showWarnings(context, c, confirm: 'Continuar')) return;
  if (!context.mounted) return;
  final session = context.read<SessionController>();
  final orders = context.read<OrderService>();
  final draft = CheckoutDraft(
    buyer: session.user,
    restaurant: c.restaurant,
    items: c.items,
    address: session.data.defaultAddress,
    payment: session.data.defaultPayment,
  );
  final totals = orders.preview(draft);
  final errors = orders.validate(draft);
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pedir ya · ${c.restaurant!.name}',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const DemoBadge('Pedido de demostración · sin cobros reales'),
            const SizedBox(height: 12),
            for (final l in order.lines)
              Text(
                '${l.qty}× ${l.name}${l.detail.isEmpty ? '' : ' (${l.detail})'}',
              ),
            const SizedBox(height: 8),
            Text(
              '📍 ${draft.address?.label ?? 'Sin dirección'} · 💳 ${draft.payment.label}',
            ),
            const SizedBox(height: 8),
            TotalsCard(totals: totals),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final e in errors)
                Text('• $e', style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            PrimaryButton(
              key: const Key('order-now-confirm'),
              label: 'Confirmar pedido · ${cop(totals.total)}',
              onPressed: errors.isEmpty ? () => Navigator.pop(ctx, true) : null,
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    final created = orders.placeOrder(draft);
    showSnack(context, 'Pedido ${created.id} creado · sin cobros reales');
    context.push('/pedido/${created.id}');
  } on OrderException catch (e) {
    showSnack(context, e.message, error: true);
  }
}
