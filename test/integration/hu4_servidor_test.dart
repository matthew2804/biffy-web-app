import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// HU-4 contra el proyecto real: tres clientes (como tres dispositivos)
/// comprueban las reglas de 0027 y que los avisos llegan por Realtime.
///
/// Crea un pedido real y lo cancela al final (devuelve porciones y Gotas);
/// deja la disponibilidad de Andrés y el ajuste de Diego como estaban.
///
/// ```bash
/// flutter test test/integration/hu4_servidor_test.dart \
///   --dart-define-from-file=env.json
/// ```
void main() {
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_KEY');
  final enabled = url.isNotEmpty && key.isNotEmpty;

  /// Inicia sesión con una cuenta demo en un cliente propio.
  Future<SupabaseClient> login(String email) async {
    final c = SupabaseClient(url, key);
    await c.auth.signInWithPassword(email: email, password: 'biffy123');
    return c;
  }

  group(
    'HU-4 · servidor y avisos entre dispositivos',
    () {
      late SupabaseClient buyer;
      late SupabaseClient restaurant;
      late SupabaseClient courier;
      late String branchId;
      late String dishId;
      late String addressId;
      bool? courierWasOnline;
      bool? demoLunchBefore;
      String? orderId;

      /// Los tres roles inician sesión y se fijan los datos del pedido.
      setUpAll(() async {
        buyer = await login('diego.demo@icesi.edu.co');
        restaurant = await login('qbano@demo.biffy.co');
        courier = await login('andres.repartidor@demo.biffy.co');

        final branch = await restaurant
            .from('branches')
            .select('id, business_id, businesses!inner(owner_id)')
            .eq('businesses.owner_id', restaurant.auth.currentUser!.id)
            .isFilter('deleted_at', null)
            .limit(1)
            .single();
        branchId = branch['id'] as String;

        final dish = await buyer
            .from('dishes')
            .select('id')
            .eq('branch_id', branchId)
            .eq('active', true)
            .eq('sold_out', false)
            .isFilter('deleted_at', null)
            .isFilter('portion_limit', null)
            .limit(1)
            .single();
        dishId = dish['id'] as String;

        final address = await buyer
            .from('addresses')
            .select('id')
            .eq('user_id', buyer.auth.currentUser!.id)
            .isFilter('deleted_at', null)
            .limit(1)
            .single();
        addressId = address['id'] as String;

        final c = await courier
            .from('courier_profiles')
            .select('online')
            .eq('user_id', courier.auth.currentUser!.id)
            .single();
        courierWasOnline = c['online'] as bool?;

        final s = await buyer
            .from('app_settings')
            .select('demo_lunch')
            .eq('user_id', buyer.auth.currentUser!.id)
            .maybeSingle();
        demoLunchBefore = s?['demo_lunch'] as bool?;
        // El pedido debe poder entrar a cualquier hora en que corra la prueba.
        await buyer.from('app_settings').upsert({
          'user_id': buyer.auth.currentUser!.id,
          'demo_lunch': true,
        });
      });

      /// Cancela el pedido si quedó vivo y restaura lo que se tocó.
      tearDownAll(() async {
        if (orderId != null) {
          await buyer.rpc('buyer_cancel', params: {'p_order': orderId});
        }
        await buyer.from('app_settings').upsert({
          'user_id': buyer.auth.currentUser!.id,
          'demo_lunch': demoLunchBefore ?? false,
        });
        await courier.rpc(
          'courier_set_online',
          params: {'p_online': courierWasOnline ?? false},
        );
        for (final c in [buyer, restaurant, courier]) {
          await c.auth.signOut();
          await c.dispose();
        }
      });

      /// Lee los repartidores cercanos que publica la sede.
      Future<int> nearby() async {
        final row = await buyer
            .from('branches')
            .select('couriers_nearby')
            .eq('id', branchId)
            .single();
        return (row['couriers_nearby'] as num).toInt();
      }

      /// Lee las porciones vendidas hoy del plato.
      Future<int> soldToday() async {
        final row = await buyer
            .from('dishes')
            .select('sold_today')
            .eq('id', dishId)
            .single();
        return (row['sold_today'] as num).toInt();
      }

      test('conectar y desconectar al repartidor cambia la sede', () async {
        await courier.rpc('courier_set_online', params: {'p_online': false});
        final without = await nearby();

        final res = await courier.rpc(
          'courier_set_online',
          params: {'p_online': true, 'p_zone': 'general'},
        );
        expect(res['result'], 'ok');
        expect(await nearby(), without + 1);
      });

      test(
        'el cliente no puede escribir couriers_nearby ni sold_today',
        () async {
          final before = await soldToday();
          final nearbyBefore = await nearby();
          await restaurant
              .from('dishes')
              .update({'sold_today': 999})
              .eq('id', dishId);
          await restaurant
              .from('branches')
              .update({'couriers_nearby': 99})
              .eq('id', branchId);
          expect(await soldToday(), before);
          expect(await nearby(), nearbyBefore);
        },
      );

      test('el pedido del comprador le llega al restaurante en vivo', () async {
        final received = Completer<Map<String, dynamic>>();
        final channel = restaurant
            .channel('hu4-test-${DateTime.now().millisecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: restaurant.auth.currentUser!.id,
              ),
              callback: (p) {
                if (!received.isCompleted) received.complete(p.newRecord);
              },
            );
        final subscribed = Completer<void>();
        channel.subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed &&
              !subscribed.isCompleted) {
            subscribed.complete();
          }
        });
        await subscribed.future.timeout(const Duration(seconds: 15));
        // `subscribed` llega antes de que el servidor registre la escucha de
        // la tabla; sin esta pausa el primer INSERT se puede perder.
        await Future<void>.delayed(const Duration(seconds: 3));

        final sold = await soldToday();
        final res = await buyer.rpc(
          'place_order',
          params: {
            'p_payload': {
              'branch_id': branchId,
              'address_id': addressId,
              'payment': 'cash',
              'lines': [
                {'dish_id': dishId, 'qty': 1},
              ],
              'client_key': 'hu4-test-${DateTime.now().millisecondsSinceEpoch}',
            },
          },
        );
        expect(res['result'], 'ok', reason: '$res');
        orderId = (res['order'] as Map)['id'] as String;

        final notice = await received.future.timeout(
          const Duration(seconds: 20),
        );
        expect(notice['order_id'], orderId);
        expect(notice['title'], isNotEmpty);
        expect(await soldToday(), sold + 1);

        await restaurant.removeChannel(channel);
      });

      test('cancelar devuelve las porciones del día', () async {
        expect(orderId, isNotNull);
        final sold = await soldToday();
        final res = await buyer.rpc(
          'buyer_cancel',
          params: {'p_order': orderId},
        );
        expect(res['result'], 'ok', reason: '$res');
        orderId = null;
        expect(await soldToday(), sold - 1);
      });
    },
    skip: enabled
        ? false
        : 'Sin SUPABASE_URL/SUPABASE_KEY: prueba contra el proyecto real omitida.',
  );
}
