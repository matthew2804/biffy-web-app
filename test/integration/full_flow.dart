import 'package:biffy/data/models/order.dart';
import 'package:biffy/domain/order_rules.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:biffy/shared/state/order_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Abre el selector de cuentas demo desde el perfil del rol actual y entra
/// con la cuenta [userId].
Future<void> switchDemoAccount(WidgetTester tester, String userId) async {
  await tapVisible(tester, find.text('Perfil').last);
  await tapVisible(tester, find.text('Cuentas de demostración'));
  await scrollTo(
    tester,
    find.byKey(Key('demo-$userId')),
    scrollable: find
        .descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.tap(find.byKey(Key('demo-$userId')));
  await tester.pumpAndSettle();
}

/// Flujo completo comprador → restaurante → repartidor → historial, todo
/// mediante la interfaz y sobre el mismo estado compartido.
Future<void> runFullOrderFlow(WidgetTester tester, AppServices s) async {
  // 1. El comprador abre la app y explora sin sesión.
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
  expect(find.text('¿Qué se te antoja hoy? 🐝'), findsOneWidget);
  expect(s.session.isLoggedIn, isFalse);

  // 2-4. Restaurante → plato con extra → carrito.
  await tapVisible(tester, find.byKey(const Key('qbano-strip')));
  expect(find.text('Qbano · Icesi'), findsWidgets);
  await tapVisible(tester, find.text('Qbano Especial'));
  await tapVisible(tester, find.byKey(const Key('extra-qe-queso')));
  await tester.tap(find.byKey(const Key('add-to-cart')));
  await tester.pumpAndSettle();
  expect(s.cart.count, 1);
  expect(s.cart.subtotal, 24900 + 3000);

  // 5. Al confirmar se pide iniciar sesión y luego continúa el flujo.
  await tester.tap(find.byKey(const Key('cart-bar')));
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const Key('when-now')));
  await tapVisible(tester, find.byKey(const Key('pay-cash')));
  await tapVisible(tester, find.byKey(const Key('tip-ten')));
  await tapVisible(tester, find.byKey(const Key('go-checkout')));
  expect(find.text('Inicia sesión para confirmar tu pedido'), findsOneWidget);
  await tester.tap(find.text('Iniciar sesión').last);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const Key('quick-buyer')));
  expect(s.session.user?.id, 'u-diego');

  // 6-8. Resumen (dirección, hora, pago) y confirmación.
  expect(find.text('Confirmar pedido'), findsOneWidget);
  expect(find.textContaining('Biblioteca Icesi'), findsWidgets);
  expect(find.text('Efectivo'), findsWidgets);
  final before = s.orders.all.length;
  await tapVisible(tester, find.byKey(const Key('confirm-order')));

  // 9. Se crea una sola vez con ID único.
  expect(s.orders.all.length, before + 1);
  final order = s.orders.forBuyer('u-diego').first;
  expect(s.orders.all.where((o) => o.id == order.id), hasLength(1));
  expect(order.status, OrderStatus.pending);
  expect(find.text('Pedido ${order.id}'), findsOneWidget);
  expect(find.text(order.deliveryCode), findsOneWidget);

  // 10-11. El restaurante (cuenta demo) recibe y acepta el pedido.
  await waitSnackBars(tester);
  await tapVisible(tester, find.byKey(const Key('demo-open-restaurant')));
  final metricsBefore = computeMetrics(
    orders: s.orders.forBusiness('qbano'),
    dishes: s.catalog.productsOf('qbano'),
    branches: s.catalog.branchesOf('qbano'),
    now: kTestNow,
  );
  expect(find.byKey(Key('kitchen-${order.id}')), findsOneWidget);
  await tapVisible(tester, find.byKey(Key('accept-order-${order.id}')));

  // 12. El comprador vería «Preparando».
  expect(order.status.buyerLabel, 'Preparando');

  // 13-14. Listo → pasa a las ofertas.
  await waitSnackBars(tester);
  await tapVisible(tester, find.byKey(Key('ready-order-${order.id}')));
  expect(order.status, OrderStatus.ready);
  expect(
    s.orders
        .availableOffers(
          courierId: 'u-andres',
          zone: s.session.data.courierZone,
        )
        .map((o) => o.id),
    contains(order.id),
  );

  // 15. Un repartidor conectado acepta el pedido.
  await waitSnackBars(tester);
  await switchDemoAccount(tester, 'u-andres');
  expect(find.byKey(const Key('courier-online')), findsOneWidget);
  final deliveriesBefore = computeEarnings(
    s.orders
        .deliveredBy('u-andres')
        .where(
          (o) => o.deliveredAt != null && o.deliveredAt!.day == kTestNow.day,
        ),
  ).deliveries;
  await tapVisible(tester, find.byKey(const Key('courier-online')));
  await tapVisible(tester, find.byKey(Key('accept-${order.id}')));
  expect(order.courierId, 'u-andres');

  // 16. Ya no está disponible para otros repartidores.
  expect(
    s.orders
        .availableOffers(
          courierId: 'u-valentina',
          zone: s.session.data.courierZone,
        )
        .map((o) => o.id),
    isNot(contains(order.id)),
  );
  expect(
    s.orders.courierAccept(order.id, s.session.auth.byId('u-valentina')!),
    CourierAcceptResult.alreadyAssigned,
  );

  // 17-19. Recogida con los tres checks → en camino.
  await waitSnackBars(tester);
  for (var i = 0; i < 3; i++) {
    await tapVisible(tester, find.byKey(Key('check-$i')));
  }
  await tapVisible(tester, find.byKey(const Key('confirm-pickup')));
  expect(order.status, OrderStatus.onTheWay);
  expect(order.status.buyerLabel, 'En camino');

  // 20-21. Código + evidencia → entregado.
  await waitSnackBars(tester);
  await tester.enterText(
    find.byKey(const Key('delivery-code-input')),
    order.deliveryCode,
  );
  await tapVisible(tester, find.byKey(const Key('demo-evidence')));
  await tapVisible(tester, find.byKey(const Key('mark-delivered')));
  expect(order.status, OrderStatus.delivered);

  // 24. Ganancias del repartidor actualizadas.
  await waitSnackBars(tester);
  expect(find.text('${deliveriesBefore + 1}'), findsWidgets);
  await tapVisible(tester, find.text('Ganancias').last);
  await scrollTo(tester, find.byKey(Key('earning-${order.id}')));
  expect(find.byKey(Key('earning-${order.id}')), findsOneWidget);

  // 23. Métricas del restaurante actualizadas.
  final metricsAfter = computeMetrics(
    orders: s.orders.forBusiness('qbano'),
    dishes: s.catalog.productsOf('qbano'),
    branches: s.catalog.branchesOf('qbano'),
    now: kTestNow,
  );
  expect(metricsAfter.completedCount, metricsBefore.completedCount + 1);

  // 22. El comprador lo ve en su historial.
  await waitSnackBars(tester);
  await switchDemoAccount(tester, 'u-diego');
  await tapVisible(tester, find.text('Perfil').last);
  await tapVisible(tester, find.byKey(const Key('menu-orders')));
  await tapVisible(tester, find.textContaining('Anteriores'));
  expect(find.byKey(Key('order-${order.id}')), findsOneWidget);
  await tapVisible(tester, find.byKey(Key('order-${order.id}')));
  expect(find.text('Entregado'), findsWidgets);
}
