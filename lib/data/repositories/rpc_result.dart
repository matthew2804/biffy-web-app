/// Respuesta normalizada de un RPC de pedidos (`jsonb` con `result`).
///
/// Los errores de transporte (sin red, timeout, 5xx) se representan con
/// códigos propios para que la UI nunca muestre una excepción cruda:
/// `network`, `server_error`, `upload_failed`, `not_synced`, `in_flight`.
class RpcResult {
  const RpcResult(this.code, [this.data = const {}]);

  /// Respuesta correcta.
  factory RpcResult.ok([Map<String, dynamic> data = const {}]) =>
      RpcResult('ok', data);

  /// Interpreta el `jsonb` que devuelven las funciones de `0003`/`0012`.
  factory RpcResult.fromJson(Object? json) {
    if (json is Map) {
      final map = Map<String, dynamic>.from(json);
      return RpcResult((map['result'] as String?) ?? 'server_error', map);
    }
    return const RpcResult('server_error');
  }

  final String code;
  final Map<String, dynamic> data;

  bool get ok => code == 'ok';

  /// Pedido devuelto por el RPC (columnas de `orders` en JSON), si lo hay.
  Map<String, dynamic>? get order {
    final o = data['order'];
    return o is Map ? Map<String, dynamic>.from(o) : null;
  }

  @override
  String toString() => 'RpcResult($code)';
}
