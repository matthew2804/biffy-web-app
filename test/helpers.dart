import 'package:biffy/app/app.dart';
import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/data/models/cart.dart';
import 'package:biffy/data/models/catalog.dart';
import 'package:biffy/data/models/order.dart';
import 'package:biffy/shared/state/order_service.dart';
import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Martes 20 de octubre de 2026, 12:00: todos los restaurantes semilla abiertos.
final kTestNow = DateTime(2026, 10, 20, 12, 0);

AppServices makeServices() =>
    AppServices.demo(clock: Clock.fixed(kTestNow), randomSeed: 7);

/// Monta la app con un tamaño de teléfono (400 × 860 dp).
Future<AppServices> pumpBiffy(
  WidgetTester tester, {
  AppServices? services,
  String initialLocation = '/',
  bool settle = true,
  bool phoneSize = true,
}) async {
  final s = services ?? makeServices();
  if (phoneSize) {
    tester.view.physicalSize = const Size(1200, 2580);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(
    BiffyApp(services: s, initialLocation: initialLocation),
  );
  if (settle) await tester.pumpAndSettle();
  return s;
}

/// Navega usando el router real de la app.
Future<void> goTo(WidgetTester tester, String location) async {
  final ctx = tester.element(find.byType(Navigator).first);
  GoRouter.of(ctx).go(location);
  await tester.pumpAndSettle();
}

/// Desplaza la vista principal hasta que [finder] exista (listas perezosas).
Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  Finder? scrollable,
}) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: scrollable ?? find.byType(Scrollable).first,
      maxScrolls: 80,
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Diego (demo) pide un Qbano Especial con extra queso, pago en efectivo.
Order placeQbano(AppServices s, {int qty = 1, bool useGotas = false}) {
  s.session.login(kDemoBuyerEmail, kDemoPassword);
  return s.orders.placeOrder(
    CheckoutDraft(
      buyer: s.session.user,
      restaurant: s.catalog.restaurantById('qbano-icesi'),
      items: [
        CartItem(
          lineId: 'l1',
          dishId: 'qbano-especial',
          qty: qty,
          selection: const DishSelection(
            sizeId: 'qe-30',
            extraIds: {'qe-queso'},
          ),
        ),
      ],
      address: s.session.data.defaultAddress,
      payment: PaymentMethod.cash,
      useGotas: useGotas,
      tip: TipOption.ten,
    ),
  );
}

/// Espera a que se oculten los SnackBar flotantes (duran 2 s).
Future<void> waitSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}
