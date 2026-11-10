import 'package:biffy/data/models/order.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets(
    'el comprador califica su pedido entregado desde el seguimiento',
    (tester) async {
      final s = makeServices();
      final o = await deliverQbano(s);
      await pumpBiffy(tester, services: s, initialLocation: '/pedido/${o.id}');

      await scrollTo(tester, find.byKey(const Key('rate-card')));
      await tapVisible(tester, find.byKey(const Key('rate-card-star-4')));
      expect(find.text('Califica tu pedido'), findsOneWidget);

      await tester.tap(find.byKey(const Key('rate-star-5')));
      await tester.enterText(
        find.byKey(const Key('rate-comment')),
        'Llegó caliente',
      );
      await tester.tap(find.byKey(const Key('rate-submit')));
      await tester.pumpAndSettle();

      expect(o.rating, 5);
      expect(o.review, 'Llegó caliente');
      expect(find.byKey(const Key('rate-card')), findsNothing);
      await scrollTo(tester, find.byKey(const Key('rate-done')));
      expect(find.text('«Llegó caliente»'), findsOneWidget);
      await waitSnackBars(tester);
    },
  );

  testWidgets('un pedido sin entregar no muestra la tarjeta de calificar', (
    tester,
  ) async {
    final s = makeServices();
    final o = await placeQbano(s);
    expect(o.status, OrderStatus.pending);
    await pumpBiffy(tester, services: s, initialLocation: '/pedido/${o.id}');
    expect(find.byKey(const Key('rate-card')), findsNothing);
  });
}
