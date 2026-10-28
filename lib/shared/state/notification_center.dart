import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/user.dart';

/// Notificaciones locales dentro de la app (sin push ni FCM en este sprint).
class NotificationCenter extends ChangeNotifier {
  /// Usa el reloj indicado para fechar las notificaciones.
  NotificationCenter(this._clock);

  final Clock _clock;
  final List<AppNotification> _items = [];
  int _seq = 0;

  /// Todas las notificaciones (solo lectura).
  List<AppNotification> get all => List.unmodifiable(_items);

  /// Crea una notificación para una audiencia y avisa a la UI.
  void push({
    required String title,
    required String body,
    required String audience,
    String? route,
  }) {
    _items.insert(
      0,
      AppNotification(
        id: 'n${++_seq}',
        title: title,
        body: body,
        audience: audience,
        createdAt: _clock.now(),
        route: route,
      ),
    );
    notifyListeners();
  }

  /// `true` si la notificación corresponde al usuario y rol.
  static bool isFor(AppNotification n, AppUser? user, UserRole role) {
    if (n.audience == 'all') return true;
    if (user == null) return n.audience == 'guest';
    return switch (role) {
      UserRole.buyer => n.audience == 'user:${user.id}',
      UserRole.courier =>
        n.audience == 'couriers' || n.audience == 'courier:${user.id}',
      UserRole.restaurant =>
        user.businessId != null && n.audience == 'business:${user.businessId}',
    };
  }

  /// Notificaciones que puede ver el usuario según su rol.
  List<AppNotification> visibleFor(AppUser? user, UserRole role) =>
      _items.where((n) => isFor(n, user, role)).toList();

  /// Cantidad de notificaciones sin leer para el usuario.
  int unreadFor(AppUser? user, UserRole role) =>
      visibleFor(user, role).where((n) => !n.read).length;

  /// Marca una notificación como leída.
  void markRead(String id) {
    for (final n in _items) {
      if (n.id == id) n.read = true;
    }
    notifyListeners();
  }

  /// Marca como leídas todas las visibles para el usuario.
  void markAllRead(AppUser? user, UserRole role) {
    for (final n in visibleFor(user, role)) {
      n.read = true;
    }
    notifyListeners();
  }
}
