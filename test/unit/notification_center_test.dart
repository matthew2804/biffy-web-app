import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/data/models/app_notification.dart';
import 'package:biffy/data/models/user.dart';
import 'package:biffy/data/repositories/supabase_notification_repository.dart';
import 'package:biffy/shared/state/notification_center.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del centro de notificaciones: persistencia, carga y visibilidad.
void main() {
  final clock = Clock.fixed(DateTime(2026, 1, 1, 12));

  /// Crea un usuario de prueba con el rol indicado.
  AppUser user(UserRole role, {String id = 'u1', String? businessId}) =>
      AppUser(
        id: id,
        name: 'Prueba',
        email: 'prueba@biffy.co',
        role: role,
        businessId: businessId,
      );

  group('NotificationCenter', () {
    test('push persiste la notificación con su audiencia', () async {
      final saved = <AppNotification>[];
      final center = NotificationCenter(
        clock,
        persist: (n) async => saved.add(n),
      );

      center.push(title: 'Hola', body: 'Mundo', audience: 'user:u1');
      await Future<void>.delayed(Duration.zero);

      expect(saved, hasLength(1));
      expect(saved.single.audience, 'user:u1');
      expect(center.all.single.title, 'Hola');
    });

    test('seed no duplica ids y ordena de más nueva a más vieja', () {
      final center = NotificationCenter(clock)
        ..seed([
          AppNotification(
            id: 'b',
            title: 'Vieja',
            body: '',
            audience: 'all',
            createdAt: DateTime(2026, 1, 1),
          ),
          AppNotification(
            id: 'a',
            title: 'Nueva',
            body: '',
            audience: 'all',
            createdAt: DateTime(2026, 1, 2),
          ),
        ])
        ..seed([
          AppNotification(
            id: 'a',
            title: 'Duplicada',
            body: '',
            audience: 'all',
            createdAt: DateTime(2026, 1, 2),
          ),
        ]);

      expect(center.all, hasLength(2));
      expect(center.all.first.id, 'a');
      expect(center.all.last.id, 'b');
    });

    test('markRead avisa al backend con el id', () {
      String? read;
      final center = NotificationCenter(clock, onRead: (id) => read = id)
        ..push(title: 't', body: 'b', audience: 'all');

      final id = center.all.single.id;
      center.markRead(id);

      expect(center.all.single.read, isTrue);
      expect(read, id);
    });

    test('visibleFor filtra por rol', () {
      final center = NotificationCenter(clock)
        ..push(title: 'global', body: '', audience: 'all')
        ..push(title: 'mío', body: '', audience: 'user:u1')
        ..push(title: 'repartidores', body: '', audience: 'couriers')
        ..push(title: 'negocio', body: '', audience: 'business:b1');

      final buyer = user(UserRole.buyer);
      final courier = user(UserRole.courier, id: 'u2');
      final restaurant = user(UserRole.restaurant, id: 'u3', businessId: 'b1');

      expect(
        center.visibleFor(buyer, UserRole.buyer).map((n) => n.title),
        containsAll(['global', 'mío']),
      );
      expect(
        center.visibleFor(courier, UserRole.courier).map((n) => n.title),
        containsAll(['global', 'repartidores']),
      );
      expect(
        center.visibleFor(restaurant, UserRole.restaurant).map((n) => n.title),
        containsAll(['global', 'negocio']),
      );
    });

    test('sin sesión solo ve las globales', () {
      final center = NotificationCenter(clock)
        ..push(title: 'global', body: '', audience: 'all')
        ..push(title: 'mío', body: '', audience: 'user:u1');

      expect(center.visibleFor(null, UserRole.buyer).single.title, 'global');
    });

    test('unreadFor cuenta solo las visibles sin leer', () {
      final center = NotificationCenter(clock)
        ..push(title: 'a', body: '', audience: 'all')
        ..push(title: 'b', body: '', audience: 'user:u1')
        ..push(title: 'c', body: '', audience: 'couriers');

      final buyer = user(UserRole.buyer);
      expect(center.unreadFor(buyer, UserRole.buyer), 2);

      center.markAllRead(buyer, UserRole.buyer);
      expect(center.unreadFor(buyer, UserRole.buyer), 0);
    });

    test(
      'upsert agrega el aviso de Realtime una sola vez y sin persistirlo',
      () {
        final saved = <AppNotification>[];
        final center = NotificationCenter(
          clock,
          persist: (n) async => saved.add(n),
        );
        final buyer = user(UserRole.buyer);
        AppNotification aviso({bool read = false}) => AppNotification(
          id: '7d1c0e9a-0000-4000-8000-000000000001',
          title: 'Pedido en camino 🛵',
          body: 'Repa va en camino con tu pedido BF-2041.',
          audience: 'user:u1',
          createdAt: DateTime(2026, 1, 1, 12, 5),
          route: '/pedido/BF-2041',
          read: read,
        );

        center.upsert(aviso());
        center.upsert(aviso());
        expect(center.visibleFor(buyer, UserRole.buyer), hasLength(1));
        expect(center.unreadFor(buyer, UserRole.buyer), 1);
        expect(saved, isEmpty);

        center.upsert(aviso(read: true));
        expect(center.unreadFor(buyer, UserRole.buyer), 0);
      },
    );

    test('marcar todas como leídas avisa al backend de cada una', () {
      final read = <String>[];
      final center = NotificationCenter(clock, onRead: read.add);
      final buyer = user(UserRole.buyer);
      center.push(title: 'A', body: '', audience: 'user:u1');
      center.push(title: 'B', body: '', audience: 'user:u1');
      center.push(title: 'Otro', body: '', audience: 'user:u2');

      center.markAllRead(buyer, UserRole.buyer);
      expect(read, hasLength(2));
      center.markAllRead(buyer, UserRole.buyer);
      expect(read, hasLength(2));
    });

    test('los avisos de la base quedan en hora local', () {
      final n = SupabaseNotificationRepository.notificationFromRow({
        'id': '7d1c0e9a-0000-4000-8000-000000000002',
        'title': 'Pedido entregado ✅',
        'audience': 'user:u1',
        'created_at': '2026-11-10T01:30:00+00:00',
        'read_at': null,
      });
      expect(n.createdAt.isUtc, isFalse);
      expect(n.createdAt, DateTime.utc(2026, 11, 10, 1, 30).toLocal());
      expect(n.read, isFalse);
    });
  });
}
