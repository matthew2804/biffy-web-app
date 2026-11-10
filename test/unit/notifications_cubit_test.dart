import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/features/buyer/notifications/notifications_cubit.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late AppServices s;
  late NotificationsCubit c;

  setUp(() {
    s = makeServices();
    s.session.login(kDemoBuyerEmail, kDemoPassword);
    c = NotificationsCubit(center: s.notifications, session: s.session);
  });
  tearDown(() => c.close());

  test('solo muestra los avisos del usuario y rol activos', () {
    final id = s.session.user!.id;
    final before = c.state.items.length;
    s.notifications.push(title: 'Mío', body: '', audience: 'user:$id');
    s.notifications.push(title: 'De otro', body: '', audience: 'user:otro');
    s.notifications.push(title: 'Repartidores', body: '', audience: 'couriers');

    expect(c.state.items.length, before + 1);
    expect(c.state.items.first.title, 'Mío');
  });

  test('abrir uno y marcar todos baja el contador', () {
    final id = s.session.user!.id;
    s.notifications.push(title: 'A', body: '', audience: 'user:$id');
    s.notifications.push(title: 'B', body: '', audience: 'user:$id');
    final unread = c.state.unread;
    expect(unread, greaterThanOrEqualTo(2));

    c.open(c.state.items.first);
    expect(c.state.unread, unread - 1);

    c.markAllRead();
    expect(c.state.unread, 0);
  });

  test('un pedido entregado avisa al comprador en vivo', () async {
    final before = c.state.items.length;
    await deliverQbano(s);
    expect(c.state.items.length, greaterThan(before));
    expect(c.state.items.map((n) => n.title), contains('Pedido entregado ✅'));
  });
}
