import 'package:biffy/data/models/user.dart';
import 'package:biffy/data/repositories/supabase_auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Prueba de registro real de las HU-1 con cuentas nuevas.
///
/// Crea tres cuentas QA (comprador, repartidor y restaurante). Se ejecuta solo
/// si además del URL y la clave se pasa `HU1_REGISTRATION=1`, para que no se
/// creen cuentas en cada corrida del CI.
///
/// ```bash
/// flutter test test/integration/hu1_registration_test.dart \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_KEY=sb_publishable_... \
///   --dart-define=HU1_REGISTRATION=1
/// ```
///
/// Limpieza posterior (SQL Editor, borra en cascada perfiles y direcciones):
/// ```sql
/// delete from auth.users where email like 'hu1.qa.%@demo.biffy.co';
/// ```
void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_KEY');
  const run = String.fromEnvironment('HU1_REGISTRATION');
  final enabled = url.isNotEmpty && key.isNotEmpty && run == '1';

  group(
    'HU-1 · registro real de cuentas',
    () {
      /// Inicia sesión o registra la cuenta QA indicada.
      Future<SupabaseClient> ensureAccount(String email, String role) async {
        final client = SupabaseClient(
          url,
          key,
          authOptions: const AuthClientOptions(
            authFlowType: AuthFlowType.implicit,
          ),
        );
        try {
          final res = await client.auth.signUp(
            email: email,
            password: 'biffy123',
            data: {'full_name': 'QA HU-1', 'role': role},
          );
          if (res.session == null) {
            await client.auth.signInWithPassword(
              email: email,
              password: 'biffy123',
            );
          }
        } on AuthException catch (e) {
          if (!e.message.toLowerCase().contains('already')) rethrow;
          await client.auth.signInWithPassword(
            email: email,
            password: 'biffy123',
          );
        }
        return client;
      }

      /// Comprueba la fila de perfil y la bienvenida única de 450 Gotas.
      Future<void> expectProfile(
        SupabaseClient client,
        String expectedRole,
      ) async {
        final id = client.auth.currentUser!.id;
        final profile = await client
            .from('profiles')
            .select('role, gotas')
            .eq('id', id)
            .single();
        expect(profile['role'], expectedRole);
        expect(profile['gotas'], isA<int>());

        final welcome = await client
            .from('gotas_ledger')
            .select('amount, reason')
            .eq('user_id', id)
            .eq('reason', 'Bienvenida a Biffy');
        expect(welcome, hasLength(1));
        expect((welcome.first['amount'] as num).toInt(), 450);
      }

      test('el comprador nuevo queda con rol buyer y 450 Gotas', () async {
        final client = await ensureAccount(
          'hu1.qa.comprador@demo.biffy.co',
          'buyer',
        );
        addTearDown(client.auth.signOut);
        await expectProfile(client, 'buyer');
      });

      test('el repartidor queda con rol courier, 450 Gotas y perfil', () async {
        final client = await ensureAccount(
          'hu1.qa.repartidor@demo.biffy.co',
          'courier',
        );
        addTearDown(client.auth.signOut);
        await expectProfile(client, 'courier');

        final id = client.auth.currentUser!.id;
        final repo = SupabaseAuthRepository(client: client);
        await repo.saveCourierProfile(
          id,
          const CourierProfile(
            fullName: 'QA HU-1',
            docType: 'CC',
            docNumber: '1000000009',
            phone: '300 000 0009',
            vehicle: Vehicle.bicycle,
            contactEmail: 'hu1.qa.repartidor@demo.biffy.co',
          ),
        );

        final row = await client
            .from('courier_profiles')
            .select('full_name, vehicle')
            .eq('user_id', id)
            .single();
        expect(row['full_name'], 'QA HU-1');
        expect(row['vehicle'], 'bicycle');
      });

      test('el restaurante nuevo queda con rol restaurant', () async {
        final client = await ensureAccount(
          'hu1.qa.restaurante@demo.biffy.co',
          'restaurant',
        );
        addTearDown(client.auth.signOut);
        await expectProfile(client, 'restaurant');
      });

      test(
        'el restaurante crea negocio y sede con register_business',
        () async {
          final client = await ensureAccount(
            'hu1.qa.restaurante@demo.biffy.co',
            'restaurant',
          );
          addTearDown(client.auth.signOut);
          final id = client.auth.currentUser!.id;
          final profile = await client
              .from('profiles')
              .select('business_id')
              .eq('id', id)
              .single();

          var businessId = profile['business_id'] as String?;
          businessId ??= await SupabaseAuthRepository(client: client)
              .registerBusiness({
                'brand': 'QA HU-1',
                'legal_name': 'QA HU-1 SAS',
                'nit': '900000000-1',
                'cuisine': 'almuerzo',
                'description': 'Negocio temporal de pruebas de la HU-1',
                'owner_name': 'QA HU-1',
                'owner_doc': '1000000009',
                'owner_phone': '300 000 0009',
                'owner_email': 'hu1.qa.restaurante@demo.biffy.co',
                'branches': [
                  {
                    'name': 'QA HU-1',
                    'branch_name': 'Sede QA',
                    'address': 'Calle de prueba 123',
                    'city': 'Cali',
                    'lat': 3.3415,
                    'lng': -76.5300,
                    'radius_km': 1,
                    'open_hour': 8,
                    'close_hour': 20,
                    'campus_id': null,
                  },
                ],
              });

          expect(businessId, isNotNull);
          final saved = await client
              .from('profiles')
              .select('business_id')
              .eq('id', id)
              .single();
          expect(saved['business_id'], businessId);

          final branches = await client
              .from('branches')
              .select('id, name')
              .eq('business_id', businessId!);
          expect(branches, isNotEmpty);

          // La sede se oculta del catálogo público al terminar la prueba.
          await client
              .from('branches')
              .update({
                'paused': true,
                'deleted_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', branches.first['id'] as String);
        },
      );
    },
    skip: enabled
        ? false
        : 'Requiere SUPABASE_URL, SUPABASE_KEY y HU1_REGISTRATION=1',
  );
}
