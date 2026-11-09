import 'dart:math' as math;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../../core/utils/clock.dart';
import '../../data/mock/seed_state.dart';
import '../../data/mock/seed_users.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/in_memory_order_repository.dart';
import '../../data/repositories/supabase_auth_repository.dart';
import '../../data/repositories/supabase_catalog_repository.dart';
import '../../data/repositories/supabase_order_repository.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/usecases/orders/order_usecases.dart';
import '../../features/orders/bloc/orders_bloc.dart';
import '../adapters/order_adapters.dart';
import 'cart_controller.dart';
import 'catalog_controller.dart';
import 'notification_center.dart';
import 'session_controller.dart';

/// Contenedor de dependencias (raíz de composición).
///
/// Aquí, y solo aquí, se decide qué implementación concreta recibe cada capa:
/// repositorios en memoria (demo) o Supabase (real). Los casos de uso y el
/// `OrdersBloc` solo conocen las interfaces del dominio.
class AppServices {
  AppServices._({
    required this.clock,
    required this.notifications,
    required this.session,
    required this.catalog,
    required this.cart,
    required this.orders,
  });

  factory AppServices.demo({Clock? clock, int? randomSeed, bool seed = true}) {
    final c = clock ?? Clock();
    final catalogRepo = InMemoryCatalogRepository();
    final auth = InMemoryAuthRepository(seedUsers(catalogRepo.businesses));
    final notifications = NotificationCenter(c);
    final session = SessionController(auth, notifications, c);
    final catalog = CatalogController(catalogRepo, session, c);
    final cart = CartController(catalogRepo);
    final orderRepo = InMemoryOrderRepository(
      c,
      random: randomSeed == null ? null : math.Random(randomSeed),
    );
    final orders = _buildOrders(
      repo: orderRepo,
      catalog: catalog,
      session: session,
      notifications: notifications,
      clock: c,
      demo: true,
    );
    if (seed) applyDemoSeed(session, orderRepo, catalog, c);
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

  /// Contenedor con autenticación, catálogo y pedidos reales (Supabase).
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
    final session = SessionController(remoteAuth, notifications, c);
    final catalog = CatalogController(repo, session, c);
    final cart = CartController(repo);
    final orders = _buildOrders(
      repo: orderStore,
      catalog: catalog,
      session: session,
      notifications: notifications,
      clock: c,
      demo: false,
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

  /// Ensambla repositorio → casos de uso → bloc.
  static OrdersBloc _buildOrders({
    required OrderRepository repo,
    required CatalogController catalog,
    required SessionController session,
    required NotificationCenter notifications,
    required Clock clock,
    required bool demo,
  }) {
    final sessionAdapter = SessionOrderAdapter(session);
    return OrdersBloc(
      OrderUseCases(
        repo: repo,
        catalog: CatalogOrderAdapter(catalog),
        buyers: sessionAdapter,
        wallet: sessionAdapter,
        notifier: NotificationOrderAdapter(notifications, demo: demo),
        clock: clock,
      ),
    );
  }

  final Clock clock;
  final NotificationCenter notifications;
  final SessionController session;
  final CatalogController catalog;
  final CartController cart;
  final OrdersBloc orders;

  List<SingleChildWidget> get providers => [
    Provider<Clock>.value(value: clock),
    ChangeNotifierProvider<NotificationCenter>.value(value: notifications),
    ChangeNotifierProvider<SessionController>.value(value: session),
    ChangeNotifierProvider<CatalogController>.value(value: catalog),
    ChangeNotifierProvider<CartController>.value(value: cart),
    BlocProvider<OrdersBloc>.value(value: orders),
  ];
}
