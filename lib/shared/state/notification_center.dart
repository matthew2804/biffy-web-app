import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/models/app_notification.dart';
import '../../data/models/user.dart';

/// Notificaciones locales dentro de la app (sin push ni FCM en este sprint).
class NotificationCenter extends ChangeNotifier {
  NotificationCenter(this._clock);

  final Clock _clock;
  final List<AppNotification> _items = [];
  int _seq = 0;

  List<AppNotification> get all => List.unmodifiable(_items);

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

  List<AppNotification> visibleFor(AppUser? user, UserRole role) =>
      _items.where((n) => isFor(n, user, role)).toList();

  int unreadFor(AppUser? user, UserRole role) =>
      visibleFor(user, role).where((n) => !n.read).length;

  void markRead(String id) {
    for (final n in _items) {
      if (n.id == id) n.read = true;
    }
    notifyListeners();
  }

  void markAllRead(AppUser? user, UserRole role) {
    for (final n in visibleFor(user, role)) {
      n.read = true;
    }
    notifyListeners();
  }
}
