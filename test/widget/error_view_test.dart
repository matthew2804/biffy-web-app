import 'package:biffy/core/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del estado de error reutilizable.
void main() {
  testWidgets('ErrorView muestra título y ejecuta el reintento', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorView(
            title: 'Falló la carga',
            body: 'Detalle del error',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('Falló la carga'), findsOneWidget);
    expect(find.text('Detalle del error'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    expect(retries, 1);
  });

  testWidgets('ErrorView sin onRetry no muestra botón', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ErrorView())),
    );

    expect(find.text('No pudimos cargar esto'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });
}
