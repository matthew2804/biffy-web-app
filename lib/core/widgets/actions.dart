import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../data/models/cart.dart';
import '../../data/models/catalog.dart';
import '../../data/models/user.dart';
import '../../shared/state/cart_controller.dart';
import '../../shared/state/catalog_controller.dart';
import '../../shared/state/session_controller.dart';
import '../constants/catalog_constants.dart';
import '../utils/format.dart';
import 'ui.dart';

/// Pide iniciar sesión para una acción restringida y, si el usuario lo hace,
/// devuelve `true` para continuar el flujo original.
Future<bool> requireLogin(
  BuildContext context, {
  required String reason,
}) async {
  final session = context.read<SessionController>();
  if (session.isLoggedIn) return true;
  final go = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BeeLogo(size: 56),
            const SizedBox(height: 8),
            Text(
              'Inicia sesión para $reason',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              'Puedes seguir explorando sin cuenta. Después de iniciar sesión volverás a donde estabas.',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Iniciar sesión',
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            SecondaryButton(
              label: 'Ahora no',
              onPressed: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    ),
  );
  if (go != true || !context.mounted) return false;
  await context.push<bool>('/login');
  return session.isLoggedIn;
}

bool needsCustomization(Dish d) =>
    d.sizes.length > 1 || d.sides.isNotEmpty || d.extras.isNotEmpty;

/// Agrega al carrito gestionando restaurante distinto y disponibilidad.
Future<bool> addToCart(
  BuildContext context,
  Dish dish, {
  DishSelection? selection,
  int qty = 1,
  String note = '',
}) async {
  final cart = context.read<CartController>();
  final result = cart.add(dish, selection: selection, qty: qty, note: note);
  switch (result) {
    case AddResult.added:
      showSnack(context, '${dish.name} agregado al carrito');
      return true;
    case AddResult.unavailable:
      showSnack(context, '${dish.name} no está disponible', error: true);
      return false;
    case AddResult.differentRestaurant:
      final current = cart.restaurant?.name ?? 'otro restaurante';
      final ok = await showConfirm(
        context,
        title: '¿Empezar un carrito nuevo?',
        message:
            'Tu carrito tiene productos de $current. Cada pedido es de un solo restaurante. ¿Vaciarlo y agregar ${dish.name}?',
        confirm: 'Vaciar y agregar',
        destructive: true,
      );
      if (!ok || !context.mounted) return false;
      cart.replaceWith(dish, selection: selection, qty: qty, note: note);
      showSnack(context, '${dish.name} agregado al carrito');
      return true;
  }
}

/// Botón «+»: agrega directo o abre el detalle si requiere personalización.
Future<void> quickAdd(BuildContext context, Dish dish) async {
  if (needsCustomization(dish)) {
    context.push('/plato/${dish.id}');
    return;
  }
  await addToCart(context, dish);
}

Future<void> toggleFavoriteDish(BuildContext context, Dish dish) async {
  if (!await requireLogin(context, reason: 'guardar favoritos')) return;
  if (!context.mounted) return;
  final s = context.read<SessionController>();
  s.toggleFavoriteDish(dish.id);
  showSnack(
    context,
    s.data.favoriteDishes.contains(dish.id)
        ? 'Agregado a favoritos ❤️'
        : 'Quitado de favoritos',
  );
}

Future<void> copyShareLink(
  BuildContext context,
  String path,
  String what,
) async {
  final link = 'https://biffy.demo/$path';
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) {
    showSnack(context, 'Enlace de demostración de $what copiado: $link');
  }
}

/// Panel inferior reutilizable para elegir el punto de entrega (sin GPS).
Future<void> showDeliveryPointSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      final session = ctx.watch<SessionController>();
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                '¿Dónde te entregamos?',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Puntos de demostración. No usamos tu GPS.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final p in kDeliveryPoints)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BiffyCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: p.id == session.pointId
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                    onTap: () {
                      session.setPoint(p.id);
                      Navigator.pop(ctx);
                      final n = context
                          .read<CatalogController>()
                          .reachableRestaurants
                          .length;
                      showSnack(
                        context,
                        'Entregando en ${p.name} · $n ${n == 1 ? 'restaurante disponible' : 'restaurantes disponibles'}',
                      );
                    },
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                p.detail,
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (p.campusId != null)
                          Tag('🎓 ${p.campusId!.toUpperCase()}'),
                        if (p.id == session.pointId)
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

String homeForRole(UserRole role) => switch (role) {
  UserRole.buyer => '/',
  UserRole.courier => '/repartidor',
  UserRole.restaurant => '/negocio',
};

/// Selector de cuentas de demostración para recorrer los tres roles.
Future<void> showDemoAccountsSheet(BuildContext context) {
  final session = context.read<SessionController>();
  final accounts = session.auth.demoAccounts;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              'Cuentas de demostración',
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Datos ficticios. Contraseña de todas: $kDemoPassword',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            for (final role in UserRole.values) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 6),
                child: Text(
                  '${role.emoji} ${role.label}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              for (final u in accounts.where((a) => a.role == role))
                ListTile(
                  key: Key('demo-${u.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(u.name),
                  subtitle: Text(u.email),
                  trailing: session.user?.id == u.id
                      ? const Icon(Icons.check_circle, color: AppColors.success)
                      : const Icon(Icons.chevron_right),
                  onTap: () {
                    session.loginAs(u);
                    Navigator.pop(ctx);
                    context.go(homeForRole(u.role));
                    showSnack(context, 'Sesión demo: ${u.name}');
                  },
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

String etaLabel(int minutes) => '$minutes min';

String priceDelta(int p) =>
    p == 0 ? 'Incluido' : (p > 0 ? '+${cop(p)}' : '−${cop(-p)}');
