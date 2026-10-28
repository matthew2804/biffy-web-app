import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/user.dart';

/// Notificaciones locales dentro de la app (sin push ni FCM en este sprint).
class NotificationCenter extends ChangeNotifier {
  /// Usa el reloj indicado y, opcionalmente, persiste en el backend.
  NotificationCenter(this._clock, {this.persist, this.onRead});

  final Clock _clock;
  final List<AppNotification> _items = [];
  int _seq = 0;

  /// Guarda una notificación nueva (null en modo demo).
  final Future<void> Function(AppNotification n)? persist;

  /// Marca una notificación como leída en el backend (null en modo demo).
  final void Function(String id)? onRead;

  /// Todas las notificaciones (solo lectura).
  List<AppNotification> get all => List.unmodifiable(_items);

  /// Crea una notificación para una audiencia y avisa a la UI.
  void push({
    required String title,
    required String body,
    required String audience,
    String? route,
  }) {
    final n = AppNotification(
      id: 'n${++_seq}',
      title: title,
      body: body,
      audience: audience,
      createdAt: _clock.now(),
      route: route,
    );
    _items.insert(0, n);
    persist?.call(n);
    notifyListeners();
  }

  /// Carga notificaciones ya guardadas sin volver a persistirlas.
  void seed(Iterable<AppNotification> items) {
    final known = {for (final n in _items) n.id};
    var changed = false;
    for (final n in items) {
      if (known.add(n.id)) {
        _items.add(n);
        changed = true;
      }
    }
    if (!changed) return;
    _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
    onRead?.call(id);
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
