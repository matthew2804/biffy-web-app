import 'package:biffy/core/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Pinta [SyncStateView] dentro de una app mínima.
Future<void> _pump(
  WidgetTester tester, {
  required bool isEmpty,
  bool loading = false,
  bool failed = false,
  VoidCallback? onRetry,
}) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SyncStateView(
        isEmpty: isEmpty,
        loading: loading,
        failed: failed,
        onRetry: onRetry ?? () {},
        child: const Text('contenido'),
      ),
    ),
  ),
);

void main() {
  testWidgets('lista vacía por error: muestra reintento y lo ejecuta', (
    tester,
  ) async {
    var retries = 0;
    await _pump(tester, isEmpty: true, failed: true, onRetry: () => retries++);
    expect(find.byKey(const Key('sync-error')), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    expect(retries, 1);
  });

  testWidgets('lista vacía mientras carga: indicador, no vacío falso', (
    tester,
  ) async {
    await _pump(tester, isEmpty: true, loading: true);
    expect(find.byKey(const Key('sync-loading')), findsOneWidget);
    expect(find.text('contenido'), findsNothing);
  });

  testWidgets('con datos en caché se muestra el contenido aunque falle', (
    tester,
  ) async {
    await _pump(tester, isEmpty: false, failed: true);
    expect(find.text('contenido'), findsOneWidget);
  });

  testWidgets('el inicio avisa cuando faltan repartidores conectados', (
    tester,
  ) async {
    final s = await makeServices();
    for (final r in s.catalog.repo.restaurants) {
      r.couriersNearby = 0;
    }
    await pumpBiffy(tester, services: s, initialLocation: '/');
    await scrollTo(tester, find.byKey(const Key('no-couriers')));
    expect(find.text('No hay repartidores conectados ahora'), findsOneWidget);
  });
}
