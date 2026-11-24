import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/entities/catalog.dart';
import '../../domain/entities/payment.dart';
import '../../domain/repositories/payment_repository.dart';
import '../../shared/adapters/payment_adapters.dart';

/// Pago real con Wompi a través de las Edge Functions y Realtime.
class SupabasePaymentRepository implements PaymentRepository {
  SupabasePaymentRepository({sb.SupabaseClient? client})
    : _client = client ?? sb.Supabase.instance.client;

  final sb.SupabaseClient _client;
  final StreamController<Payment> _changes =
      StreamController<Payment>.broadcast();
  sb.RealtimeChannel? _channel;
  Timer? _poll;
  String? _watching;

  @override
  bool get isRemote => true;

  /// Convierte la respuesta de `create-payment` en el resultado del dominio.
  PaymentResult _fromStart(
    Map<String, dynamic> map,
    PaymentMethod method,
  ) {
    final code = (map['result'] as String?) ?? 'server_error';
    if (code != 'ok') {
      return PaymentResult(
        code,
        expected: (map['expected'] as num?)?.toInt(),
      );
    }
    final id = (map['paymentId'] ?? '').toString();
    if (id.isEmpty) return const PaymentResult('server_error');
    return PaymentResult.ok(
      Payment(
        id: id,
        orderId: (map['orderId'] ?? '').toString(),
        amount: (map['amount'] as num?)?.toInt() ?? 0,
        method: method,
        status: PaymentStatus.pending,
        attempt: (map['attempt'] as num?)?.toInt() ?? 1,
        reference: (map['reference'] as String?) ?? '',
        checkoutUrl: map['checkoutUrl'] as String?,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<PaymentResult> start({
    required String orderId,
    required PaymentMethod method,
    int? amount,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'create-payment',
        body: {
          'orderId': orderId,
          'method': method.name,
          'amount': ?amount,
        },
      );
      final map = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
      // El pedido real lo conoce la app; se completa aquí para la UI.
      map['orderId'] = orderId;
      return _fromStart(map, method);
    } on sb.FunctionException catch (e) {
      final details = e.details is Map
          ? Map<String, dynamic>.from(e.details as Map)
          : const <String, dynamic>{};
      final code = (details['result'] as String?) ?? 'server_error';
      return PaymentResult(code, expected: (details['expected'] as num?)?.toInt());
    } on TimeoutException {
      return const PaymentResult('network');
    } on Object {
      return const PaymentResult('network');
    }
  }

  @override
  Future<PaymentResult> status(String orderId) async {
    try {
      final res = await _client.rpc(
        'payment_for_order',
        params: {'p_order': orderId},
      );
      if (res is! Map) return const PaymentResult('server_error');
      final map = Map<String, dynamic>.from(res);
      final code = (map['result'] as String?) ?? 'server_error';
      if (code != 'ok') return PaymentResult(code);
      final payment = paymentFromRpc(map);
      return payment == null
          ? const PaymentResult('not_found')
          : PaymentResult.ok(payment);
    } on sb.PostgrestException {
      return const PaymentResult('server_error');
    } on TimeoutException {
      return const PaymentResult('network');
    } on Object {
      return const PaymentResult('network');
    }
  }

  @override
  Future<PaymentResult> retry({
    required String orderId,
    required PaymentMethod method,
  }) => start(orderId: orderId, method: method);

  @override
  Future<PaymentResult> refund(
    String orderId, {
    String reason = 'Cancelación',
  }) async {
    try {
      final res = await _client.functions.invoke(
        'refund-payment',
        body: {'orderId': orderId, 'reason': reason},
      );
      final map = res.data is Map
          ? Map<String, dynamic>.from(res.data as Map)
          : const <String, dynamic>{};
      final code = (map['result'] as String?) ?? 'server_error';
      if (code != 'ok') return PaymentResult(code);
      final updated = await status(orderId);
      return updated.payment == null ? const PaymentResult('ok') : updated;
    } on TimeoutException {
      return const PaymentResult('network');
    } on Object {
      return const PaymentResult('network');
    }
  }

  @override
  Stream<Payment> watch(String orderId) {
    if (_watching != orderId) {
      _watching = orderId;
      _unsubscribe();
      try {
        _channel = _client
            .channel('biffy-payments-$orderId')
            .onPostgresChanges(
              event: sb.PostgresChangeEvent.all,
              schema: 'public',
              table: 'payments',
              filter: sb.PostgresChangeFilter(
                type: sb.PostgresChangeFilterType.eq,
                column: 'order_id',
                value: orderId,
              ),
              callback: (_) => unawaited(_emitLatest(orderId)),
            )
            .subscribe();
      } on Object {
        // Realtime es opcional: el sondeo de respaldo sigue funcionando.
      }
      // Respaldo por si Realtime no entrega el evento (red móvil, RLS…).
      _poll = Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_emitLatest(orderId)),
      );
      unawaited(_emitLatest(orderId));
    }
    return _changes.stream;
  }

  /// Consulta el último estado y lo publica en el stream.
  Future<void> _emitLatest(String orderId) async {
    final result = await status(orderId);
    final payment = result.payment;
    if (payment != null && !_changes.isClosed) _changes.add(payment);
  }

  /// Cierra el canal y el sondeo anteriores.
  void _unsubscribe() {
    _poll?.cancel();
    _poll = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(_client.removeChannel(channel));
  }

  @override
  void dispose() {
    _unsubscribe();
    unawaited(_changes.close());
  }
}
