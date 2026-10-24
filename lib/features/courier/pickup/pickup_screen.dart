import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import '../offers/offer_widgets.dart';

/// Recogida: exige los tres checks antes de confirmar.
class PickupScreen extends StatefulWidget {
  const PickupScreen({super.key, required this.id});
  final String id;

  @override
  State<PickupScreen> createState() => _PickupScreenState();
}

class _PickupScreenState extends State<PickupScreen> {
  final _checks = [false, false, false];

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderService>();
    final session = context.watch<SessionController>();
    final catalog = context.read<CatalogController>();
    final t = Theme.of(context).textTheme;
    final o = orders.byId(widget.id);
    if (o == null || o.courierId != session.user?.id) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🔎',
          title: 'Pedido no encontrado o no asignado a ti',
          actionLabel: 'Volver al inicio',
          onAction: () => context.go('/repartidor'),
        ),
      );
    }
    if (o.status != OrderStatus.ready) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '✅',
          title: 'La recogida de ${o.id} ya se confirmó',
          actionLabel: 'Ir a la entrega',
          onAction: () => context.go('/repartidor/entrega/${o.id}'),
        ),
      );
    }
    final r = catalog.restaurantById(o.restaurantId);
    final labels = [
      'Código validado por el restaurante',
      'Bolsa sellada (sin derrames)',
      'Productos verificados (${o.itemCount})',
    ];
    final notes = [
      if (o.restaurantNote.isNotEmpty) o.restaurantNote,
      for (final l in o.lines)
        if (l.note.isNotEmpty) '${l.name}: ${l.note}',
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Recoger ${o.id}')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Paso 1 de 2 · Recoger y verificar',
              style: t.titleSmall?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 8),
            BiffyCard(
              color: AppColors.primary,
              child: Column(
                children: [
                  const Text(
                    'Código de recogida (simulado)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    o.pickupCode,
                    style: const TextStyle(
                      fontFamily: AppTypography.heading,
                      fontSize: 40,
                      letterSpacing: 8,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const Text(
                    'Muéstralo en el restaurante',
                    style: TextStyle(color: AppColors.text),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BiffyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.restaurantName, style: t.titleMedium),
                  Text(r?.address ?? '', style: t.bodySmall),
                  const SizedBox(height: 4),
                  const Tag(
                    'Estado: listo para recoger',
                    color: AppColors.success,
                    textColor: Colors.white,
                  ),
                  const Divider(height: 20),
                  for (final l in o.lines)
                    Text(
                      '${l.qty}× ${l.name}${l.detail.isEmpty ? '' : ' · ${l.detail}'}',
                    ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    for (final n in notes) Text('📝 $n', style: t.bodySmall),
                  ],
                  const SizedBox(height: 8),
                  Text('💳 ${paymentForCourier(o)}', style: t.bodySmall),
                ],
              ),
            ),
            const SectionHeader('Checklist de recogida'),
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < 3; i++)
                    CheckboxListTile(
                      key: Key('check-$i'),
                      value: _checks[i],
                      title: Text(labels[i]),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) => setState(() => _checks[i] = v ?? false),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              key: const Key('confirm-pickup'),
              label: 'Confirmar recogida',
              onPressed: _checks.every((c) => c)
                  ? () {
                      final ok = orders.confirmPickup(
                        o.id,
                        session.user!.id,
                        codeValidated: _checks[0],
                        bagSealed: _checks[1],
                        productsVerified: _checks[2],
                      );
                      if (ok) {
                        showSnack(
                          context,
                          'Recogida confirmada · rumbo al cliente',
                        );
                        context.go('/repartidor/entrega/${o.id}');
                      } else {
                        showSnack(
                          context,
                          'No se pudo confirmar la recogida',
                          error: true,
                        );
                      }
                    }
                  : null,
            ),
            if (!_checks.every((c) => c))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Marca los tres puntos para habilitar la confirmación.',
                  style: t.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
            TextButton.icon(
              onPressed: () => context.push('/soporte'),
              icon: const Icon(Icons.support_agent),
              label: const Text('¿Problema con el pedido? Soporte'),
            ),
          ],
        ),
      ),
    );
  }
}
