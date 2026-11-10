import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/actions.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/session_controller.dart';

/// Preferencias de notificaciones, tema y punto de entrega.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  /// Construye los interruptores de ajustes y el acceso al punto de entrega.
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final s = session.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SwitchListTile(
                    key: const Key('set-notifications'),
                    title: const Text('Notificaciones'),
                    subtitle: const Text(
                      'Avisos dentro de la app y contador en el inicio',
                    ),
                    value: s.notifications,
                    onChanged: (v) =>
                        session.updateSettings(s.copyWith(notifications: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Promociones'),
                    subtitle: const Text(
                      'Muestra tarjetas promocionales en el inicio',
                    ),
                    value: s.promotions,
                    onChanged: (v) =>
                        session.updateSettings(s.copyWith(promotions: v)),
                  ),
                  SwitchListTile(
                    title: const Text('Resumen por correo'),
                    subtitle: const Text(
                      'Preferencia guardada localmente: la demo no envía correos',
                    ),
                    value: s.emailSummary,
                    onChanged: (v) =>
                        session.updateSettings(s.copyWith(emailSummary: v)),
                  ),
                  SwitchListTile(
                    key: const Key('set-demo-lunch'),
                    title: const Text('Horario de demostración (12:00)'),
                    subtitle: const Text(
                      'Simula la hora del almuerzo para probar pedidos inmediatos a cualquier hora. No cambia el reloj del teléfono.',
                    ),
                    value: s.demoLunch,
                    onChanged: (v) =>
                        session.updateSettings(s.copyWith(demoLunch: v)),
                  ),
                  SwitchListTile(
                    key: const Key('set-dark'),
                    title: const Text('Modo oscuro'),
                    value: s.darkMode,
                    onChanged: (v) =>
                        session.updateSettings(s.copyWith(darkMode: v)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            BiffyCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: const Text('Punto de entrega'),
                subtitle: Text(session.point.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDeliveryPointSheet(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Biffy · Sprint 1 · prototipo frontend sin backend. Los datos se pierden al cerrar la app.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
