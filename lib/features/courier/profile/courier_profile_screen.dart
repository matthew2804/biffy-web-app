import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/mock/seed_users.dart';
import '../../../data/models/user.dart';
import '../../../shared/state/session_controller.dart';
import '../../buyer/profile/profile_screen.dart';

class CourierProfileScreen extends StatelessWidget {
  const CourierProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final p = session.data.courierProfile!;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Perfil de repartidor', style: t.headlineSmall),
            const SizedBox(height: 12),
            Center(
              child: PersonAvatar(
                name: p.fullName,
                asset: kDemoAvatars[session.user?.id],
                radius: 44,
              ),
            ),
            const SizedBox(height: 12),
            BiffyCard(
              child: Column(
                children: [
                  InfoRow('Nombre', p.fullName),
                  InfoRow('Documento', '${p.docType} ${p.docNumber}'),
                  InfoRow('Teléfono', p.phone),
                  InfoRow('Correo', p.contactEmail),
                  InfoRow(
                    'Transporte',
                    '${p.vehicle.emoji} ${p.vehicle.label}',
                  ),
                  if (p.plate != null) InfoRow('Placa', p.plate!),
                  InfoRow(
                    'Universidad',
                    universityById(p.universityId)?.name ?? 'Ninguna',
                  ),
                  InfoRow(
                    'Modo Campus',
                    session.isVerifiedStudent
                        ? 'Habilitado (simulado)'
                        : 'Bloqueado',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Identidad no verificada legalmente: datos de demostración.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Editar datos'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/repartidor/registro'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.notifications_none),
                    title: const Text('Notificaciones'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/notificaciones'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.help_outline),
                    title: const Text('Ayuda y soporte'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/soporte'),
                  ),
                  ListTile(
                    key: const Key('to-buyer'),
                    leading: const Icon(Icons.shopping_bag_outlined),
                    title: const Text('Cambiar a modo comprador'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      session.setActiveRole(UserRole.buyer);
                      context.go('/');
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.switch_account),
                    title: const Text('Cuentas de demostración'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showDemoAccountsSheet(context),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout, color: AppColors.error),
                    title: const Text(
                      'Cerrar sesión',
                      style: TextStyle(color: AppColors.error),
                    ),
                    onTap: () => logoutFlow(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
