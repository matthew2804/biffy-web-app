import 'package:biffy/data/repositories/rpc_result.dart';
import 'package:biffy/domain/order_errors.dart';
import 'package:flutter_test/flutter_test.dart';

/// Todos los `result` que pueden devolver los RPC de pedidos
/// (`0003_functions.sql` + `0012_order_cycle.sql`) más los de transporte.
const _serverCodes = [
  'not_authenticated', 'no_profile', 'forbidden', 'branch_not_found',
  'branch_paused', 'address_not_found', 'point_not_found', 'out_of_zone',
  'empty_cart', 'invalid_qty', 'dish_not_found', 'dish_unavailable',
  'no_portions', 'invalid_option', 'subtotal_mismatch', 'total_mismatch',
  'insufficient_gotas', 'invalid_gotas', 'invalid_tip', 'invalid_payment',
  'coupon_unavailable', 'invalid_payload', 'not_found', 'invalid_state',
  'already_assigned', 'not_available', 'busy', 'out_of_range',
  'declined_before', 'wrong_code', 'missing_evidence',
  // transporte
  'network', 'upload_failed', 'not_synced',
];

void main() {
  group('orderErrorMessage', () {
    test('cada código tiene un mensaje en español, sin el código crudo', () {
      final generic = orderErrorMessage('algo_desconocido');
      for (final code in _serverCodes) {
        final m = orderErrorMessage(code);
        expect(m, isNotEmpty, reason: code);
        expect(m, isNot(contains('_')), reason: '$code muestra el código crudo');
        expect(m, isNot(generic), reason: '$code cae en el mensaje genérico');
        expect(m.length, greaterThan(10), reason: code);
      }
    });

    test('un código desconocido nunca expone nada técnico', () {
      final m = orderErrorMessage('pg_exception_42501');
      expect(m, isNot(contains('42501')));
      expect(m, contains('Intenta de nuevo'));
    });

    test('los desajustes de precio informan el total nuevo', () {
      for (final c in ['subtotal_mismatch', 'total_mismatch']) {
        expect(
          orderErrorMessage(c, {'expected': 21500}),
          contains(r'$21.500'),
          reason: c,
        );
      }
      expect(orderErrorMessage('total_mismatch'), contains('precios cambiaron'));
    });

    test('nombra el plato cuando el servidor lo informa', () {
      expect(
        orderErrorMessage('dish_unavailable', {'dish': 'Qbano Especial'}),
        'Qbano Especial ya no está disponible.',
      );
      expect(
        orderErrorMessage('no_portions', {'dish': 'Papas'}),
        contains('Papas'),
      );
      expect(orderErrorMessage('dish_unavailable'), isNot(contains('null')));
    });

    test('isTransportError separa red de reglas de negocio', () {
      for (final c in ['network', 'server_error', 'upload_failed']) {
        expect(isTransportError(c), isTrue, reason: c);
      }
      for (final c in ['wrong_code', 'forbidden', 'invalid_state', 'ok']) {
        expect(isTransportError(c), isFalse, reason: c);
      }
    });
  });

  group('RpcResult', () {
    test('lee el result del jsonb', () {
      final r = RpcResult.fromJson({
        'result': 'ok',
        'order': {'id': 'x', 'code': 'BF-1'},
      });
      expect(r.ok, isTrue);
      expect(r.order, containsPair('code', 'BF-1'));
    });

    test('una respuesta inesperada no lanza: es server_error', () {
      expect(RpcResult.fromJson(null).code, 'server_error');
      expect(RpcResult.fromJson('texto').code, 'server_error');
      expect(RpcResult.fromJson(<String, dynamic>{}).code, 'server_error');
    });

    test('un fallo no trae pedido', () {
      expect(RpcResult.fromJson({'result': 'forbidden'}).order, isNull);
    });
  });
}
