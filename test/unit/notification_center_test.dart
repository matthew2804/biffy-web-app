import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/data/models/app_notification.dart';
import 'package:biffy/data/models/user.dart';
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
  });
}
