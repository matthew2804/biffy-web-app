import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../unit/rewards_cubit_test.dart' show FakeRewards;

void main() {
  testWidgets('con la base muestra las cajas y el premio al canjear', (
    tester,
  ) async {
    final repo = FakeRewards();
    final s = AppServices.demo(
      clock: Clock.fixed(kTestNow),
      randomSeed: 7,
      rewards: repo,
    );
    s.session.login(kDemoBuyerEmail, kDemoPassword);
    await pumpBiffy(tester, services: s, initialLocation: '/recompensas');

    expect(find.text('Cajas y recompensas'), findsOneWidget);
    await scrollTo(tester, find.text('Caja sorpresa'));
    expect(find.text('Caja básica'), findsOneWidget);

    await tapVisible(tester, find.byKey(const Key('open-box_25')));
    await tester.tap(find.text('Abrir').last);
    await tester.pumpAndSettle();

    expect(repo.redeemed, ['box_25']);
    expect(find.text('¡Te salió un premio! 🎉'), findsOneWidget);
    expect(find.text(r'$2.000 de descuento'), findsOneWidget);
    await tester.tap(find.text('Listo'));
    await tester.pumpAndSettle();
  });

  testWidgets('en modo demo sigue mostrando los beneficios locales', (
    tester,
  ) async {
    final s = makeServices();
    s.session.login(kDemoBuyerEmail, kDemoPassword);
    await pumpBiffy(tester, services: s, initialLocation: '/recompensas');
    expect(find.text('Beneficios disponibles'), findsOneWidget);
  });
}
