import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/address.dart';
import '../models/cart.dart';
import '../models/catalog.dart';
import '../models/order.dart';
import 'order_repository.dart';

/// Pedidos reales contra Supabase.
///
/// Cache en memoria para que las pantallas sigan leyendo de forma síncrona;
/// Realtime y cambios de sesión recargan y avisan a `OrderService`.
///
/// Las escrituras pasan por los RPC de `0003_functions.sql`: el estado local
/// es optimista y se reconcilia con la base.
class SupabaseOrderRepository implements OrderRepository {
  /// Usa el cliente de Supabase indicado.
  SupabaseOrderRepository(this._client);

  final sb.SupabaseClient _client;
  final List<Order> _orders = [];
  final _changes = StreamController<void>.broadcast();

  sb.RealtimeChannel? _channel;
  StreamSubscription<sb.AuthState>? _authSub;

  /// Emite cuando Realtime trae cambios.
  Stream<void> get changes => _changes.stream;

  /// Carga los pedidos, se suscribe a Realtime y devuelve el repositorio.
  static Future<SupabaseOrderRepository> load({
    sb.SupabaseClient? client,
  }) async {
    final repo = SupabaseOrderRepository(client ?? sb.Supabase.instance.client);
    await repo.refresh();
    repo._subscribe();
    return repo;
  }

  // ------------------------------------------------------------- Lectura

  /// Pedidos en caché (solo lectura).
  @override
  List<Order> get all => List.unmodifiable(_orders);

  /// Pedido por código o uuid.
  @override
  Order? byId(String id) {
    for (final o in _orders) {
      if (o.id == id || o.dbId == id) return o;
    }
    return null;
  }

  /// `true` si el pedido ya está en la caché.
  @override
  bool exists(String id) => byId(id) != null;

  /// Inserta un pedido local si no está repetido.
  @override
  void insert(Order order) {
    if (order.dbId != null && byId(order.dbId!) != null) return;
    _orders.insert(0, order);
  }

  /// Relee los pedidos visibles para el usuario (RLS decide cuáles).
  Future<void> refresh() async {
    try {
      final rows = await _client.from('orders').select();
      final items = await _client.from('order_items').select();
      final events = await _client.from('order_events').select();

      final itemsByOrder = <String, List<OrderLine>>{};
      for (final row in items) {
        final orderId = row['order_id'] as String?;
        if (orderId == null) continue;
        itemsByOrder.putIfAbsent(orderId, () => []).add(_line(row));
      }

      final eventsByOrder = <String, List<StatusEvent>>{};
      for (final row in events) {
        final orderId = row['order_id'] as String?;
        if (orderId == null) continue;
        eventsByOrder
            .putIfAbsent(orderId, () => [])
            .add(
              StatusEvent(
                _status(row['status'] as String?),
                _date(row['created_at']) ?? DateTime.now(),
                (row['actor_label'] as String?) ?? '',
              ),
            );
      }

      final incoming = rows
          .map(
            (row) => _order(
              row,
              itemsByOrder[row['id'] as String] ?? const [],
              eventsByOrder[row['id'] as String] ?? const [],
            ),
          )
          .toList();

      _merge(incoming);
    } on Object {
      // Sin conexión se conserva la última copia buena.
    }
  }

  /// Fusiona lo remoto con lo local conservando objetos vivos.
  void _merge(List<Order> incoming) {
    final byDbId = <String, Order>{
      for (final o in _orders)
        if (o.dbId != null) o.dbId!: o,
    };
    final result = <Order>[];

    for (final fresh in incoming) {
      final existing = fresh.dbId == null ? null : byDbId[fresh.dbId];
      if (existing == null) {
        result.add(fresh);
        continue;
      }
      // Se actualiza el objeto vivo para no romper rutas abiertas.
      existing.status = fresh.status;
      existing.courierId = fresh.courierId;
      existing.courierName = fresh.courierName;
      existing.rejectReason = fresh.rejectReason;
      existing.evidence = fresh.evidence;
      existing.deliveredAt = fresh.deliveredAt;
      existing.gotasCredited = fresh.gotasCredited;
      existing.history
        ..clear()
        ..addAll(fresh.history);
      result.add(existing);
    }

    // Pedidos locales que aún no se sincronizaron.
    for (final o in _orders) {
      if (o.dbId == null) result.add(o);
    }

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _orders
      ..clear()
      ..addAll(result);
    if (!_changes.isClosed) _changes.add(null);
  }

