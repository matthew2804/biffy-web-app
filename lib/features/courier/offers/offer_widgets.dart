import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/order.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

String paymentForCourier(Order o) => o.payment == PaymentMethod.cash
    ? 'Efectivo · cobrar ${cop(o.total)}'
    : '${o.payment.label} · pago simulado';

/// Aceptar una oferta: asignación atómica en el estado compartido.
void acceptOffer(BuildContext context, Order o) {
  final session = context.read<SessionController>();
  final res = context.read<OrderService>().courierAccept(
    o.id,
    session.user!,
    vehicle: session.data.courierProfile?.vehicle,
  );
  switch (res) {
    case CourierAcceptResult.ok:
      showSnack(context, 'Pedido ${o.id} aceptado');
      context.go('/repartidor/recogida/${o.id}');
    case CourierAcceptResult.alreadyAssigned:
      showSnack(context, 'Otro repartidor ya tomó este pedido', error: true);
    case CourierAcceptResult.notAvailable:
      showSnack(context, 'La oferta ya no está disponible', error: true);
    case CourierAcceptResult.busy:
      showSnack(
        context,
        'Termina tu entrega actual antes de aceptar otra',
        error: true,
      );
    case CourierAcceptResult.outOfRange:
      showSnack(
        context,
        'La distancia supera el alcance de tu medio de transporte',
        error: true,
      );
  }
}

void declineOffer(BuildContext context, Order o) {
  final session = context.read<SessionController>();
  context.read<OrderService>().courierDecline(o.id, session.user!.id);
  showSnack(context, 'Oferta rechazada · no afecta tu nivel');
}

class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final catalog = context.read<CatalogController>();
    final r = catalog.restaurantById(o.restaurantId);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BiffyCard(
        key: Key('offer-${o.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${o.restaurantName} · ${o.id}',
                    style: t.titleSmall,
                  ),
                ),
                Text(
                  cop(o.courierPay),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.success,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('📍 Recoger: ${r?.address ?? ''}', style: t.bodySmall),
            Text(
              '🏁 Entregar: ${o.address.label} · ${o.address.line}',
              style: t.bodySmall,
            ),
            Text(
              '${o.distanceKm} km · ~${o.etaMin} min · ${o.itemCount} productos',
              style: t.bodySmall,
            ),
            Text('💳 ${paymentForCourier(o)}', style: t.bodySmall),
            const SizedBox(height: 4),
            StatusChip(o.status, kitchen: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('decline-${o.id}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => declineOffer(context, o),
                    child: const Text('Rechazar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => context.push('/repartidor/oferta/${o.id}'),
                    child: const Text('Detalles'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: Key('accept-${o.id}'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: () => acceptOffer(context, o),
                    child: const Text('Aceptar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Mapa ilustrativo de demanda (no es un mapa real ni usa GPS).
class DemandMap extends StatelessWidget {
  const DemandMap({super.key, required this.labels});
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return BiffyCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 150,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _GridPainter(p.border)),
              ),
              for (final (i, label) in labels.indexed)
                Align(
                  alignment: [
                    const Alignment(-0.6, -0.4),
                    const Alignment(0.5, 0.2),
                    const Alignment(-0.1, 0.6),
                  ][i % 3],
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 34.0 - i * 6,
                        height: 34.0 - i * 6,
                        decoration: BoxDecoration(
                          color:
                              (i == 0 ? AppColors.error : AppColors.secondary)
                                  .withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              Positioned(
                right: 8,
                bottom: 6,
                child: Text(
                  'Ilustrativo · sin GPS',
                  style: TextStyle(fontSize: 10, color: p.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final road = Paint()
      ..color = color.withValues(alpha: 1)
      ..strokeWidth = 6;
    canvas.drawLine(
      Offset(0, size.height * 0.55),
      Offset(size.width, size.height * 0.35),
      road,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}
