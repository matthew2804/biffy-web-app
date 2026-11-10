import '../../data/models/app_notification.dart';

/// Contrato de notificaciones guardadas. El dominio no sabe que detrás está
/// Supabase con Realtime; en modo demo no hay repositorio (todo en memoria).
abstract interface class NotificationRepository {
  /// Últimas notificaciones del usuario.
  Future<List<AppNotification>> forUser(String userId);

  /// Escucha avisos nuevos o leídos; devuelve la función que cancela.
  void Function() watch(
    String userId,
    void Function(AppNotification n) onChange,
  );

  /// Guarda un aviso personal creado en la app.
  Future<void> save(AppNotification n);

  /// Marca un aviso como leído.
  Future<void> markRead(String id);
}
