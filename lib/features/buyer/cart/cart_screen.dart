import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/cart.dart';
import '../../../data/models/catalog.dart';
import '../../../domain/catalog_rules.dart';
import '../../../domain/pricing.dart';
import '../../../shared/state/cart_controller.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import 'cart_draft.dart';
import 'schedule_sheet.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final TextEditingController _note = TextEditingController(
    text: context.read<CartController>().restaurantNote,
  );

  @override
  void initState() {
    super.initState();
    _note; // Inicializa mientras el contexto está activo.
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final orders = context.read<OrderService>();
    final t = Theme.of(context).textTheme;

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Tu carrito')),
        body: EmptyState(
          emoji: '🛒',
          title: 'Tu carrito está vacío',
          body: 'Explora platos cerca de ti y agrégalos aquí.',
          actionLabel: 'Explorar comida',
          onAction: () => context.go('/explorar'),
        ),
      );
    }

    final r = cart.restaurant!;
    final address = session.isLoggedIn ? cartAddress(session, cart) : null;
    final point = address == null ? session.point : pointById(address.pointId);
    final reachable = isReachable(r, point);
    final draft = draftFromCart(context);
    final totals = orders.preview(draft);
    final payment = cart.payment ?? session.data.defaultPayment;
    final coupons = session.data.coupons.where((c) => !c.used).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tu carrito'),
        actions: [
          TextButton(
            key: const Key('clear-cart'),
            onPressed: () async {
              final ok = await showConfirm(
                context,
                title: '¿Vaciar carrito?',
                message: 'Se quitarán todos los productos.',
                confirm: 'Vaciar',
                destructive: true,
              );
              if (ok) cart.clear();
            },
            child: const Text(
              'Vaciar',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            BiffyCard(
              padding: const EdgeInsets.all(12),
              onTap: () => context.push('/restaurante/${r.id}'),
              child: Row(
                children: [
                  FoodImage(emoji: r.emoji, asset: r.imageAsset, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text('Agregar más productos', style: t.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.add_circle_outline),
                ],
              ),
            ),
            if (!reachable)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠️ ${r.name} no entrega en ${point.name}. Cambia la dirección o el punto de entrega.',
                  style: const TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            for (final l in cart.pricedLines) _CartLine(line: l),
            const SectionHeader('Nota para el restaurante'),
            TextField(
              key: const Key('cart-note'),
              controller: _note,
              maxLength: 140,
              onChanged: cart.setNote,
              decoration: const InputDecoration(
                hintText: 'Indicaciones generales del pedido',
              ),
            ),
            const SectionHeader('¿Cuándo?'),
            Row(
              children: [
                Expanded(
                  child: SelectPill(
                    key: const Key('when-now'),
                    label: 'Ahora',
                    selected: cart.scheduledFor == null,
                    onTap: () => cart.setSchedule(null),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectPill(
                    key: const Key('when-schedule'),
                    label: 'Programar',
                    selected: cart.scheduledFor != null,
                    onTap: () => _schedule(context, r),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (cart.scheduledFor != null)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '📅 ${dateTimeLabel(cart.scheduledFor!)}',
                      style: t.titleSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _schedule(context, r),
                    child: const Text('Cambiar'),
                  ),
                ],
              )
            else
              Text(
                catalog.isOpen(r)
                    ? 'Entrega estimada: ~${etaMinutes(r, point)} min'
                    : '${r.name} está cerrado ahora. Programa tu pedido.',
                style: t.bodySmall?.copyWith(
                  color: catalog.isOpen(r) ? null : AppColors.error,
                ),
              ),
            const SectionHeader('Dirección de entrega'),
            if (!session.isLoggedIn)
              BiffyCard(
                padding: const EdgeInsets.all(12),
                onTap: () => showDeliveryPointSheet(context),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${session.point.name}\nInicia sesión al confirmar para elegir tu dirección.',
                        style: t.bodySmall,
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              )
            else
              BiffyCard(
                key: const Key('cart-address'),
                padding: const EdgeInsets.all(12),
                onTap: () => _pickAddress(context),
                child: Row(
                  children: [
                    const Icon(Icons.home_outlined, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: address == null
                          ? const Text(
                              'Agrega una dirección',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  address.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(address.full, style: t.bodySmall),
                              ],
                            ),
                    ),
                    const Text(
                      'Cambiar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            const SectionHeader('Método de pago'),
            Text(
              'Simulado: no se procesan pagos ni se piden datos bancarios.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in PaymentMethod.values)
                  SelectPill(
                    key: Key('pay-${m.name}'),
                    label: m.label,
                    emoji: m.emoji,
                    selected: payment == m,
                    onTap: () => cart.setPayment(m),
                  ),
              ],
            ),
            if (session.isLoggedIn) ...[
              const SectionHeader('Gotas y cupones'),
              SwitchListTile(
                key: const Key('use-gotas'),
                contentPadding: EdgeInsets.zero,
                title: Text('Usar mis Gotas (${session.gotas} disponibles)'),
                subtitle: Text(
                  '1 Gota = ${cop(kGotaValue)} (referencia de la demo)',
                ),
                value: cart.useGotas,
                onChanged: session.gotas > 0 ? cart.setUseGotas : null,
              ),
              if (coupons.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SelectPill(
                      label: 'Sin cupón',
                      selected: cart.couponId == null,
                      onTap: () => cart.setCoupon(null),
                    ),
                    for (final c in coupons)
                      SelectPill(
                        label: '🎟️ ${c.title}',
                        selected: cart.couponId == c.id,
                        onTap: () => cart.setCoupon(c.id),
                      ),
                  ],
                ),
            ],
            const SectionHeader('Propina para el repartidor'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final tip in TipOption.values)
                  SelectPill(
                    key: Key('tip-${tip.name}'),
                    label: tip == TipOption.none
                        ? tip.label
                        : '${tip.label} · ${cop(tipAmount(totals.subtotal, tip))}',
                    selected: cart.tip == tip,
                    onTap: () => cart.setTip(tip),
                  ),
              ],
            ),
            const SectionHeader('Resumen'),
            TotalsCard(totals: totals),
            const SizedBox(height: 16),
            PrimaryButton(
              key: const Key('go-checkout'),
              label: 'Continuar al checkout · ${cop(totals.total)}',
              onPressed: () async {
                if (!await requireLogin(
                  context,
                  reason: 'confirmar tu pedido',
                )) {
                  return;
                }
                if (context.mounted) context.push('/checkout');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _schedule(BuildContext context, Restaurant r) async {
    final cart = context.read<CartController>();
    final when = await showScheduleSheet(
      context,
      restaurant: r,
      now: context.read<CatalogController>().now,
      initial: cart.scheduledFor,
    );
    if (when != null) cart.setSchedule(when);
  }

  Future<void> _pickAddress(BuildContext context) async {
    final session = context.read<SessionController>();
    final cart = context.read<CartController>();
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Elige la dirección',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            for (final a in session.data.addresses)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  a.id == cartAddress(session, cart)?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: AppColors.primary,
                ),
                title: Text(a.label),
                subtitle: Text('${a.full} · zona ${pointById(a.pointId).name}'),
                onTap: () {
                  cart.setAddress(a.id);
                  session.setPoint(a.pointId);
                  Navigator.pop(ctx);
                },
              ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                context.push('/direcciones/nueva');
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar dirección'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  const _CartLine({required this.line});
  final PricedLine line;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
    final d = line.dish;
    final it = line.item;
    final detail = selectionDetail(d, it.selection);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BiffyCard(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FoodImage.dish(d, size: 60),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if (detail.isNotEmpty) Text(detail, style: t.bodySmall),
                      if (it.note.isNotEmpty)
                        Text('📝 ${it.note}', style: t.bodySmall),
                      Text(
                        '${cop(unitPrice(d, it.selection))} c/u',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  cop(line.total),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            Row(
              children: [
                TextButton.icon(
                  key: Key('edit-${it.lineId}'),
                  onPressed: () =>
                      context.push('/plato/${d.id}?edit=${it.lineId}'),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
                IconButton(
                  tooltip: 'Eliminar ${d.name}',
                  icon: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  onPressed: () {
                    cart.remove(it.lineId);
                    showSnack(context, '${d.name} eliminado');
                  },
                ),
                const Spacer(),
                QtyStepper(
                  key: Key('qty-${it.lineId}'),
                  value: it.qty,
                  min: 0,
                  compact: true,
                  onChanged: (v) => cart.setQty(it.lineId, v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Desglose de valores reutilizado en carrito, checkout y seguimiento.
class TotalsCard extends StatelessWidget {
  const TotalsCard({super.key, required this.totals});
  final CartTotals totals;

  @override
  Widget build(BuildContext context) {
    return BiffyCard(
      child: Column(
        children: [
          InfoRow('Subtotal', cop(totals.subtotal)),
          if (totals.campusDiscount > 0)
            InfoRow(
              'Descuento campus',
              '-${cop(totals.campusDiscount)}',
              valueColor: AppColors.success,
            ),
          if (totals.couponDiscount > 0)
            InfoRow(
              'Cupón',
              '-${cop(totals.couponDiscount)}',
              valueColor: AppColors.success,
            ),
          if (totals.gotasUsed > 0)
            InfoRow(
              'Gotas (${totals.gotasUsed})',
              '-${cop(totals.gotasDiscount)}',
              valueColor: AppColors.success,
            ),
          InfoRow('Tarifa de entrega (simulada)', cop(totals.deliveryFee)),
          InfoRow('Propina', cop(totals.tip)),
          const Divider(height: 16),
          InfoRow('Total', cop(totals.total), bold: true),
        ],
      ),
    );
  }
}
