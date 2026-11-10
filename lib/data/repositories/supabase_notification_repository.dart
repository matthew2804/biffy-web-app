import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/repositories/notification_repository.dart';
import '../models/app_notification.dart';

/// Notificaciones en Supabase: las crea la base (0022) y llegan por Realtime.
class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository([sb.SupabaseClient? client])
    : _client = client ?? sb.Supabase.instance.client;

  final sb.SupabaseClient _client;

  /// Notificaciones guardadas del usuario (solo las dirigidas a él).
  @override
  Future<List<AppNotification>> forUser(String userId) async {
    final rows = await _client
        .from('notifications')
        .select('id, title, body, audience, route, read_at, created_at')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);

    return rows.map(notificationFromRow).toList();
  }

  /// Escucha en Realtime los avisos nuevos o leídos del usuario.
  /// Devuelve la función que cancela la suscripción.
  @override
  void Function() watch(
    String userId,
    void Function(AppNotification n) onChange,
  ) {
    try {
      final channel = _client
          .channel('biffy-notifications-$userId')
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: sb.PostgresChangeFilter(
              type: sb.PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (payload) {
              final row = payload.newRecord;
              if (row['id'] == null) return;
              onChange(notificationFromRow(row));
            },
          )
          .subscribe();
      return () => _client.removeChannel(channel);
    } on Object {
      return () {};
    }
  }

  /// Convierte una fila de `notifications` al modelo (hora local).
  @visibleForTesting
  static AppNotification notificationFromRow(Map<String, dynamic> row) =>
      AppNotification(
        id: row['id'] as String,
        title: (row['title'] as String?) ?? '',
        body: (row['body'] as String?) ?? '',
        audience: (row['audience'] as String?) ?? 'all',
        createdAt:
            DateTime.tryParse(
              (row['created_at'] as String?) ?? '',
            )?.toLocal() ??
            DateTime.now(),
        route: row['route'] as String?,
        read: row['read_at'] != null,
      );

  /// Guarda una notificación dirigida al usuario actual.
  @override
  Future<void> save(AppNotification n) async {
    // Solo se persisten las notificaciones personales (`user:<id>`).
    if (!n.audience.startsWith('user:')) return;
    final userId = n.audience.substring(5);
    try {
      await _client.from('notifications').insert({
        'user_id': userId,
        'audience': n.audience,
        'title': n.title,
        'body': n.body,
        'route': n.route,
      });
    } on Object {
      // Si falla, la notificación local se conserva igual.
    }
  }

  /// Marca como leída una notificación guardada.
  @override
  Future<void> markRead(String id) async {
    // Los ids locales (`n1`) no son uuid: se ignoran.
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      return;
    }
    try {
      await _client
          .from('notifications')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', id);
    } on Object {
      // Silencioso: el estado local ya cambió.
    }
  }
}
