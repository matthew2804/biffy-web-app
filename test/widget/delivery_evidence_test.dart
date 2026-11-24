import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('el comprador ve la evidencia de su pedido entregado', (
    tester,
  ) async {
    final s = await makeServices();
    final o = await deliverQbano(s);
    await pumpBiffy(tester, services: s, initialLocation: '/pedido/${o.id}');

    await scrollTo(tester, find.byKey(const Key('evidence-card')));
    expect(find.text('Evidencia de entrega'), findsOneWidget);
    // En la demo no hay foto en Storage: se muestra lo que registró el repartidor.
    expect(find.byKey(const Key('evidence-empty')), findsOneWidget);
  });

  testWidgets('un pedido sin entregar no muestra evidencia', (tester) async {
    final s = await makeServices();
    final o = await placeQbano(s);
    await pumpBiffy(tester, services: s, initialLocation: '/pedido/${o.id}');
    expect(find.byKey(const Key('evidence-card')), findsNothing);
  });
}
