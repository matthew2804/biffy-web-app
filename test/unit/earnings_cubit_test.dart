import 'package:biffy/domain/order_rules.dart';
import 'package:biffy/domain/usecases/get_courier_earnings.dart';
import 'package:biffy/features/courier/earnings/earnings_cubit.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late AppServices s;
  setUp(() => s = makeServices());

  group('GetCourierEarnings', () {
    test('suma hoy, la semana y el acumulado con las entregas reales', () {
      final o = deliverQbano(s);
      final now = s.catalog.now;
      final e = const GetCourierEarnings()(
        s.orders.deliveredBy('u-andres'),
        now,
      );

      expect(e.history.first.id, o.id);
      expect(e.today.deliveries, greaterThanOrEqualTo(1));
      expect(e.week, hasLength(7));
      expect(e.week.last.net, e.today.net);
      expect(e.total.net, computeEarnings(e.history).net);
      expect(e.settlement.weekday, DateTime.monday);
      expect(e.settlement.isAfter(now), isTrue);
    });

    test('sin entregas todo queda en cero', () {
      final e = const GetCourierEarnings()(const [], s.catalog.now);
      expect(e.today.net, 0);
      expect(e.total.deliveries, 0);
      expect(e.week.every((d) => d.net == 0), isTrue);
      expect(e.history, isEmpty);
    });
  });

  group('EarningsCubit', () {
    test(
      'se actualiza solo cuando el repartidor entrega otro pedido',
      () async {
        final c = EarningsCubit(
          orders: s.orders,
          courierId: 'u-andres',
          now: () => s.catalog.now,
        );
        final before = c.state.today.deliveries;

        final o = deliverQbano(s);
        expect(c.state.today.deliveries, before + 1);
        expect(c.state.history.first.id, o.id);

        await c.close();
        deliverQbano(s);
        expect(c.state.today.deliveries, before + 1);
      },
    );
  });
}
