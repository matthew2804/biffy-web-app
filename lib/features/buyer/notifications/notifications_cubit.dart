import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/app_notification.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/session_controller.dart';

/// Lo que muestra la pantalla de notificaciones del rol activo.
class NotificationsState {
  const NotificationsState({required this.items, required this.enabled});

  /// Avisos visibles para el usuario y rol, del más nuevo al más viejo.
  final List<AppNotification> items;

  /// `false` si el usuario apagó las notificaciones en Ajustes.
  final bool enabled;

  /// Cuántos avisos faltan por leer.
  int get unread => items.where((n) => !n.read).length;
}

/// Cubit de notificaciones: filtra los avisos del rol activo y los marca
/// como leídos. Se actualiza solo cuando llega un aviso (Realtime o demo).
///
/// Flujo: [NotificationCenter] (avisos compartidos) + [SessionController]
/// (quién soy) → [NotificationsCubit] → pantalla.
class NotificationsCubit extends Cubit<NotificationsState> {
  NotificationsCubit({
    required NotificationCenter center,
    required SessionController session,
  }) : _center = center,
       _session = session,
       super(_read(center, session)) {
    _center.addListener(_refresh);
    _session.addListener(_refresh);
  }

  final NotificationCenter _center;
  final SessionController _session;

  static NotificationsState _read(
    NotificationCenter center,
    SessionController session,
  ) => NotificationsState(
    items: center.visibleFor(session.user, session.activeRole),
    enabled: session.settings.notifications,
  );

  void _refresh() {
    if (!isClosed) emit(_read(_center, _session));
  }

  /// Marca un aviso como leído (y en la base si viene de Supabase).
  void open(AppNotification n) {
    if (!n.read) _center.markRead(n.id);
  }

  /// Marca como leídos todos los avisos visibles.
  void markAllRead() => _center.markAllRead(_session.user, _session.activeRole);

  @override
  Future<void> close() {
    _center.removeListener(_refresh);
    _session.removeListener(_refresh);
    return super.close();
  }
}
