import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/features/auth/login_screen.dart';
import 'package:biffy/features/buyer/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets(
    'el repartidor cierra sesión y el comprador entra sin quedar en el login',
    (tester) async {
      final s = await makeServices();
      await pumpBiffy(tester, services: s, initialLocation: '/login');

      await loginViaForm(tester, kDemoCourierEmail);
      expect(s.session.hasCourierProfile, isTrue);
      await waitSnackBars(tester);

      // Cerrar sesión desde el perfil del repartidor.
      await tapVisible(tester, find.text('Perfil').last);
      await tapVisible(tester, find.text('Cerrar sesión'));
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('Cerrar sesión'),
        ),
      );
      await tester.pumpAndSettle();
      expect(s.session.isLoggedIn, isFalse);
      expect(find.byType(HomeScreen), findsOneWidget);

      // Entrar como comprador desde el inicio.
      await waitSnackBars(tester);
      await tapVisible(tester, find.text('Iniciar sesión').first);
      await loginViaForm(tester, kDemoBuyerEmail);

      expect(s.session.user?.id, 'u-diego');
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await waitSnackBars(tester);
    },
  );
}
