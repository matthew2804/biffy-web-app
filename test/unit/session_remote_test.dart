import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/data/models/address.dart';
import 'package:biffy/data/repositories/auth_repository.dart';
import 'package:biffy/data/repositories/catalog_repository.dart';
import 'package:biffy/shared/state/notification_center.dart';
import 'package:biffy/shared/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const _uuid1 = '11111111-1111-4111-8111-111111111111';
const _uuid2 = '22222222-2222-4222-8222-222222222222';

/// Autenticación «con servidor» simulada: reutiliza las cuentas demo pero
/// responde como lo haría Supabase y anota las llamadas.
class FakeRemoteAuth extends InMemoryAuthRepository {
  FakeRemoteAuth(super.seed);

  String? serverVerifiedUniversity;
  String verifyCode = 'ok';
  bool failWrites = false;
  int serverGotas = 450;
  final List<Address> serverAddresses = [];
  final List<String> calls = [];
  int _seq = 0;

  @override
  bool get isRemote => true;

  @override
  Future<int?> gotasBalance(String userId) async => serverGotas;

  @override
  Future<List<Address>> addresses(String userId) async =>
      List.of(serverAddresses);

  @override
  Future<String?> verifiedUniversity(String userId) async =>
      serverVerifiedUniversity;

  @override
  Future<String> verifyUniversity(String universityId, String email) async {
    calls.add('verify:$universityId');
    return verifyCode;
  }

  @override
  Future<Address?> saveAddress(
    String userId,
    Address address, {
    required bool makeDefault,
  }) async {
    calls.add('save:${address.label}:default=$makeDefault');
    if (failWrites) throw StateError('sin red');
    final id = isUuid(address.id)
        ? address.id
        : '00000000-0000-4000-8000-${(++_seq).toString().padLeft(12, '0')}';
    return Address(
      id: id,
      label: address.label,
      line: address.line,
      details: address.details,
      neighborhood: address.neighborhood,
      reference: address.reference,
      pointId: address.pointId,
    );
  }

  @override
  Future<void> deleteAddress(String userId, String addressId) async {
    calls.add('delete:$addressId');
    if (failWrites) throw StateError('sin red');
  }

  @override
  Future<void> setDefaultAddress(String userId, String addressId) async {
    calls.add('default:$addressId');
    if (failWrites) throw StateError('sin red');
  }

  bool isUuid(String v) => RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  ).hasMatch(v);
}

