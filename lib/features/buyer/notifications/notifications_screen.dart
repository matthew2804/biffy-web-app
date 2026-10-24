import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/session_controller.dart';

/// Notificaciones locales del rol activo; cada una abre su pantalla.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final center = context.watch<NotificationCenter>();
    final session = context.watch<SessionController>();
    final list = center.visibleFor(session.user, session.activeRole);
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (list.any((n) => !n.read))
            TextButton(
              onPressed: () =>
                  center.markAllRead(session.user, session.activeRole),
              child: const Text('Marcar leídas'),
            ),
        ],
      ),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (!session.settings.notifications)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: BiffyCard(
                  color: AppColors.secondary.withValues(alpha: 0.2),
                  onTap: () => context.push('/ajustes'),
                  child: const Text(
                    '🔕 Tienes las notificaciones desactivadas: no verás avisos en el inicio. Toca para cambiarlo.',
                  ),
                ),
              ),
            if (list.isEmpty)
              const EmptyState(emoji: '🔔', title: 'No tienes notificaciones')
            else
              for (final n in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: BiffyCard(
                    key: Key('notif-${n.id}'),
                    border: n.read
                        ? null
                        : Border.all(color: AppColors.primary, width: 2),
                    onTap: () {
                      center.markRead(n.id);
                      if (n.route != null) context.push(n.route!);
                    },
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                n.title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(n.body),
                              const SizedBox(height: 4),
                              Text(
                                '${relativeDay(n.createdAt, now)} · ${hourLabel(n.createdAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (n.route != null) const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