  // ------------------------------------------------------------ Escritura

  /// Crea el pedido en la base. Devuelve el uuid o el motivo del rechazo.
  Future<({String? id, String? error})> place(
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _client.rpc(
        'place_order',
        params: {'p_payload': payload},
      );
      final map = res is Map ? res : const {};
      if (map['result'] != 'ok') {
        return (id: null, error: map['result'] as String?);
      }
      final order = map['order'];
      return (
        id: order is Map ? order['id'] as String? : null,
        error: null,
      );
    } on Object {
      return (id: null, error: 'network');
    }
  }

  /// Ejecuta una transición; el estado se reconcilia con Realtime.
  Future<void> call(String fn, Map<String, dynamic> params) async {
    try {
      await _client.rpc(fn, params: params);
    } on Object {
      // Si falla, la próxima recarga corrige el estado local.
    }
  }

  /// Sube la evidencia al bucket privado y confirma la entrega.
  Future<void> deliver(
    Order order,
    String code,
    String? evidence,
    Uint8List? bytes,
  ) async {
    final dbId = order.dbId;
    if (dbId == null) return;

    var reference = evidence ?? '';
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final path = '$dbId/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await _client.storage
            .from('delivery-evidence')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const sb.FileOptions(contentType: 'image/jpeg'),
            );
        reference = path;
      } on Object {
        // Si la subida falla, se conserva la referencia local.
      }
    }

    await call('courier_deliver', {
      'p_order': dbId,
      'p_code': code,
      'p_evidence': reference,
    });
  }

  // ------------------------------------------------------------ Realtime

  /// Abre el canal de Realtime y escucha los cambios de sesión.
  void _subscribe() {
    try {
      _channel = _client
          .channel('biffy-orders')
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'orders',
            callback: (_) => _reload(),
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'order_events',
            callback: (_) => _reload(),
          )
          .subscribe();
    } on Object {
      // Realtime es opcional.
    }
    _authSub = _client.auth.onAuthStateChange.listen((_) => _reload());
  }

  /// Recarga los pedidos desde la base.
  Future<void> _reload() async {
    await refresh();
  }

  /// Libera el canal de Realtime y el stream de cambios.
  Future<void> dispose() async {
    await _authSub?.cancel();
    final channel = _channel;
    if (channel != null) {
      await _client.removeChannel(channel);
      _channel = null;
    }
    await _changes.close();
  }

  // --------------------------------------------------------------- Mapeo

  /// Convierte una fila de `orders` al modelo.
  static Order _order(
    Map<String, dynamic> row,
    List<OrderLine> lines,
    List<StatusEvent> events,
  ) {
    final snapshot = row['address_snapshot'];
    final address = Address(
      id: (snapshot is Map ? snapshot['id'] as String? : null) ?? '',
      label: (snapshot is Map ? snapshot['label'] as String? : null) ?? '',
      line: (snapshot is Map ? snapshot['line'] as String? : null) ?? '',
      details: (snapshot is Map ? snapshot['details'] as String? : null) ?? '',
      neighborhood:
          (snapshot is Map ? snapshot['neighborhood'] as String? : null) ?? '',
      reference:
          (snapshot is Map ? snapshot['reference'] as String? : null) ?? '',
      pointId: (snapshot is Map ? snapshot['point_id'] as String? : null) ?? '',
    );

    final order = Order(
      id: (row['code'] as String?) ?? (row['id'] as String),
      buyerId: row['buyer_id'] as String,
      buyerName: (row['buyer_name'] as String?) ?? '',
      restaurantId: row['branch_id'] as String,
      restaurantName: (row['restaurant_name'] as String?) ?? '',
      lines: lines,
      address: address,
      pointId: (row['point_id'] as String?) ?? address.pointId,
      payment: _payment(row['payment_method'] as String?),
      createdAt: _date(row['created_at']) ?? DateTime.now(),
      scheduledFor: _date(row['scheduled_for']),
      restaurantNote: (row['restaurant_note'] as String?) ?? '',
      subtotal: _int(row['subtotal']),
      campusDiscount: _int(row['campus_discount']),
      couponDiscount: _int(row['coupon_discount']),
      deliveryFee: _int(row['delivery_fee']),
      gotasUsed: _int(row['gotas_used']),
      tip: _int(row['tip']),
      total: _int(row['total']),
      deliveryCode: (row['delivery_code'] as String?) ?? '0000',
      pickupCode: (row['pickup_code'] as String?) ?? '',
      etaMin: _int(row['eta_min']),
      courierPay: _int(row['courier_pay']),
      distanceKm: ((row['distance_km'] as num?) ?? 0).toDouble(),
      couponId: row['coupon_id'] as String?,
      status: _status(row['status'] as String?),
    );

    order.dbId = row['id'] as String;
    order.courierId = row['courier_id'] as String?;
    order.courierName = row['courier_name'] as String?;
    order.rejectReason = row['reject_reason'] as String?;
    order.evidence = row['evidence_url'] as String?;
    order.gotasCredited = (row['gotas_credited'] as bool?) ?? false;
    order.deliveredAt = _date(row['delivered_at']);
    order.history
      ..clear()
      ..addAll(events);

    return order;
  }

  /// Convierte una fila de `order_items` al modelo.
  static OrderLine _line(Map<String, dynamic> row) {
    final selection = row['selection'];
    final sizeId = selection is Map ? selection['sizeId'] as String? : null;
    final sideId = selection is Map ? selection['sideId'] as String? : null;
    final extras = selection is Map ? selection['extraIds'] : null;
    final removed = selection is Map ? selection['removed'] : null;

    return OrderLine(
      dishId: (row['dish_id'] as String?) ?? '',
      name: (row['name'] as String?) ?? '',
      emoji: (row['emoji'] as String?) ?? '🍽️',
      qty: _int(row['qty']),
      unitPrice: _int(row['unit_price']),
      selection: DishSelection(
        sizeId: sizeId,
        sideId: sideId,
        extraIds: (extras as List?)?.map((e) => e.toString()).toSet() ?? {},
        removed: (removed as List?)?.map((e) => e.toString()).toSet() ?? {},
      ),
      detail: (row['detail'] as String?) ?? '',
      note: (row['note'] as String?) ?? '',
    );
  }

  /// Lee un número de la base como entero.
  static int _int(Object? value) => (value as num?)?.toInt() ?? 0;

  /// `timestamptz` llega en UTC; las pantallas comparan días y muestran horas
  /// en la zona del dispositivo.
  static DateTime? _date(Object? value) =>
      DateTime.tryParse((value as String?) ?? '')?.toLocal();

  /// Traduce el estado guardado al enum local.
  static OrderStatus _status(String? value) => switch (value) {
    'preparing' => OrderStatus.preparing,
    'ready' => OrderStatus.ready,
    'on_the_way' => OrderStatus.onTheWay,
    'delivered' => OrderStatus.delivered,
    'cancelled' => OrderStatus.cancelled,
    _ => OrderStatus.pending,
  };

  /// Traduce el medio de pago guardado al enum local.
  static PaymentMethod _payment(String? value) => switch (value) {
    'nequi' => PaymentMethod.nequi,
    'daviplata' => PaymentMethod.daviplata,
    'card' => PaymentMethod.card,
    'pse' => PaymentMethod.pse,
    _ => PaymentMethod.cash,
  };
}