void main() {
  late FakeRemoteAuth auth;
  late SessionController session;

  setUp(() {
    final clock = Clock.fixed(kTestNow);
    auth = FakeRemoteAuth(seedUsers(InMemoryCatalogRepository().businesses));
    session = SessionController(auth, NotificationCenter(clock), clock);
  });

  Address draft(String label, {String id = ''}) => Address(
    id: id,
    label: label,
    line: 'Calle 1',
    neighborhood: 'Pance',
    pointId: 'icesi-biblioteca',
  );

  group('Verificación universitaria: manda el servidor', () {
    test('al iniciar sesión se hidrata lo que el servidor tiene verificado', () async {
      auth.serverVerifiedUniversity = 'icesi';
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      expect(session.verifiedUniversityId, 'icesi');
    });

    test('si el servidor no lo tiene verificado, la app tampoco', () async {
      auth.serverVerifiedUniversity = null;
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      expect(session.verifiedUniversityId, isNull);
    });

    test('cambiar la universidad de preferencias no revoca la verificación', () async {
      auth.serverVerifiedUniversity = 'icesi';
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      session.setUniversity('unal');
      expect(session.verifiedUniversityId, 'icesi');
    });

    test('verificar llama al RPC y solo entonces queda verificado', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      final r = await session.verifyUniversityAsync(
        'icesi',
        'diego@icesi.edu.co',
      );
      expect(r, VerifyResult.ok);
      expect(auth.calls, contains('verify:icesi'));
      expect(session.verifiedUniversityId, 'icesi');
    });

    test('dominio incorrecto según el servidor → no se verifica', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      auth.verifyCode = 'domain_mismatch';
      final r = await session.verifyUniversityAsync(
        'icesi',
        'diego@icesi.edu.co',
      );
      expect(r, VerifyResult.domainMismatch);
      expect(session.verifiedUniversityId, isNull);
    });

    test('sin conexión → unavailable y nada cambia', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      auth.verifyCode = 'network';
      final r = await session.verifyUniversityAsync(
        'icesi',
        'diego@icesi.edu.co',
      );
      expect(r, VerifyResult.unavailable);
      expect(session.verifiedUniversityId, isNull);
    });

    test('un correo mal escrito ni siquiera llega al servidor', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      final r = await session.verifyUniversityAsync('icesi', 'no-es-correo');
      expect(r, VerifyResult.invalidEmail);
      expect(auth.calls, isEmpty);
    });
  });

  group('Direcciones: se guardan en la cuenta', () {
    test('al iniciar sesión se cargan las del servidor', () async {
      auth.serverAddresses.add(draft('Casa', id: _uuid1));
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      expect(session.data.addresses.map((a) => a.id), [_uuid1]);
      expect(session.data.defaultAddressId, _uuid1);
    });

    test('guardar usa el uuid del servidor, no un id local', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      final saved = await session.saveAddressAsync(draft('Oficina'));
      expect(saved, isNotNull);
      expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(saved!.id), isTrue);
      expect(session.addressById(saved.id)?.label, 'Oficina');
      expect(auth.calls.single, startsWith('save:Oficina'));
    });

    test('la primera dirección queda como principal', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      session.data.addresses.clear();
      session.data.defaultAddressId = null;
      final saved = await session.saveAddressAsync(draft('Casa'));
      expect(session.data.defaultAddressId, saved!.id);
      expect(auth.calls.single, endsWith('default=true'));
    });

    test('si el servidor falla no se guarda nada localmente', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      final before = session.data.addresses.length;
      auth.failWrites = true;
      final saved = await session.saveAddressAsync(draft('Nueva'));
      expect(saved, isNull);
      expect(session.data.addresses.length, before);
    });

    test('editar una dirección del servidor conserva su uuid', () async {
      auth.serverAddresses.add(draft('Casa', id: _uuid1));
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      final saved = await session.saveAddressAsync(draft('Casa 2', id: _uuid1));
      expect(saved!.id, _uuid1);
      expect(session.data.addresses, hasLength(1));
      expect(session.data.addresses.single.label, 'Casa 2');
    });

    test('una dirección local antigua se reemplaza por la del servidor', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      final local = session.saveAddress(draft('Vieja')); // id local «addr-N»
      final saved = await session.saveAddressAsync(local);
      expect(saved!.id, isNot(local.id));
      expect(session.addressById(local.id), isNull);
      expect(session.addressById(saved.id), isNotNull);
    });

    test('eliminar y cambiar la principal pasan por el servidor', () async {
      auth.serverAddresses
        ..add(draft('Casa', id: _uuid1))
        ..add(draft('Oficina', id: _uuid2));
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);

      expect(await session.setDefaultAddressAsync(_uuid2), isTrue);
      expect(session.data.defaultAddressId, _uuid2);
      expect(await session.deleteAddressAsync(_uuid1), isTrue);
      expect(session.addressById(_uuid1), isNull);
      expect(auth.calls, ['default:$_uuid2', 'delete:$_uuid1']);
    });

    test('si falla borrar o cambiar la principal, local queda igual', () async {
      auth.serverAddresses
        ..add(draft('Casa', id: _uuid1))
        ..add(draft('Oficina', id: _uuid2));
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      auth.failWrites = true;

      expect(await session.setDefaultAddressAsync(_uuid2), isFalse);
      expect(session.data.defaultAddressId, _uuid1);
      expect(await session.deleteAddressAsync(_uuid1), isFalse);
      expect(session.addressById(_uuid1), isNotNull);
    });
  });

  group('Gotas', () {
    test('syncGotas relee el saldo del servidor', () async {
      await session.loginAsync(kDemoBuyerEmail, kDemoPassword);
      auth.serverGotas = 999;
      await session.syncGotas();
      expect(session.gotas, 999);
    });
  });
}
