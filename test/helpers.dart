import 'dart:math' as math;

import 'package:biffy/app/app.dart';
import 'package:biffy/app/di/bootstrap.dart';
import 'package:biffy/app/di/injection.dart';
import 'package:biffy/data/repositories/in_memory_order_repository.dart';
import 'package:biffy/data/repositories/in_memory_payment_repository.dart';
import 'package:biffy/domain/repositories/rewards_repository.dart';
import 'package:biffy/domain/usecases/rate_order.dart';
import 'package:biffy/features/orders/bloc/orders_bloc.dart';
import 'package:biffy/features/buyer/cart/bloc/cart_cubit.dart';
import 'package:biffy/shared/state/catalog_controller.dart';
import 'package:biffy/shared/state/notification_center.dart';
import 'package:biffy/shared/state/session_controller.dart';
import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/data/models/cart.dart';
import 'package:biffy/data/models/catalog.dart';
import 'package:biffy/data/models/order.dart';
import 'package:biffy/domain/repositories/order_repository.dart';
import 'package:biffy/domain/repositories/payment_repository.dart';
import 'package:biffy/domain/usecases/orders/checkout_draft.dart';
import 'package:biffy/core/utils/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Martes 20 de octubre de 2026, 12:00: todos los restaurantes semilla abiertos.
final kTestNow = DateTime(2026, 10, 20, 12, 0);

/// Atajos a lo que las pruebas piden al contenedor (GetIt).
class TestServices {
  const TestServices();

  Clock get clock => getIt<Clock>();
  SessionController get session => getIt<SessionController>();
  CatalogController get catalog => getIt<CatalogController>();
  CartCubit get cart => getIt<CartCubit>();
  PaymentRepository get payment => getIt<PaymentRepository>();
  NotificationCenter get notifications => getIt<NotificationCenter>();
  OrdersBloc get orders => getIt<OrdersBloc>();
  RateOrder get rateOrder => getIt<RateOrder>();
}

/// Reinicia GetIt en modo demo (sin Supabase) con reloj fijo y datos de
/// ejemplo. [rewards] sustituye el repositorio de recompensas por un doble.
Future<TestServices> makeServices({
  Clock? clock,
  int? randomSeed = 7,
  bool seed = true,
  RewardsRepository? rewards,
}) async {
  await getIt.reset();
  getIt.allowReassignment = true;
  // Se libera en el mismo test que lo creó (en otro, el Bloc ya no tiene zona).
  addTearDown(getIt.reset);
  await configureDependencies();
  final c = clock ?? Clock.fixed(kTestNow);
  getIt.registerSingleton<Clock>(c);
  getIt.registerLazySingleton<OrderRepository>(
    () => InMemoryOrderRepository(
      c,
      random: randomSeed == null ? null : math.Random(randomSeed),
    ),
  );
  if (rewards != null) getIt.registerSingleton<RewardsRepository>(rewards);
  // En pruebas el pago simulado se resuelve rápido (sin esperar 2 s).
  getIt.registerLazySingleton<PaymentRepository>(
    () => InMemoryPaymentRepository(
      autoApproveAfter: const Duration(milliseconds: 10),
    ),
  );
  bootstrapDemo(seedData: seed);
  return const TestServices();
}

/// Monta la app con un tamaño de teléfono (400 × 860 dp).
Future<TestServices> pumpBiffy(
  WidgetTester tester, {
  TestServices? services,
  String initialLocation = '/',
  bool settle = true,
  bool phoneSize = true,
}) async {
  final s = services ?? await makeServices();
  if (phoneSize) {
    tester.view.physicalSize = const Size(1200, 2580);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(BiffyApp(initialLocation: initialLocation));
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
Future<Order> placeQbano(
  TestServices s, {
  int qty = 1,
  bool useGotas = false,
}) async {
  s.session.login(kDemoBuyerEmail, kDemoPassword);
  final result = await s.orders.useCases.placeOrder(
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
  if (!result.ok) throw StateError('No se pudo crear el pedido: ${result.message}');
  return result.order!;
}

/// Espera a que se oculten los SnackBar flotantes (duran 2 s).
Future<void> waitSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

/// Lleva un pedido de Diego hasta «entregado» con los casos de uso reales.
Future<Order> deliverQbano(TestServices s) async {
  final o = await placeQbano(s);
  final uc = s.orders.useCases;
  final andres = s.session.auth.byId('u-andres')!;
  for (final step in <Future<OrderResult> Function()>[
    () => uc.acceptOrder(o.id),
    () => uc.markOrderReady(o.id),
    () => uc.acceptOffer(o.id, andres),
    () => uc.confirmPickup(
      o.id,
      'u-andres',
      codeValidated: true,
      bagSealed: true,
      productsVerified: true,
    ),
    () => uc.completeDelivery(o.id, 'u-andres', o.deliveryCode, 'foto'),
  ]) {
    final res = await step();
    if (!res.ok) throw StateError('Paso del pedido falló: ${res.code}');
  }
  expect(o.status, OrderStatus.delivered);
  return o;
}
