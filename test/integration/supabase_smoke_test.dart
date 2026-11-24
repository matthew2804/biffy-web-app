import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Prueba de humo contra el proyecto real de Supabase.
///
/// Solo se ejecuta si se pasan las credenciales; en `flutter test` normal se
/// salta, así que el CI no depende de la red.
///
/// ```bash
/// flutter test test/integration/supabase_smoke_test.dart \
///   --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
///   --dart-define=SUPABASE_KEY=sb_publishable_...
/// ```
void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_KEY');
  final enabled = url.isNotEmpty && key.isNotEmpty;

  group(
    'Supabase (proyecto real)',
    () {
      late SupabaseClient client;

      /// Inicia sesión con la cuenta demo del comprador.
      setUpAll(() async {
        client = SupabaseClient(url, key);
        final res = await client.auth.signInWithPassword(
          email: 'diego.demo@icesi.edu.co',
          password: 'biffy123',
        );
        expect(res.session, isNotNull);
      });

      /// Cierra la sesión al terminar.
      tearDownAll(() async {
        await client.auth.signOut();
      });

      test('el perfil trae rol, nombre y Gotas', () async {
        final uid = client.auth.currentUser!.id;
        final row = await client
            .from('profiles')
            .select('role, full_name, gotas')
            .eq('id', uid)
            .single();

        expect(row['role'], 'buyer');
        expect(row['full_name'], isNotEmpty);
        expect(row['gotas'], isA<int>());
      });

      test('el catálogo público tiene sedes y platos', () async {
        final branches = await client.from('branches').select('id').limit(5);
        final dishes = await client.from('dishes').select('id').limit(5);

        expect(branches, isNotEmpty);
        expect(dishes, isNotEmpty);
      });

      test('las recompensas están cargadas', () async {
        final boxes = await client
            .from('gotas_rewards')
            .select('code, gotas_cost')
            .eq('is_active', true);

        expect(boxes.length, greaterThanOrEqualTo(4));
      });

      test('las políticas RLS ocultan pedidos ajenos', () async {
        // Con RLS, el cliente solo ve los pedidos del comprador autenticado.
        final rows = await client.from('orders').select('buyer_id');
        final uid = client.auth.currentUser!.id;

        for (final row in rows) {
          expect(row['buyer_id'], uid);
        }
      });
    },
    skip: enabled
        ? false
        : 'Requiere --dart-define=SUPABASE_URL y SUPABASE_KEY',
  );
}
