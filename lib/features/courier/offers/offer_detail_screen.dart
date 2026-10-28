import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import 'offer_widgets.dart';

/// Detalle de una oferta con productos y botones para aceptar o rechazar.
class OfferDetailScreen extends StatelessWidget {
  const OfferDetailScreen({super.key, required this.id});
  final String id;

  /// Muestra la oferta o un aviso si ya no está disponible.
  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderService>();
    final session = context.watch<SessionController>();
    final catalog = context.read<CatalogController>();
    final o = orders.byId(id);
    final available =
        o != null && o.status == OrderStatus.ready && o.courierId == null;
    if (o == null || (!available && o.courierId != session.user?.id)) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '📭',
          title: 'Esta oferta ya no está disponible',
          actionLabel: 'Volver al inicio',
          onAction: () => context.go('/repartidor'),
        ),
      );
    }
    final r = catalog.restaurantById(o.restaurantId);
    return Scaffold(
      appBar: AppBar(title: Text('Oferta ${o.id}')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            BiffyCard(
              child: Column(
                children: [
                  InfoRow('Restaurante', o.restaurantName),
                  InfoRow('Punto de recogida', r?.address ?? ''),
                  InfoRow('Destino', o.address.label),
                  InfoRow('Dirección', o.address.line),
                  InfoRow('Distancia estimada', '${o.distanceKm} km'),
                  InfoRow('Tiempo estimado', '~${o.etaMin} min'),
                  InfoRow('Pago estimado', cop(o.courierPay), bold: true),
                  InfoRow('Pago del cliente', paymentForCourier(o)),
                  InfoRow('Estado', o.status.kitchenLabel),
                ],
              ),
            ),
            const SectionHeader('Productos'),
            for (final l in o.lines)
              Text(
                '${l.qty}× ${l.name}${l.detail.isEmpty ? '' : ' · ${l.detail}'}',
              ),
            const SizedBox(height: 24),
            if (available) ...[
              PrimaryButton(
                label: 'Aceptar oferta',
                onPressed: () => acceptOffer(context, o),
              ),
              const SizedBox(height: 8),
              SecondaryButton(
                label: 'Rechazar',
                onPressed: () {
                  declineOffer(context, o);
                  context.go('/repartidor');
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
