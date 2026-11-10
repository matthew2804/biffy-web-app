import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/session_controller.dart';
import 'notifications_cubit.dart';

/// Notificaciones locales del rol activo; cada una abre su pantalla.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  /// Crea el [NotificationsCubit] y pinta su estado.
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NotificationsCubit(
        center: context.read<NotificationCenter>(),
        session: context.read<SessionController>(),
      ),
      child: BlocBuilder<NotificationsCubit, NotificationsState>(
        builder: (context, state) => _NotificationsView(state: state),
      ),
    );
  }
}

/// Lista de avisos: solo dibuja el [NotificationsState].
class _NotificationsView extends StatelessWidget {
  const _NotificationsView({required this.state});

  final NotificationsState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<NotificationsCubit>();
    final list = state.items;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (state.unread > 0)
            TextButton(
              key: const Key('notif-mark-all'),
              onPressed: cubit.markAllRead,
              child: const Text('Marcar leídas'),
            ),
        ],
      ),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            if (!state.enabled)
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
                      cubit.open(n);
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
