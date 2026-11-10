import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/data/models/address.dart';
import 'package:biffy/data/models/user.dart';
import 'package:biffy/data/repositories/auth_repository.dart';
import 'package:biffy/shared/state/notification_center.dart';
import 'package:biffy/shared/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repositorio remoto falso que registra las escrituras del perfil.
class _FakeRemoteAuth implements AuthRepository {
  _FakeRemoteAuth() {
    user = AppUser(
      id: 'u-remote',
      name: 'Ana',
      email: 'ana@icesi.edu.co',
      role: UserRole.buyer,
    );
  }

  late AppUser user;

  /// Código que devolverá el RPC de verificación.
  String verifyCode = 'ok';

  /// Llamadas al RPC de verificación.
  int verifyCalls = 0;

  /// Últimos datos de perfil guardados.
  ({String? name, String? phone})? savedProfile;

  /// Último perfil de repartidor guardado.
  CourierProfile? savedCourier;

  @override
  bool get isRemote => true;

  @override
  List<AppUser> get demoAccounts => const [];

  @override
  AppUser login(String email, String password) => throw UnimplementedError();

  @override
  AppUser register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) => throw UnimplementedError();

  @override
  AppUser? byId(String id) => id == user.id ? user : null;

  @override
  AppUser? byBusiness(String businessId) => null;

  @override
  Future<AppUser> signIn(String email, String password) async => user;

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) async => user;

  @override
  Future<void> signOut() async {}

  @override
  Future<AppUser?> restoreSession() async => user;

  @override
  Future<int?> gotasBalance(String userId) async => 450;

  @override
  Future<List<Address>> addresses(String userId) async => const [];

  @override
  Future<CourierProfile?> courierProfile(String userId) async => null;

  @override
  Future<String?> registerBusiness(Map<String, dynamic> payload) async => null;

  @override
  Future<void> saveProfile(String userId, {String? name, String? phone}) async {
    savedProfile = (name: name, phone: phone);
  }

  @override
  Future<void> saveCourierProfile(String userId, CourierProfile profile) async {
    savedCourier = profile;
  }

  @override
  Future<String?> verifyUniversity(String universityId, String email) async {
    verifyCalls++;
    return verifyCode;
  }
}

/// Crea un controlador de sesión con el repositorio remoto falso.
SessionController _session(_FakeRemoteAuth auth) => SessionController(
  auth,
  NotificationCenter(Clock.fixed(DateTime(2026))),
  Clock.fixed(DateTime(2026)),
);

void main() {
  group('Perfil remoto', () {
    test('guardar nombre y teléfono llama al backend', () async {
      final auth = _FakeRemoteAuth();
      final s = _session(auth)..loginAs(auth.user);

      await s.updateProfile(name: 'Ana María', phone: '300 111 2233');

      expect(auth.savedProfile?.name, 'Ana María');
      expect(auth.savedProfile?.phone, '300 111 2233');
      expect(s.user?.name, 'Ana María');
    });

    test('guardar perfil de repartidor lo persiste y activa el rol', () async {
      final auth = _FakeRemoteAuth();
      final s = _session(auth)..loginAs(auth.user);
      const profile = CourierProfile(
        fullName: 'Ana Repartidora',
        docType: 'CC',
        docNumber: '1000000009',
        phone: '300 111 2233',
        vehicle: Vehicle.bicycle,
        contactEmail: 'ana@icesi.edu.co',
      );

      await s.saveCourierProfile(profile);

      expect(auth.savedCourier?.fullName, 'Ana Repartidora');
      expect(auth.savedCourier?.vehicle, Vehicle.bicycle);
      expect(s.activeRole, UserRole.courier);
      expect(s.hasCourierProfile, isTrue);
    });

    test('restoreAsync recupera la sesión persistida', () async {
      final auth = _FakeRemoteAuth();
      final s = _session(auth);

      final restored = await s.restoreAsync();

      expect(restored?.id, auth.user.id);
      expect(s.isLoggedIn, isTrue);
    });

    test('logoutAsync limpia la sesión', () async {
      final auth = _FakeRemoteAuth();
      final s = _session(auth)..loginAs(auth.user);

      await s.logoutAsync();

      expect(s.isLoggedIn, isFalse);
      expect(s.user, isNull);
    });
  });

  group('Verificación universitaria remota', () {
    test('un dominio distinto devuelve domainMismatch sin verificar', () async {
      final auth = _FakeRemoteAuth()..verifyCode = 'domain_mismatch';
      final s = _session(auth)..loginAs(auth.user);

      final result = await s.verifyUniversityAsync('icesi', 'ana@gmail.com');

      expect(result, VerifyResult.domainMismatch);
      expect(auth.verifyCalls, 1);
      expect(s.isVerifiedStudent, isFalse);
    });

    test('un correo inválido no llama al backend', () async {
      final auth = _FakeRemoteAuth();
      final s = _session(auth)..loginAs(auth.user);

      final result = await s.verifyUniversityAsync('icesi', 'sin-arroba');

      expect(result, VerifyResult.invalidEmail);
      expect(auth.verifyCalls, 0);
    });

    test('ok guarda la universidad verificada en la sesión', () async {
      final auth = _FakeRemoteAuth();
      final s = _session(auth)..loginAs(auth.user);

      final result = await s.verifyUniversityAsync('icesi', 'ana@icesi.edu.co');

      expect(result, VerifyResult.ok);
      expect(s.verifiedUniversityId, 'icesi');
      expect(s.data.universityEmail, 'ana@icesi.edu.co');
    });

    test('un error del RPC se traduce a rpcError', () async {
      final auth = _FakeRemoteAuth()..verifyCode = 'algo_raro';
      final s = _session(auth)..loginAs(auth.user);

      final result = await s.verifyUniversityAsync('icesi', 'ana@icesi.edu.co');

      expect(result, VerifyResult.rpcError);
    });
  });
}
