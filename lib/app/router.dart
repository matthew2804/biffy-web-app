import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/navigation/shells.dart';
import '../core/widgets/ui.dart';
import '../data/models/user.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/register_screen.dart';
import '../features/buyer/addresses/addresses_screen.dart';
import '../features/buyer/ai/ai_screen.dart';
import '../features/buyer/campus/campus_screen.dart';
import '../features/buyer/cart/cart_screen.dart';
import '../features/buyer/cart/checkout_screen.dart';
import '../features/buyer/explore/explore_screen.dart';
import '../features/buyer/favorites/favorites_screen.dart';
import '../features/buyer/home/home_screen.dart';
import '../features/buyer/notifications/notifications_screen.dart';
import '../features/buyer/orders/frequent_orders_screen.dart';
import '../features/buyer/orders/orders_screen.dart';
import '../features/buyer/payments/payments_screen.dart';
import '../features/buyer/preferences/preferences_screen.dart';
import '../features/buyer/product/dish_screen.dart';
import '../features/buyer/profile/personal_info_screen.dart';
import '../features/buyer/profile/profile_screen.dart';
import '../features/buyer/restaurant/restaurant_screen.dart';
import '../features/buyer/rewards/rewards_screen.dart';
import '../features/buyer/settings/settings_screen.dart';
import '../features/buyer/support/support_screen.dart';
import '../features/buyer/tracking/tracking_screen.dart';
import '../features/courier/delivery/delivery_screen.dart';
import '../features/courier/earnings/earnings_screen.dart';
import '../features/courier/home/courier_home_screen.dart';
import '../features/courier/offers/offer_detail_screen.dart';
import '../features/courier/pickup/pickup_screen.dart';
import '../features/courier/profile/courier_profile_screen.dart';
import '../features/courier/registration/courier_registration_screen.dart';
import '../features/onboarding/splash_screen.dart';
import '../features/restaurant_owner/home/merchant_home_screen.dart';
import '../features/restaurant_owner/menu/merchant_menu_screen.dart';
import '../features/restaurant_owner/orders/merchant_orders_screen.dart';
import '../features/restaurant_owner/products/product_form_screen.dart';
import '../features/restaurant_owner/profile/merchant_profile_screen.dart';
import '../features/restaurant_owner/registration/merchant_registration_screen.dart';
import '../features/restaurant_owner/statistics/merchant_stats_screen.dart';
import '../shared/state/session_controller.dart';

/// Rutas del comprador que requieren cuenta (explorar nunca la requiere).
const kBuyerProtected = [
  '/checkout',
  '/pedido',
  '/pedidos',
  '/frecuentes',
  '/recompensas',
  '/favoritos',
  '/direcciones',
  '/pagos',
  '/perfil/datos',
];

/// Reglas de acceso por rol. Conserva la ruta de origen en `from`.
String? appRedirect(SessionController s, String location, String fullUri) {
  String login() => '/login?from=${Uri.encodeComponent(fullUri)}';
  if (location.startsWith('/repartidor')) {
    if (!s.isLoggedIn) return login();
    if (location != '/repartidor/registro' && !s.hasCourierProfile) {
      return '/repartidor/registro';
    }
    return null;
  }
  if (location.startsWith('/negocio')) {
    if (location == '/negocio/registro') return null;
    if (!s.isLoggedIn || s.businessId == null) return login();
    return null;
  }
  final protected = kBuyerProtected.any(
    (p) => location == p || location.startsWith('$p/'),
  );
  if (protected && !s.isLoggedIn) return login();
  return null;
}

/// Marca el rol activo según la sección visible (afecta notificaciones).
class RoleScope extends StatefulWidget {
  const RoleScope({super.key, required this.role, required this.child});
  final UserRole role;
  final Widget child;

  @override
  State<RoleScope> createState() => _RoleScopeState();
}

class _RoleScopeState extends State<RoleScope> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<SessionController>();
      if (s.activeRole != widget.role) s.setActiveRole(widget.role);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Si la sesión dejó de cumplir los requisitos del rol (p. ej. al cambiar
    // de cuenta), no se construyen sus pantallas mientras el router redirige.
    final s = context.watch<SessionController>();
    final allowed = switch (widget.role) {
      UserRole.buyer => true,
      UserRole.courier => s.isLoggedIn && s.hasCourierProfile,
      UserRole.restaurant => s.isLoggedIn && s.businessId != null,
    };
    return allowed ? widget.child : const Scaffold(body: SizedBox.shrink());
  }
}

GoRoute _r(String path, Widget Function(GoRouterState s) build) =>
    GoRoute(path: path, builder: (_, s) => build(s));

