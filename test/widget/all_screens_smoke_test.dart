import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Recorre todas las rutas de cada rol y comprueba que se renderizan sin
/// excepciones ni pantallas en blanco.
void main() {
  testWidgets('rutas públicas y del comprador', (tester) async {
    final s = await pumpBiffy(tester);
    for (final route in [
      '/',
      '/explorar',
      '/explorar?cat=pizza',
      '/ai',
      '/perfil',
      '/restaurante/qbano-icesi',
      '/restaurante/no-existe',
      '/plato/qbano-especial',
      '/plato/no-existe',
      '/carrito',
      '/preferencias',
      '/notificaciones',
      '/ajustes',
      '/soporte',
      '/campus',
      '/ruta-inexistente',
    ]) {
      await goTo(tester, route);
      expect(tester.takeException(), isNull, reason: route);
      expect(find.byType(Scaffold), findsWidgets, reason: route);
    }
    s.session.login(kDemoBuyerEmail, kDemoPassword);
    s.cart.add(s.catalog.dishById('qbano-especial')!);
    for (final route in [
      '/',
      '/perfil',
      '/carrito',
      '/checkout',
      '/pedidos',
      '/pedido/BF-1830',
      '/pedido/BF-0000',
      '/frecuentes',
      '/recompensas',
      '/favoritos',
      '/direcciones',
      '/direcciones/nueva',
      '/direcciones/addr-diego-1',
      '/pagos',
      '/perfil/datos',
      '/campus',
      '/ai',
    ]) {
      await goTo(tester, route);
      expect(tester.takeException(), isNull, reason: route);
    }
  });

  testWidgets('rutas del repartidor', (tester) async {
    final s = await pumpBiffy(tester);
    s.session.login(kDemoCourierEmail, kDemoPassword);
    for (final route in [
      '/repartidor',
      '/repartidor/ganancias',
      '/repartidor/perfil',
      '/repartidor/registro',
      '/repartidor/oferta/BF-1840',
      '/repartidor/recogida/BF-1840',
      '/repartidor/entrega/BF-1840',
    ]) {
      await goTo(tester, route);
      expect(tester.takeException(), isNull, reason: route);
    }
  });

  testWidgets('rutas del restaurante', (tester) async {
    final s = await pumpBiffy(tester);
    s.session.login(kDemoRestaurantEmail, kDemoPassword);
    for (final route in [
      '/negocio',
      '/negocio/pedidos',
      '/negocio/pedidos?f=nuevos',
      '/negocio/menu',
      '/negocio/estadisticas',
      '/negocio/perfil',
      '/negocio/producto/nuevo',
      '/negocio/producto/qbano-especial',
      '/negocio/registro',
    ]) {
      await goTo(tester, route);
      expect(tester.takeException(), isNull, reason: route);
    }
  });

  testWidgets('modo oscuro y punto sin cobertura', (tester) async {
    final s = await pumpBiffy(tester);
    s.session.updateSettings(s.session.settings.copyWith(darkMode: true));
    s.session.setPoint('suba');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Casa · Suba'), findsOneWidget);
    s.session.setPoint(kDeliveryPoints.last.id);
    await goTo(tester, '/explorar');
    expect(tester.takeException(), isNull);
  });
}
