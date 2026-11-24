import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/mock/seed_users.dart';
import '../../../data/models/order.dart';
import '../../../data/models/user.dart';
import '../../../features/orders/bloc/orders_bloc.dart';
import '../../../shared/state/session_controller.dart';
import '../../../app/di/injection.dart';
import '../../../shared/state/controller_scope.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Perfil del comprador con accesos a cuenta, pedidos y modos de rol.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Construye la cabecera del perfil y el menú de accesos.
  @override
  Widget build(BuildContext context) {
    final session = context.watchController<SessionController>();
    final orders = context.watch<OrdersBloc>();
    final t = Theme.of(context).textTheme;
    final u = session.user;
    final uni = universityById(session.universityId);
    final delivered = u == null
        ? 0
        : orders
              .forBuyer(u.id)
              .where((o) => o.status == OrderStatus.delivered)
              .length;

    Widget item(
      IconData icon,
      String label,
      VoidCallback onTap, {
      Key? key,
      Color? color,
    }) => ListTile(
      key: key,
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.w600, color: color),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Perfil', style: t.headlineSmall),
            const SizedBox(height: 12),
            if (u == null)
              BiffyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BeeLogo(size: 56),
                    Text(
                      'Estás explorando como invitado',
                      style: t.titleMedium,
                    ),
                    Text(
                      'Inicia sesión para pedir, guardar favoritos y acumular Gotas Biffy.',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    PrimaryButton(
                      key: const Key('profile-login'),
                      label: 'Iniciar sesión',
                      onPressed: () => context.push('/login'),
                    ),
                    const SizedBox(height: 8),
                    SecondaryButton(
                      label: 'Crear cuenta',
                      onPressed: () => context.push('/registro'),
                    ),
                  ],
                ),
              )
            else ...[
              BiffyCard(
                child: Row(
                  children: [
                    PersonAvatar(
                      name: u.name,
                      asset: kDemoAvatars[u.id],
                      radius: 30,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.name, style: t.titleMedium),
                          Text(u.email, style: t.bodySmall),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              Tag(uni == null ? 'Sin universidad' : uni.name),
                              Tag(
                                session.isVerifiedStudent
                                    ? 'Verificado (simulado)'
                                    : 'No verificado',
                                color: session.isVerifiedStudent
                                    ? AppColors.success
                                    : null,
                                textColor: session.isVerifiedStudent
                                    ? Colors.white
                                    : null,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: BigNumber('Pedidos entregados', '$delivered'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => context.push('/recompensas'),
                      child: BigNumber(
                        'Gotas Biffy',
                        '${session.gotas}',
                        highlight: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  if (u != null) ...[
                    item(
                      Icons.badge_outlined,
                      'Información personal',
                      () => context.push('/perfil/datos'),
                    ),
                    item(
                      Icons.receipt_long_outlined,
                      'Mis pedidos',
                      () => context.push('/pedidos'),
                      key: const Key('menu-orders'),
                    ),
                    item(
                      Icons.bolt,
                      'Pedidos frecuentes',
                      () => context.push('/frecuentes'),
                    ),
                    item(
                      Icons.water_drop_outlined,
                      'Recompensas',
                      () => context.push('/recompensas'),
                    ),
                    item(
                      Icons.favorite_border,
                      'Favoritos',
                      () => context.push('/favoritos'),
                    ),
                  ],
                  item(
                    Icons.school_outlined,
                    'Campus',
                    () => context.push('/campus'),
                  ),
                  item(
                    Icons.tune,
                    'Preferencias y alergias',
                    () => context.push('/preferencias'),
                  ),
                  if (u != null) ...[
                    item(
                      Icons.home_outlined,
                      'Direcciones',
                      () => context.push('/direcciones'),
                    ),
                    item(
                      Icons.account_balance_wallet_outlined,
                      'Métodos de pago',
                      () => context.push('/pagos'),
                    ),
                  ],
                  item(
                    Icons.notifications_none,
                    'Notificaciones',
                    () => context.push('/notificaciones'),
                  ),
                  item(
                    Icons.settings_outlined,
                    'Configuración',
                    () => context.push('/ajustes'),
                  ),
                  item(
                    Icons.help_outline,
                    'Ayuda y soporte',
                    () => context.push('/soporte'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  item(
                    Icons.delivery_dining,
                    'Modo repartidor',
                    () => _courierMode(context),
                    key: const Key('mode-courier'),
                  ),
                  item(
                    Icons.storefront,
                    'Modo restaurante',
                    () => _restaurantMode(context),
                    key: const Key('mode-restaurant'),
                  ),
                  if (u != null)
                    item(
                      Icons.logout,
                      'Cerrar sesión',
                      () => logoutFlow(context),
                      key: const Key('logout'),
                      color: AppColors.error,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Cambia al modo repartidor o lleva a su registro.
  Future<void> _courierMode(BuildContext context) async {
    if (!await requireLogin(context, reason: 'usar el modo repartidor')) return;
    if (!context.mounted) return;
    final session = getIt<SessionController>();
    if (session.hasCourierProfile) {
      session.setActiveRole(UserRole.courier);
      context.go('/repartidor');
    } else {
      context.push('/repartidor/registro');
    }
  }

  /// Cambia al modo restaurante o explica cómo registrar un negocio.
  void _restaurantMode(BuildContext context) {
    final session = getIt<SessionController>();
    if (session.businessId != null) {
      session.setActiveRole(UserRole.restaurant);
      context.go('/negocio');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Modo restaurante',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Tu cuenta no tiene un negocio. Puedes registrarlo para empezar a vender.',
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: 'Registrar mi negocio',
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/negocio/registro');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cierra sesión con confirmación y vuelve al inicio. Primero navega (la
/// pantalla actual puede desaparecer al cambiar la sesión) y después cierra
/// también la sesión del servidor: así el repartidor se desconecta y al
/// reabrir la app no se restaura la cuenta anterior.
Future<void> logoutFlow(BuildContext context) async {
  final ok = await showConfirm(
    context,
    title: '¿Cerrar sesión?',
    message: 'Se cerrará tu sesión en este dispositivo.',
    confirm: 'Cerrar sesión',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  GoRouter.of(context).go('/');
  await getIt<SessionController>().logoutAsync();
  messenger.showSnackBar(const SnackBar(content: Text('Sesión cerrada')));
}
