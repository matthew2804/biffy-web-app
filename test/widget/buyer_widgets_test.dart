import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:biffy/core/utils/format.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('el splash conduce a Inicio', (tester) async {
    await pumpBiffy(tester, initialLocation: '/splash', settle: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('BIFFY'), findsOneWidget);
    expect(find.text('Comida que llega volando'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('BIFFY'), findsNothing);
    expect(find.text('¿Qué se te antoja hoy? 🐝'), findsOneWidget);
  });

  testWidgets('se puede explorar sin iniciar sesión', (tester) async {
    final s = await pumpBiffy(tester);
    expect(s.session.isLoggedIn, isFalse);
    await tester.tap(find.text('Explorar').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('explore-search')), 'qbano');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('results-count')), findsOneWidget);
    await tapVisible(tester, find.text('Qbano Especial'));
    expect(find.textContaining('Agregar ·'), findsOneWidget);
    await scrollTo(tester, find.text('Ingredientes'));
    expect(find.text('Ingredientes'), findsOneWidget);
    expect(s.session.isLoggedIn, isFalse);
  });

  testWidgets('los filtros actualizan los resultados', (tester) async {
    await pumpBiffy(tester, initialLocation: '/explorar');
    await tester.tap(find.byKey(const Key('explore-cat-pizza')));
    await tester.pumpAndSettle();
    expect(find.text('3 resultados'), findsOneWidget);
    final cheap = find.text('💸 < ${cop(15000)}');
    await scrollTo(
      tester,
      cheap,
      scrollable: find
          .ancestor(
            of: find.text('🎓 Campus'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(cheap);
    await tester.pumpAndSettle();
    expect(find.text('0 resultados'), findsOneWidget);
    expect(find.text('No encontramos coincidencias'), findsOneWidget);
    await tester.tap(find.text('Limpiar filtros').first);
    await tester.pumpAndSettle();
    // Limpia todos los filtros (incluida la categoría): vuelve a la vista general.
    expect(find.text('Populares'), findsOneWidget);
  });

  testWidgets('el panel de filtros cuenta coincidencias y aplica precio', (
    tester,
  ) async {
    await pumpBiffy(tester, initialLocation: '/explorar?cat=pizza');
    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Ver 3 resultados'), findsOneWidget);
    final slider = find.byKey(const Key('price-slider'));
    await tester.drag(slider, const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Ver 0 resultados'), findsOneWidget);
    await tester.tap(find.byKey(const Key('filters-apply')));
    await tester.pumpAndSettle();
    expect(find.text('0 resultados'), findsOneWidget);
  });

  testWidgets('un producto se agrega al carrito y aparece la barra', (
    tester,
  ) async {
    final s = await pumpBiffy(tester, initialLocation: '/plato/qbano-pollo');
    await tapVisible(tester, find.text('15 cm'));
    await tester.tap(find.byKey(const Key('add-to-cart')));
    await tester.pumpAndSettle();
    expect(s.cart.count, 1);
    expect(s.cart.subtotal, 21900 - 7000);
    await goTo(tester, '/');
    expect(find.byKey(const Key('cart-bar')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cart-bar')));
    await tester.pumpAndSettle();
    expect(find.text('Tu carrito'), findsOneWidget);
    expect(find.text('Sándwich de Pollo'), findsOneWidget);
  });

  testWidgets('las personalizaciones modifican el precio', (tester) async {
    await pumpBiffy(tester, initialLocation: '/plato/qbano-especial');
    expect(find.text('Agregar · ${cop(24900)}'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('extra-qe-queso')));
    expect(find.text('Agregar · ${cop(27900)}'), findsOneWidget);
    await tapVisible(tester, find.text('Papas a la francesa'));
    expect(find.text('Agregar · ${cop(32400)}'), findsOneWidget);
    await tapVisible(tester, find.bySemanticsLabel('Aumentar cantidad'));
    expect(find.text('Agregar · ${cop(64800)}'), findsOneWidget);
  });

  testWidgets('editar una línea del carrito y cancelar no la pierde', (
    tester,
  ) async {
    final s = await pumpBiffy(tester);
    s.cart.add(s.catalog.dishById('qbano-especial')!);
    await goTo(tester, '/carrito');
    final line = s.cart.items.first.lineId;
    await tapVisible(tester, find.byKey(Key('edit-$line')));
    await tapVisible(tester, find.byKey(const Key('extra-qe-queso')));
    await tapVisible(tester, find.text('Cancelar edición'));
    expect(s.cart.items, hasLength(1));
    expect(s.cart.items.first.selection.extraIds, isEmpty);
  });

  testWidgets('el checkout muestra un resumen correcto y crea el pedido', (
    tester,
  ) async {
    final s = await pumpBiffy(tester);
    s.session.login(kDemoBuyerEmail, kDemoPassword);
    s.cart.add(s.catalog.dishById('qbano-especial')!, qty: 2);
    await goTo(tester, '/checkout');
    final before = s.orders.forBuyer('u-diego').length;
    // 2 × 24.900 = 49.800 − 10% campus (4.980) + 1.500 de entrega = 46.320
    expect(find.text(cop(49800)), findsWidgets);
    expect(find.text('-${cop(4980)}'), findsOneWidget);
    expect(find.text(cop(46320)), findsOneWidget);
    expect(
      find.text(
        'Pedido de demostración · sin cobros reales',
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.textContaining('Pedido de demostración · sin cobros reales'),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('confirm-order')));
    expect(s.orders.forBuyer('u-diego').length, before + 1);
    expect(s.cart.isEmpty, isTrue);
    final id = s.orders.forBuyer('u-diego').first.id;
    expect(find.text('Pedido $id'), findsOneWidget);
    expect(find.byKey(const Key('delivery-code')), findsOneWidget);
  });

  testWidgets('la navegación inferior conserva el estado de las pestañas', (
    tester,
  ) async {
    await pumpBiffy(tester);
    await tester.tap(find.text('Explorar').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('explore-search')), 'café');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inicio').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar').last);
    await tester.pumpAndSettle();
    expect(find.text('café'), findsOneWidget);
  });

  testWidgets('cambiar el punto de entrega actualiza los restaurantes', (
    tester,
  ) async {
    final s = await pumpBiffy(tester);
    await tester.tap(find.byKey(const Key('location-selector')));
    await tester.pumpAndSettle();
    await scrollTo(
      tester,
      find.text('Casa · Suba'),
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Casa · Suba'));
    await tester.pumpAndSettle();
    expect(s.session.pointId, 'suba');
    expect(s.catalog.reachableRestaurants.map((r) => r.id), ['pizzeria-norte']);
    expect(find.textContaining('Entregando en Casa · Suba'), findsOneWidget);
  });

  testWidgets(
    'el perfil muestra las Gotas actualizadas tras las preferencias',
    (tester) async {
      final s = await pumpBiffy(tester);
      s.session.login(kDemoNewBuyerEmail, kDemoPassword);
      await goTo(tester, '/perfil');
      expect(find.text('$kWelcomeGotas'), findsOneWidget);
      await goTo(tester, '/preferencias');
      await tester.tap(find.byKey(const Key('like-pizza')));
      await tester.tap(find.byKey(const Key('prefs-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('allergy-maní')));
      await tester.tap(find.byKey(const Key('prefs-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('prefs-next')));
      await tester.pumpAndSettle();
      expect(s.session.gotas, kWelcomeGotas + kSurveyGotas);
      await goTo(tester, '/perfil');
      expect(find.text('${kWelcomeGotas + kSurveyGotas}'), findsOneWidget);
      // Repetir la encuesta no duplica la recompensa.
      await goTo(tester, '/preferencias');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byKey(const Key('prefs-next')));
        await tester.pumpAndSettle();
      }
      expect(s.session.gotas, kWelcomeGotas + kSurveyGotas);
    },
  );

  testWidgets('favoritos sin sesión piden iniciar sesión', (tester) async {
    final s = await pumpBiffy(tester, initialLocation: '/plato/capuchino');
    await tester.tap(find.byKey(const Key('fav-dish')));
    await tester.pumpAndSettle();
    expect(find.text('Inicia sesión para guardar favoritos'), findsOneWidget);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(s.session.data.favoriteDishes, isEmpty);
  });

  testWidgets('de noche se ofrece el horario de demostración', (tester) async {
    final s = AppServices.demo(
      clock: Clock.fixed(DateTime(2026, 10, 20, 23, 30)),
    );
    await pumpBiffy(tester, services: s);
    expect(find.byKey(const Key('closed-banner')), findsOneWidget);
    await tapVisible(tester, find.text('Activar horario de demostración'));
    expect(s.session.settings.demoLunch, isTrue);
    expect(find.byKey(const Key('closed-banner')), findsNothing);
    expect(s.catalog.isOpen(s.catalog.restaurantById('qbano-icesi')!), isTrue);
  });
}
