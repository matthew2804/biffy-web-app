import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/helpers.dart';
import '../test/integration/full_flow.dart';

/// Prueba de integración en dispositivo/emulador:
/// `flutter test integration_test/app_test.dart -d <id-del-dispositivo>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('flujo completo en dispositivo', (tester) async {
    final s = makeServices();
    await pumpBiffy(
      tester,
      services: s,
      initialLocation: '/splash',
      settle: false,
      phoneSize: false,
    );
    await runFullOrderFlow(tester, s);
  });
}