GoRouter buildRouter(
  SessionController session, {
  String initialLocation = '/splash',
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: session,
    redirect: (_, state) =>
        appRedirect(session, state.matchedLocation, state.uri.toString()),
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: EmptyState(
        emoji: '🧭',
        title: 'Página no encontrada',
        actionLabel: 'Ir al inicio',
        onAction: () => context.go('/'),
      ),
    ),
    routes: [
      _r('/splash', (_) => const SplashScreen()),
      _r('/login', (s) => LoginScreen(from: s.uri.queryParameters['from'])),
      _r(
        '/registro',
        (s) => RegisterScreen(from: s.uri.queryParameters['from']),
      ),

      // Comprador · pantallas sin navegación inferior.
      _r(
        '/restaurante/:id',
        (s) => RestaurantScreen(id: s.pathParameters['id']!),
      ),
      _r(
        '/plato/:id',
        (s) => DishScreen(
          id: s.pathParameters['id']!,
          editLineId: s.uri.queryParameters['edit'],
        ),
      ),
      _r('/carrito', (_) => const CartScreen()),
      _r('/checkout', (_) => const CheckoutScreen()),
      _r('/pedido/:id', (s) => TrackingScreen(id: s.pathParameters['id']!)),
      _r('/pedidos', (_) => const OrdersScreen()),
      _r('/frecuentes', (_) => const FrequentOrdersScreen()),
      _r('/preferencias', (_) => const PreferencesScreen()),
      _r('/recompensas', (_) => const RewardsScreen()),
      _r('/favoritos', (_) => const FavoritesScreen()),
      _r('/notificaciones', (_) => const NotificationsScreen()),
      _r('/ajustes', (_) => const SettingsScreen()),
      _r('/soporte', (_) => const SupportScreen()),
      _r('/pagos', (_) => const PaymentsScreen()),
      _r('/direcciones', (_) => const AddressesScreen()),
      _r('/direcciones/nueva', (_) => const AddressFormScreen()),
      _r(
        '/direcciones/:id',
        (s) => AddressFormScreen(id: s.pathParameters['id']),
      ),
      _r('/campus', (_) => const CampusScreen()),
      _r('/perfil/datos', (_) => const PersonalInfoScreen()),

      // Repartidor · flujo guiado.
      _r('/repartidor/registro', (_) => const CourierRegistrationScreen()),
      _r(
        '/repartidor/oferta/:id',
        (s) => OfferDetailScreen(id: s.pathParameters['id']!),
      ),
      _r(
        '/repartidor/recogida/:id',
        (s) => PickupScreen(id: s.pathParameters['id']!),
      ),
      _r(
        '/repartidor/entrega/:id',
        (s) => DeliveryScreen(id: s.pathParameters['id']!),
      ),

      // Restaurante · formularios.
      _r('/negocio/registro', (_) => const MerchantRegistrationScreen()),
      _r(
        '/negocio/producto/:id',
        (s) => ProductFormScreen(id: s.pathParameters['id']!),
      ),

      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RoleScope(
          role: UserRole.buyer,
          child: RoleShell(shell: shell, items: kBuyerNav, showCartBar: true),
        ),
        branches: [
          StatefulShellBranch(routes: [_r('/', (_) => const HomeScreen())]),
          StatefulShellBranch(
            routes: [
              _r(
                '/explorar',
                (s) => ExploreScreen(
                  category: s.uri.queryParameters['cat'],
                  focus: s.uri.queryParameters['focus'] == '1',
                  restaurantsView:
                      s.uri.queryParameters['view'] == 'restaurantes',
                ),
              ),
            ],
          ),
          StatefulShellBranch(routes: [_r('/ai', (_) => const AiScreen())]),
          StatefulShellBranch(
            routes: [_r('/perfil', (_) => const ProfileScreen())],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RoleScope(
          role: UserRole.courier,
          child: RoleShell(shell: shell, items: kCourierNav),
        ),
        branches: [
          StatefulShellBranch(
            routes: [_r('/repartidor', (_) => const CourierHomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              _r('/repartidor/ganancias', (_) => const EarningsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _r('/repartidor/perfil', (_) => const CourierProfileScreen()),
            ],
          ),
        ],
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => RoleScope(
          role: UserRole.restaurant,
          child: RoleShell(shell: shell, items: kRestaurantNav),
        ),
        branches: [
          StatefulShellBranch(
            routes: [_r('/negocio', (_) => const MerchantHomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              _r(
                '/negocio/pedidos',
                (s) => MerchantOrdersScreen(filter: s.uri.queryParameters['f']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [_r('/negocio/menu', (_) => const MerchantMenuScreen())],
          ),
          StatefulShellBranch(
            routes: [
              _r('/negocio/estadisticas', (_) => const MerchantStatsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              _r('/negocio/perfil', (_) => const MerchantProfileScreen()),
            ],
          ),
        ],
      ),
    ],
  );
}
