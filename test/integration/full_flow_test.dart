import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/models/order.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import 'full_flow.dart';

void main() {
  testWidgets(
    'flujo completo Comprador → Restaurante → Repartidor → Historial',
    (tester) async {
      final s = makeServices();
      await pumpBiffy(
        tester,
        services: s,
        initialLocation: '/splash',
        settle: false,
      );
      await runFullOrderFlow(tester, s);
    },
  );

  testWidgets('dos repartidores no pueden tomar el mismo pedido', (
    tester,
  ) async {
    final s = makeServices();
    final o = await placeQbano(s);
    await s.orders.useCases.acceptOrder(o.id);
    await s.orders.useCases.markOrderReady(o.id);
    s.session.logout();

    // Valentina ve la oferta en su pantalla de detalle.
    s.session.login(kDemoCourier2Email, kDemoPassword);
    await pumpBiffy(
      tester,
      services: s,
      initialLocation: '/repartidor/oferta/${o.id}',
    );
    expect(find.text('Aceptar oferta'), findsOneWidget);

    // Andrés la acepta primero en el mismo estado compartido.
    expect(
      (await s.orders.useCases.acceptOffer(
        o.id,
        s.session.auth.byId('u-andres')!,
      )).code,
      'ok',
    );
    await tester.pumpAndSettle();

    // La pantalla de Valentina se actualiza y el servicio rechaza el duplicado.
    expect(find.text('Esta oferta ya no está disponible'), findsOneWidget);
    expect(
      (await s.orders.useCases.acceptOffer(o.id, s.session.user!)).code,
      'already_assigned',
    );
    expect(o.courierId, 'u-andres');
    expect(o.status, OrderStatus.ready);
  });
}
