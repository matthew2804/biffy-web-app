import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Pruebas de RLS y perfiles de la HU-1 contra el proyecto real.
///
/// Solo se ejecutan si se pasan las credenciales publicables; en `flutter test`
/// normal se saltan, así que el CI no depende de la red.
///
/// ```bash
/// flutter test test/integration/hu1_supabase_test.dart \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_KEY=sb_publishable_...
/// ```
///
/// Las pruebas no dejan datos nuevos: solo inician sesión, leen y comprueban
/// que las escrituras prohibidas son rechazadas por RLS o por los triggers.
void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_KEY');
  final enabled = url.isNotEmpty && key.isNotEmpty;

  group(
    'HU-1 · perfiles y RLS con usuarios reales',
    () {
      late SupabaseClient buyer;
      late SupabaseClient courier;
      late SupabaseClient restaurant;
      late String buyerId;
      late String courierId;
      late String restaurantId;

      /// Inicia sesión con las tres cuentas demo, cada una en su cliente.
      setUpAll(() async {
        buyer = SupabaseClient(url, key);
        courier = SupabaseClient(url, key);
        restaurant = SupabaseClient(url, key);

        buyerId = (await buyer.auth.signInWithPassword(
          email: 'diego.demo@icesi.edu.co',
          password: 'biffy123',
        )).user!.id;
        courierId = (await courier.auth.signInWithPassword(
          email: 'andres.repartidor@demo.biffy.co',
          password: 'biffy123',
        )).user!.id;
        restaurantId = (await restaurant.auth.signInWithPassword(
          email: 'qbano@demo.biffy.co',
          password: 'biffy123',
        )).user!.id;
      });

      /// Cierra las tres sesiones al terminar.
      tearDownAll(() async {
        await buyer.auth.signOut();
        await courier.auth.signOut();
        await restaurant.auth.signOut();
      });

      test('cada cuenta ve su propio perfil y su rol', () async {
        final buyerRow = await buyer
            .from('profiles')
            .select('role, gotas')
            .eq('id', buyerId)
            .single();
        final courierRow = await courier
            .from('profiles')
            .select('role')
            .eq('id', courierId)
            .single();
        final restaurantRow = await restaurant
            .from('profiles')
            .select('role, business_id')
            .eq('id', restaurantId)
            .single();

        expect(buyerRow['role'], 'buyer');
        expect(buyerRow['gotas'], isA<int>());
        expect(courierRow['role'], 'courier');
        expect(restaurantRow['role'], 'restaurant');
        expect(restaurantRow['business_id'], isNotNull);
      });

      test('el comprador no puede leer el perfil del repartidor', () async {
        final rows = await buyer
            .from('profiles')
            .select('id')
            .eq('id', courierId);
        expect(rows, isEmpty);
      });

      test('el comprador no puede cambiarse el rol', () async {
        await expectLater(
          buyer
              .from('profiles')
              .update({'role': 'restaurant'})
              .eq('id', buyerId),
          throwsA(isA<PostgrestException>()),
        );
      });

      test('el comprador no puede cambiarse las Gotas', () async {
        await expectLater(
          buyer.from('profiles').update({'gotas': 999999}).eq('id', buyerId),
          throwsA(isA<PostgrestException>()),
        );
      });

      test('el comprador no puede cambiarse la verificación', () async {
        final row = await buyer
            .from('profiles')
            .select('verified')
            .eq('id', buyerId)
            .single();
        final current = (row['verified'] as bool?) ?? false;
        await expectLater(
          buyer
              .from('profiles')
              .update({'verified': !current})
              .eq('id', buyerId),
          throwsA(isA<PostgrestException>()),
        );
      });

      test('el comprador no puede insertar movimientos de Gotas', () async {
        await expectLater(
          buyer.from('gotas_ledger').insert({
            'user_id': buyerId,
            'amount': 5000,
            'reason': 'prueba RLS',
          }),
          throwsA(isA<PostgrestException>()),
        );
      });

      test('el comprador no puede crear una dirección para otro', () async {
        await expectLater(
          buyer.from('addresses').insert({
            'user_id': courierId,
            'label': 'Prueba RLS',
            'line': 'Calle falsa 123',
            'point_id': 'icesi-biblioteca',
          }),
          throwsA(isA<PostgrestException>()),
        );
      });

      test('cada usuario solo ve sus propias direcciones', () async {
        final buyerRows = await buyer.from('addresses').select('user_id');
        final courierRows = await courier.from('addresses').select('user_id');

        for (final row in buyerRows) {
          expect(row['user_id'], buyerId);
        }
        for (final row in courierRows) {
          expect(row['user_id'], courierId);
        }
        expect(buyerRows.map((r) => r['user_id']), isNot(contains(courierId)));
      });

      test('cada usuario solo ve sus preferencias y ajustes', () async {
        final prefs = await buyer.from('preferences').select('user_id');
        final settings = await buyer.from('app_settings').select('user_id');

        for (final row in prefs) {
          expect(row['user_id'], buyerId);
        }
        for (final row in settings) {
          expect(row['user_id'], buyerId);
        }
      });

      test('el comprador no puede escribir preferencias ajenas', () async {
        await expectLater(
          buyer.from('preferences').insert({'user_id': courierId}),
          throwsA(isA<PostgrestException>()),
        );
      });

      test('el comprador no puede escribir ajustes ajenos', () async {
        await expectLater(
          buyer.from('app_settings').insert({'user_id': courierId}),
          throwsA(isA<PostgrestException>()),
        );
      });

      test('verify_university rechaza un dominio distinto', () async {
        final res = await buyer.rpc(
          'verify_university',
          params: {
            'p_payload': {
              'university_id': 'icesi',
              'email': 'correo@gmail.com',
            },
          },
        );
        expect((res as Map)['result'], 'domain_mismatch');
      });

      test('verify_university rechaza una universidad desconocida', () async {
        final res = await buyer.rpc(
          'verify_university',
          params: {
            'p_payload': {
              'university_id': 'no-existe',
              'email': 'correo@icesi.edu.co',
            },
          },
        );
        expect((res as Map)['result'], 'unknown_university');
      });
    },
    skip: enabled
        ? false
        : 'Requiere --dart-define=SUPABASE_URL y SUPABASE_KEY',
  );
}
