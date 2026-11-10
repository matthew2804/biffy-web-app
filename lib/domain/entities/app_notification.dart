/// Notificación local dentro de la app (sin push real).
class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.createdAt,
    this.route,
    this.read = false,
  });

  final String id;
  final String title;
  final String body;

  /// Destinatario: `all`, `user:<id>`, `business:<id>`, `couriers` o `courier:<id>`.
  final String audience;
  final DateTime createdAt;
  final String? route;
  bool read;
}
