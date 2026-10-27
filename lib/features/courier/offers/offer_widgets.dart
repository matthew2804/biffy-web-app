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
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Foto del restaurante con su nombre encima.
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Stack(
                children: [
                  FoodImage(
                    emoji: r?.emoji ?? '🍽️',
                    asset: r?.imageAsset,
                    size: 110,
                    width: double.infinity,
                    radius: 0,
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 10,
                    child: Text(
                      '${o.restaurantName} · ${o.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Lo que más le importa al repartidor: cuánto gana.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ganas', style: t.bodySmall),
                            Text(
                              cop(o.courierPay),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: AppColors.success,
                                fontSize: 30,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${o.distanceKm} km',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '~${o.etaMin} min · ${o.itemCount} productos',
                            style: t.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _RouteStop(
                    color: AppColors.secondary,
                    title: 'Recoger',
                    detail: r?.address ?? '',
                    line: true,
                  ),
                  _RouteStop(
                    color: AppColors.success,
                    title: 'Entregar',
                    detail: '${o.address.label} · ${o.address.line}',
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: context.palette.surfaceSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '💳 ${paymentForCourier(o)}',
                      style: t.bodySmall,
                    ),
                  ),
                  const SizedBox(height: 8),
                  StatusChip(o.status, kitchen: true),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: Key('decline-${o.id}'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
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
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          onPressed: () =>
                              context.push('/repartidor/oferta/${o.id}'),
                          child: const Text('Detalles'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          key: Key('accept-${o.id}'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
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

/// Un punto del recorrido (recoger o entregar) con la línea punteada que los une.
class _RouteStop extends StatelessWidget {
  const _RouteStop({
    required this.color,
    required this.title,
    required this.detail,
    this.line = false,
  });

  final Color color;
  final String title;
  final String detail;
  final bool line;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 14,
            child: Column(
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                if (line)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: line ? 10 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.palette.muted,
                    ),
                  ),
                  Text(
                    detail,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
