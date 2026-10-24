import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/data/models/order.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Crea un pedido de Diego y lo deja en el estado indicado.
Order seedOrder(AppServices s, {OrderStatus until = OrderStatus.pending}) {
  final o = placeQbano(s);
  if (until.index >= OrderStatus.preparing.index) {
    s.orders.restaurantAccept(o.id);
  }
  if (until.index >= OrderStatus.ready.index) s.orders.markReady(o.id);
  s.session.logout();
  return o;
}

void main() {
  group('Login según el rol', () {
    testWidgets('comprador vuelve al inicio', (tester) async {
      await pumpBiffy(tester, initialLocation: '/login');
      await tapVisible(tester, find.byKey(const Key('quick-buyer')));
      expect(find.text('Hola, Diego 👋'), findsOneWidget);
    });

    testWidgets('repartidor abre su panel', (tester) async {
      await pumpBiffy(tester, initialLocation: '/login');
      await tester.enterText(
        find.byKey(const Key('login-email')),
        kDemoCourierEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login-password')),
        kDemoPassword,
      );
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('courier-online')), findsOneWidget);
      expect(find.text('Ganancias'), findsWidgets);
    });

    testWidgets('restaurante abre su panel', (tester) async {
      await pumpBiffy(tester, initialLocation: '/login');
      await tapVisible(tester, find.byKey(const Key('quick-restaurant')));
      expect(find.text('Ventas de hoy (simuladas)'), findsOneWidget);
      expect(find.text('Menú'), findsWidgets);
    });

    testWidgets('contraseña incorrecta muestra error', (tester) async {
      await pumpBiffy(tester, initialLocation: '/login');
      await tester.enterText(
        find.byKey(const Key('login-email')),
        kDemoBuyerEmail,
      );
      await tester.enterText(find.byKey(const Key('login-password')), 'mala');
      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Contraseña incorrecta.'), findsOneWidget);
    });

    testWidgets('ruta protegida redirige al login y retoma la ruta', (
      tester,
    ) async {
      await pumpBiffy(tester, initialLocation: '/recompensas');
      expect(find.text('Inicia sesión'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('quick-buyer')));
      expect(find.text('Gotas Biffy'), findsOneWidget);
    });
  });

  testWidgets('el restaurante ve el pedido creado y lo prepara', (
    tester,
  ) async {
    final s = makeServices();
    final o = seedOrder(s);
    s.session.login(kDemoRestaurantEmail, kDemoPassword);
    await pumpBiffy(tester, services: s, initialLocation: '/negocio/pedidos');
    expect(find.byKey(Key('kitchen-${o.id}')), findsOneWidget);
    await tapVisible(tester, find.byKey(Key('accept-order-${o.id}')));
    expect(o.status, OrderStatus.preparing);
    await tapVisible(tester, find.byKey(Key('ready-order-${o.id}')));
    expect(o.status, OrderStatus.ready);
    expect(find.text('⏳ Esperando repartidor'), findsWidgets);
  });

  testWidgets('el restaurante rechaza con motivo', (tester) async {
    final s = makeServices();
    final o = seedOrder(s);
    s.session.login(kDemoRestaurantEmail, kDemoPassword);
    await pumpBiffy(tester, services: s, initialLocation: '/negocio/pedidos');
    await tapVisible(tester, find.byKey(Key('reject-order-${o.id}')));
    await tester.tap(find.byKey(const Key('reason-Cocina saturada')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-reject')));
    await tester.pumpAndSettle();
    expect(o.status, OrderStatus.cancelled);
    expect(o.rejectReason, 'Cocina saturada');
  });

  testWidgets('el repartidor acepta el pedido disponible', (tester) async {
    final s = makeServices();
    final o = seedOrder(s, until: OrderStatus.ready);
    s.session.login(kDemoCourierEmail, kDemoPassword);
    await pumpBiffy(tester, services: s, initialLocation: '/repartidor');
    expect(find.text('Estás desconectado'), findsOneWidget);
    await tester.tap(find.byKey(const Key('courier-online')));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(Key('accept-${o.id}')));
    expect(o.courierId, 'u-andres');
    expect(find.text('Recoger ${o.id}'), findsOneWidget);
  });

  testWidgets('la recogida exige los tres checks', (tester) async {
    final s = makeServices();
    final o = seedOrder(s, until: OrderStatus.ready);
    s.orders.courierAccept(o.id, s.session.auth.byId('u-andres')!);
    s.session.login(kDemoCourierEmail, kDemoPassword);
    await pumpBiffy(
      tester,
      services: s,
      initialLocation: '/repartidor/recogida/${o.id}',
    );
    FilledButton button() => tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const Key('confirm-pickup')),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button().onPressed, isNull);
    await tapVisible(tester, find.byKey(const Key('check-0')));
    await tapVisible(tester, find.byKey(const Key('check-1')));
    expect(button().onPressed, isNull);
    await tapVisible(tester, find.byKey(const Key('check-2')));
    expect(button().onPressed, isNotNull);
    await tapVisible(tester, find.byKey(const Key('confirm-pickup')));
    expect(o.status, OrderStatus.onTheWay);
    expect(find.text('Entregar ${o.id}'), findsOneWidget);
  });

  testWidgets('la entrega rechaza código incorrecto y exige evidencia', (
    tester,
  ) async {
    final s = makeServices();
    final o = seedOrder(s, until: OrderStatus.ready);
    s.orders.courierAccept(o.id, s.session.auth.byId('u-andres')!);
    s.orders.confirmPickup(
      o.id,
      'u-andres',
      codeValidated: true,
      bagSealed: true,
      productsVerified: true,
    );
    s.session.login(kDemoCourierEmail, kDemoPassword);
    await pumpBiffy(
      tester,
      services: s,
      initialLocation: '/repartidor/entrega/${o.id}',
    );

    final wrong = o.deliveryCode == '1234' ? '4321' : '1234';
    await tester.enterText(find.byKey(const Key('delivery-code-input')), wrong);
    await tapVisible(tester, find.byKey(const Key('demo-evidence')));
    await tapVisible(tester, find.byKey(const Key('mark-delivered')));
    expect(find.text('Código incorrecto'), findsOneWidget);
    expect(o.status, OrderStatus.onTheWay);

    // Código correcto pero sin evidencia (se reinicia la pantalla).
    await goTo(tester, '/repartidor');
    await goTo(tester, '/repartidor/entrega/${o.id}');
    await tester.enterText(
      find.byKey(const Key('delivery-code-input')),
      o.deliveryCode,
    );
    await tapVisible(tester, find.byKey(const Key('mark-delivered')));
    expect(
      find.text('Agrega una foto de evidencia para finalizar'),
      findsOneWidget,
    );
    expect(o.status, OrderStatus.onTheWay);

    await tapVisible(tester, find.byKey(const Key('demo-evidence')));
    await tapVisible(tester, find.byKey(const Key('mark-delivered')));
    expect(o.status, OrderStatus.delivered);
    expect(find.byKey(const Key('courier-online')), findsOneWidget);
  });

  testWidgets('el pedido entregado aparece en el historial', (tester) async {
    final s = makeServices();
    final o = seedOrder(s, until: OrderStatus.ready);
    s.orders.courierAccept(o.id, s.session.auth.byId('u-andres')!);
    s.orders.confirmPickup(
      o.id,
      'u-andres',
      codeValidated: true,
      bagSealed: true,
      productsVerified: true,
    );
    s.orders.completeDelivery(o.id, 'u-andres', o.deliveryCode, 'foto');
    s.session.login(kDemoBuyerEmail, kDemoPassword);
    await pumpBiffy(tester, services: s, initialLocation: '/pedidos');
    await tapVisible(tester, find.textContaining('Anteriores'));
    expect(find.byKey(Key('order-${o.id}')), findsOneWidget);
  });

  testWidgets('el restaurante crea un producto visible para el comprador', (
    tester,
  ) async {
    final s = makeServices();
    s.session.login(kDemoRestaurantEmail, kDemoPassword);
    await pumpBiffy(
      tester,
      services: s,
      initialLocation: '/negocio/producto/nuevo',
    );
    await tester.enterText(
      find.byKey(const Key('p-name')),
      'Sándwich Cubano Demo',
    );
    await tester.enterText(
      find.byKey(const Key('p-desc')),
      'Producto creado en la prueba.',
    );
    await tester.enterText(find.byKey(const Key('p-price')), '15000');
    await tapVisible(tester, find.byKey(const Key('p-save')));
    expect(
      s.catalog.reachableDishes.map((d) => d.name),
      contains('Sándwich Cubano Demo'),
    );
  });
}
