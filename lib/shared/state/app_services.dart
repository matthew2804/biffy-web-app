import 'dart:math' as math;

import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/utils/clock.dart';
import '../../data/mock/seed_state.dart';
import '../../data/mock/seed_users.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../data/repositories/supabase_catalog_repository.dart';
import '../../data/repositories/supabase_order_repository.dart';
import '../../data/repositories/supabase_profile_repository.dart';
import 'cart_controller.dart';
import 'catalog_controller.dart';
import 'notification_center.dart';
import 'order_service.dart';
import 'session_controller.dart';

/// Contenedor de dependencias. Para conectar Firebase en el futuro basta con
/// sustituir los repositorios en memoria por implementaciones remotas.
class AppServices {
  /// Constructor privado: las instancias se crean con las factorías.
  AppServices._({
    required this.clock,
    required this.notifications,
    required this.session,
    required this.catalog,
    required this.cart,
    required this.orders,
  });

  /// Contenedor completo con datos de demostración en memoria.
  factory AppServices.demo({Clock? clock, int? randomSeed, bool seed = true}) {
    final c = clock ?? Clock();
    final catalogRepo = InMemoryCatalogRepository();
    final auth = InMemoryAuthRepository(seedUsers(catalogRepo.businesses));
    final notifications = NotificationCenter(c);
    final session = SessionController(auth, notifications, c);
    final catalog = CatalogController(catalogRepo, session, c);
    final cart = CartController(catalogRepo);
    final orders = OrderService(
      repo: InMemoryOrderRepository(),
      catalog: catalog,
      session: session,
      notifications: notifications,
      clock: c,
      random: randomSeed == null ? null : math.Random(randomSeed),
    );
    if (seed) applyDemoSeed(session, orders);
    notifications.push(
      title: 'Bienvenido a Biffy 🐝',
      body:
          'Explora sin registrarte. Todo es una demostración sin cobros reales.',
      audience: 'all',
    );
    return AppServices._(
      clock: c,
      notifications: notifications,
      session: session,
      catalog: catalog,
      cart: cart,
      orders: orders,
    );
  }

  /// Contenedor con autenticación y catálogo reales (Supabase).
  ///
  /// Fase 2b: catálogo remoto con caché hidratada + Realtime. Los pedidos y
  /// las escrituras de comercio siguen en memoria hasta la fase 2c/2d.
  static Future<AppServices> supabase({
    Clock? clock,
    AuthRepository? auth,
    CatalogRepository? catalogRepo,
    OrderRepository? orderRepo,
  }) async {
    final c = clock ?? Clock();
    final remoteAuth = auth ?? SupabaseAuthRepository();
    final repo = catalogRepo ?? await SupabaseCatalogRepository.load();
    final orderStore = orderRepo ?? await SupabaseOrderRepository.load();
    final notifications = NotificationCenter(c);
    final session = SessionController(
      remoteAuth,
      notifications,
      c,
      profile: SupabaseProfileRepository(),
    );
    final catalog = CatalogController(repo, session, c);
    final cart = CartController(repo);
    final orders = OrderService(
      repo: orderStore,
      catalog: catalog,
      session: session,
      notifications: notifications,
      clock: c,
    );
    return AppServices._(
      clock: c,
      notifications: notifications,
      session: session,
      catalog: catalog,
      cart: cart,
      orders: orders,
    );
  }

  final Clock clock;
  final NotificationCenter notifications;
  final SessionController session;
  final CatalogController catalog;
  final CartController cart;
  final OrderService orders;

  /// Proveedores que publican los controladores en el árbol.
  List<SingleChildWidget> get providers => [
    Provider<Clock>.value(value: clock),
    ChangeNotifierProvider<NotificationCenter>.value(value: notifications),
    ChangeNotifierProvider<SessionController>.value(value: session),
    ChangeNotifierProvider<CatalogController>.value(value: catalog),
    ChangeNotifierProvider<CartController>.value(value: cart),
    ChangeNotifierProvider<OrderService>.value(value: orders),
  ];
}
