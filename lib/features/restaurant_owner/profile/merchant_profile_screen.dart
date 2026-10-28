import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/user.dart';
import '../../../domain/catalog_rules.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';
import '../../buyer/profile/profile_screen.dart';

/// Perfil del negocio. Los campos que aún no se pueden editar se muestran
/// como información (sin botones engañosos).
class MerchantProfileScreen extends StatelessWidget {
  const MerchantProfileScreen({super.key});

  /// Muestra identidad, sedes, horarios y opciones de la cuenta.
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final t = Theme.of(context).textTheme;
    final b = catalog.businessById(session.businessId!)!;
    final branches = catalog.branchesOf(b.id);
    final paused = catalog.isBusinessPaused(b.id);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text('Perfil del negocio', style: t.headlineSmall),
            const SectionHeader('Identidad comercial'),
            BiffyCard(
              child: Column(
                children: [
                  InfoRow('Marca', b.brand),
                  InfoRow('Razón social', b.legalName),
                  InfoRow('NIT', b.nit),
                  InfoRow('Cocina', categoryById(b.cuisine).label),
                  InfoRow('Responsable', b.ownerName),
                  InfoRow('Contacto', b.ownerEmail),
                ],
              ),
            ),
            const SectionHeader('Sedes y horarios'),
            for (final r in branches)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: BiffyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${r.branchName} · ${r.name}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(r.address, style: t.bodySmall),
                      Text('🕒 ${scheduleLabel(r)}', style: t.bodySmall),
                      Text(
                        '📍 Radio ${r.radiusKm} km · ${r.couriersNearby} repartidores cerca (simulado)',
                        style: t.bodySmall,
                      ),
                      if (r.campusId != null)
                        Text(
                          '🎓 ${universityById(r.campusId)?.name} · ${(r.studentDiscount * 100).round()}% estudiantes',
                          style: t.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            const SectionHeader('Estado y preferencias'),
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Restaurante abierto'),
                    subtitle: Text(
                      paused
                          ? 'Pausado: no recibe pedidos'
                          : 'Recibiendo pedidos',
                    ),
                    value: !paused,
                    onChanged: (v) => catalog.setBusinessPaused(b.id, !v),
                  ),
                  SwitchListTile(
                    title: const Text('Mostrar información nutricional'),
                    subtitle: const Text(
                      'Se muestra en los platos que la tengan',
                    ),
                    value: b.nutritionInfo,
                    onChanged: (v) => catalog.setNutritionInfo(b.id, v),
                  ),
                ],
              ),
            ),
            const SectionHeader('Pagos y liquidaciones (demo)'),
            BiffyCard(
              child: Column(
                children: [
                  InfoRow('Banco', b.bankName),
                  InfoRow('Tipo de cuenta', b.accountType),
                  InfoRow('Cuenta', b.accountNumber),
                  const InfoRow('Liquidación', 'Informativa · semanal'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Datos de demostración: no se procesan pagos ni liquidaciones.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    key: const Key('merchant-to-buyer'),
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
