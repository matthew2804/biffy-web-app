import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/core/utils/format.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/domain/order_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('las ganancias salen de las entregas del repartidor', (
    tester,
  ) async {
    final s = makeServices();
    final o = deliverQbano(s);
    s.session.login(kDemoCourierEmail, kDemoPassword);
    await pumpBiffy(
      tester,
      services: s,
      initialLocation: '/repartidor/ganancias',
    );

    expect(find.text('Valores simulados de la demostración.'), findsOneWidget);
    final today = computeEarnings(
      s.orders
          .deliveredBy('u-andres')
          .where((x) => sameDay(x.deliveredAt!, s.catalog.now)),
    );
    expect(today.deliveries, greaterThanOrEqualTo(1));
    expect(find.text(cop(today.net)), findsWidgets);

    await scrollTo(tester, find.byKey(Key('earning-${o.id}')));
    expect(find.text(cop(o.courierEarning)), findsWidgets);
  });
}
