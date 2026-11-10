import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  testWidgets('en modo demo las cajas avisan que requieren Supabase', (
    tester,
  ) async {
    final s = makeServices();
    s.session.login(kDemoRestaurantEmail, kDemoPassword);
    await pumpBiffy(tester, services: s, initialLocation: '/negocio/cajas');
    expect(find.text('Solo con Supabase'), findsOneWidget);
  });
}
