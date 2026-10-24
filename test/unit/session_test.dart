import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/data/models/user.dart';
import 'package:biffy/data/repositories/auth_repository.dart';
import 'package:biffy/shared/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late SessionController s;
  setUp(() => s = makeServices().session);

  group('Autenticación simulada', () {
    test('login correcto y rol', () {
      final u = s.login(kDemoCourierEmail, kDemoPassword);
      expect(u.role, UserRole.courier);
      expect(s.activeRole, UserRole.courier);
    });

    test('contraseña incorrecta falla', () {
      expect(
        () => s.login(kDemoBuyerEmail, 'mal'),
        throwsA(isA<AuthException>()),
      );
    });

    test('registro duplicado falla', () {
      expect(
        () => s.register(
          name: 'X',
          email: kDemoBuyerEmail,
          password: '123456',
          role: UserRole.buyer,
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('bienvenida de 450 Gotas una sola vez', () {
      s.login(kDemoNewBuyerEmail, kDemoPassword);
      expect(s.gotas, kWelcomeGotas);
      s.logout();
      s.login(kDemoNewBuyerEmail, kDemoPassword);
      expect(s.gotas, kWelcomeGotas);
    });

    test('logout limpia la sesión', () {
      s.login(kDemoBuyerEmail, kDemoPassword);
      s.logout();
      expect(s.isLoggedIn, isFalse);
      expect(s.user, isNull);
    });
  });

  group('Preferencias y recompensas', () {
    const prefs = Preferences(
      likes: {'pizza'},
      allergies: {'maní'},
      budget: 20000,
    );

    test('guardar preferencias', () {
      s.login(kDemoNewBuyerEmail, kDemoPassword);
      s.savePreferences(prefs);
      expect(s.prefs.likes, {'pizza'});
      expect(s.prefs.allergies, {'maní'});
      expect(s.data.prefsCompleted, isTrue);
    });

    test('300 Gotas la primera vez y nunca duplicadas', () {
      s.login(kDemoNewBuyerEmail, kDemoPassword);
      final before = s.gotas;
      expect(s.savePreferences(prefs), kSurveyGotas);
      expect(s.gotas, before + kSurveyGotas);
      expect(s.savePreferences(prefs.copyWith(budget: 30000)), 0);
      expect(s.gotas, before + kSurveyGotas);
    });

    test('sin sesión no se acreditan Gotas', () {
      expect(s.savePreferences(prefs), 0);
      expect(s.gotas, 0);
      expect(s.data.prefsCompleted, isTrue);
    });

    test('canje valida saldo suficiente', () {
      s.login(kDemoNewBuyerEmail, kDemoPassword); // 450 Gotas
      final expensive = kBenefits.firstWhere((b) => b.cost > 450);
      expect(s.redeem(expensive), isNull);
      expect(s.gotas, 450);
      final cheap = kBenefits.firstWhere((b) => b.cost <= 450);
      expect(s.redeem(cheap), isNotNull);
      expect(s.gotas, 450 - cheap.cost);
    });

    test('verificación universitaria simulada por dominio', () {
      s.login(kDemoNewBuyerEmail, kDemoPassword);
      expect(
        s.verifyUniversity('icesi', 'a@gmail.com'),
        VerifyResult.domainMismatch,
      );
      expect(s.verifyUniversity('icesi', 'a@icesi.edu.co'), VerifyResult.ok);
      expect(s.verifiedUniversityId, 'icesi');
    });

    test('favoritos requieren sesión', () {
      expect(s.toggleFavoriteDish('capuchino'), isFalse);
      s.login(kDemoNewBuyerEmail, kDemoPassword);
      expect(s.toggleFavoriteDish('capuchino'), isTrue);
      expect(s.data.favoriteDishes, contains('capuchino'));
    });

    test('modo Campus del repartidor requiere verificación', () {
      s.login(kDemoCourier2Email, kDemoPassword);
      expect(s.setCourierZone(CourierZone.campus), isFalse);
      expect(s.setCourierZone(CourierZone.general), isTrue);
    });
  });
}
