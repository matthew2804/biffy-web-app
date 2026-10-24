import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

const _filters = <(String, String, bool Function(Order))>[
  ('todos', 'Todos', _all),
  ('nuevos', 'Nuevos', _new),
  ('preparacion', 'En preparación', _prep),
  ('listos', 'Listos', _ready),
  ('finalizados', 'Finalizados', _done),
];
bool _all(Order o) => true;
bool _new(Order o) => o.status == OrderStatus.pending;
bool _prep(Order o) => o.status == OrderStatus.preparing;
bool _ready(Order o) => o.status == OrderStatus.ready;
bool _done(Order o) =>
    o.status == OrderStatus.onTheWay ||
    o.status == OrderStatus.delivered ||
    o.status == OrderStatus.cancelled;

const kRejectReasons = [
  'Producto agotado',
  'Cocina saturada',
  'Fuera del horario',
  'Dirección fuera de cobertura',
];

class MerchantOrdersScreen extends StatefulWidget {
  const MerchantOrdersScreen({super.key, this.filter});
  final String? filter;

  @override
  State<MerchantOrdersScreen> createState() => _MerchantOrdersScreenState();
}

class _MerchantOrdersScreenState extends State<MerchantOrdersScreen> {
  late String _f = widget.filter ?? 'todos';

  @override
  void didUpdateWidget(covariant MerchantOrdersScreen old) {
    super.didUpdateWidget(old);
    if (widget.filter != null && widget.filter != old.filter) {
      _f = widget.filter!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderService>();
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    final all = orders.forBusiness(session.businessId!)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pred = _filters.firstWhere((x) => x.$1 == _f).$3;
    final list = all.where(pred).toList();
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pedidos', style: t.headlineSmall),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  for (final (id, label, p) in _filters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SelectPill(
                        key: Key('mf-$id'),
                        label: '$label (${all.where(p).length})',
                        selected: _f == id,
                        onTap: () => setState(() => _f = id),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      emoji: '🧾',
                      title: 'No hay pedidos en esta categoría',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      children: [for (final o in list) _KitchenCard(order: o)],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KitchenCard extends StatelessWidget {
  const _KitchenCard({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final orders = context.read<OrderService>();
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: BiffyCard(
        key: Key('kitchen-${o.id}'),
        border: o.status == OrderStatus.pending
            ? Border.all(color: AppColors.primary, width: 2)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${o.id} · ${o.buyerName}', style: t.titleSmall),
                ),
                StatusChip(o.status, kitchen: true),
              ],
            ),
            Text(o.restaurantName, style: t.bodySmall),
            const SizedBox(height: 6),
            for (final l in o.lines) ...[
              Text(
                '${l.qty}× ${l.name}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (l.detail.isNotEmpty)
                Text('   ${l.detail}', style: t.bodySmall),
              if (l.note.isNotEmpty)
                Text('   📝 ${l.note}', style: t.bodySmall),
            ],
            if (o.restaurantNote.isNotEmpty)
              Text('📝 ${o.restaurantNote}', style: t.bodySmall),
            const SizedBox(height: 6),
            Text(
              o.isScheduled
                  ? '📅 Programado: ${dateTimeLabel(o.scheduledFor!)}'
                  : '🕒 Recibido: ${dateTimeLabel(o.createdAt)}',
              style: t.bodySmall,
            ),
            Text(
              '💳 ${o.payment.label} (simulado) · Total ${cop(o.total)}',
              style: t.bodySmall,
            ),
            if (o.status == OrderStatus.cancelled && o.rejectReason != null)
              Text(
                'Motivo: ${o.rejectReason}',
                style: const TextStyle(color: AppColors.error),
              ),
            if (o.status == OrderStatus.ready)
              Text(
                o.courierName == null
                    ? '⏳ Esperando repartidor'
                    : '🛵 Repartidor asignado: ${o.courierName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (o.status == OrderStatus.pending) ...[
                  FilledButton(
                    key: Key('accept-order-${o.id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(120, 44),
                    ),
                    onPressed: () {
                      orders.restaurantAccept(o.id);
                      showSnack(context, 'Pedido ${o.id} en preparación');
                    },
                    child: const Text('Aceptar'),
                  ),
                  OutlinedButton(
                    key: Key('reject-order-${o.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(120, 44),
                      foregroundColor: AppColors.error,
                    ),
                    onPressed: () => _reject(context, o),
                    child: const Text('Rechazar'),
                  ),
                ],
                if (o.status == OrderStatus.preparing)
                  FilledButton(
                    key: Key('ready-order-${o.id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(160, 44),
                    ),
                    onPressed: () {
                      orders.markReady(o.id);
                      showSnack(
                        context,
                        'Pedido ${o.id} listo · visible para repartidores',
                      );
                    },
                    child: const Text('Marcar como listo'),
                  ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(120, 44),
                  ),
                  onPressed: () => _receipt(context, o),
                  icon: const Icon(Icons.receipt_outlined),
                  label: const Text('Recibo'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reject(BuildContext context, Order o) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _RejectDialog(orderId: o.id),
    );
    if (reason == null || !context.mounted) return;
    context.read<OrderService>().restaurantReject(o.id, reason);
    showSnack(context, 'Pedido ${o.id} rechazado');
  }

  void _receipt(BuildContext context, Order o) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Recibo de demostración',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const Text('Documento no fiscal · sin cobros reales'),
            const Divider(height: 24),
            InfoRow('Pedido', o.id),
            InfoRow('Cliente', o.buyerName),
            InfoRow('Fecha', dateTimeLabel(o.createdAt)),
            const Divider(),
            for (final l in o.lines)
              InfoRow('${l.qty}× ${l.name}', cop(l.total)),
            const Divider(),
            InfoRow('Subtotal', cop(o.subtotal)),
            if (o.campusDiscount > 0)
              InfoRow('Descuento campus', '-${cop(o.campusDiscount)}'),
            InfoRow(
              'Ingreso del restaurante',
              cop(o.restaurantRevenue),
              bold: true,
            ),
            InfoRow('Método de pago', o.payment.label),
          ],
        ),
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.orderId});
  final String orderId;

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  String? _reason;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _reason == 'Otro' ? _other.text.trim() : _reason;
    return AlertDialog(
      title: Text('Rechazar ${widget.orderId}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indica el motivo. El cliente lo verá y no se le cobrará nada.',
            ),
            for (final r in [...kRejectReasons, 'Otro'])
              ListTile(
                key: Key('reason-$r'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _reason == r
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: _reason == r ? AppColors.error : null,
                ),
                title: Text(r),
                onTap: () => setState(() => _reason = r),
              ),
            if (_reason == 'Otro')
              TextField(
                controller: _other,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Motivo'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm-reject'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            minimumSize: const Size(100, 44),
          ),
          onPressed: text == null || text.isEmpty
              ? null
              : () => Navigator.pop(context, text),
          child: const Text('Rechazar'),
        ),
      ],
    );
  }
}
