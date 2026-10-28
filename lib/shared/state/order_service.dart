import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/constants/catalog_constants.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/format.dart';
import '../../data/models/address.dart';
import '../../data/models/cart.dart';
import '../../data/models/catalog.dart';
import '../../data/models/order.dart';
import '../../data/models/user.dart';
import '../../data/repositories/order_repository.dart';
import '../../data/repositories/supabase_order_repository.dart';
import '../../domain/catalog_rules.dart';
import '../../domain/order_rules.dart';
import '../../domain/pricing.dart';
import '../../domain/scheduling.dart';
import 'catalog_controller.dart';
import 'notification_center.dart';
import 'session_controller.dart';

/// Error de negocio al operar un pedido.
class OrderException implements Exception {
  /// Guarda el mensaje que verá el usuario.
  OrderException(this.message);
  final String message;
  /// Muestra solo el mensaje de la excepción.
  @override
  String toString() => message;
}

/// Datos necesarios para crear un pedido (desde el carrito o «Pedir ya»).
class CheckoutDraft {
  const CheckoutDraft({
    required this.buyer,
    required this.restaurant,
    required this.items,
    required this.address,
    required this.payment,
    this.scheduledFor,
    this.tip = TipOption.none,
    this.useGotas = false,
    this.coupon,
    this.restaurantNote = '',
  });

  final AppUser? buyer;
  final Restaurant? restaurant;
  final List<CartItem> items;
  final Address? address;
  final PaymentMethod payment;
  final DateTime? scheduledFor;
  final TipOption tip;
  final bool useGotas;
  final Coupon? coupon;
  final String restaurantNote;
}

/// Resultado de que un repartidor acepte una oferta.
enum CourierAcceptResult { ok, alreadyAssigned, notAvailable, busy, outOfRange }

/// Resultado de confirmar una entrega.
enum DeliveryResult { ok, wrongCode, missingEvidence, invalidState }

/// Servicio de pedidos compartido por comprador, restaurante y repartidor.
/// La sincronización se limita a esta instancia de la app (sin backend).
class OrderService extends ChangeNotifier {
  /// Conecta el servicio con repositorios, sesión y notificaciones.
  OrderService({
    required this.repo,
    required this.catalog,
    required this.session,
    required this.notifications,
    required this.clock,
    math.Random? random,
  }) : _rnd = random ?? math.Random() {
    final r = repo;
    if (r is SupabaseOrderRepository) {
      _changesSub = r.changes.listen((_) => notifyListeners());
    }
  }

  final OrderRepository repo;
  final CatalogController catalog;
  final SessionController session;
  final NotificationCenter notifications;
  final Clock clock;
  final math.Random _rnd;
  int _counter = 2041;
  StreamSubscription<void>? _changesSub;

  /// Repositorio remoto si hay Supabase configurado.
  SupabaseOrderRepository? get _remote =>
      repo is SupabaseOrderRepository ? repo as SupabaseOrderRepository : null;

  /// Cancela la suscripción a los cambios remotos.
  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  /// Réplica de una transición en la base (optimista, sin bloquear la UI).
  void _sync(String fn, Order o, [Map<String, dynamic> extra = const {}]) {
    final remote = _remote;
    final dbId = o.dbId;
    if (remote == null || dbId == null) return;
    remote.call(fn, {'p_order': dbId, ...extra});
  }

  /// Todos los pedidos visibles.
  List<Order> get all => repo.all;
  /// Pedido por código.
  Order? byId(String id) => repo.byId(id);

  /// Pedidos de un comprador.
  List<Order> forBuyer(String userId) =>
      all.where((o) => o.buyerId == userId).toList();

  /// Pedidos de todas las sedes de un negocio.
  List<Order> forBusiness(String businessId) {
    final ids = catalog.branchesOf(businessId).map((r) => r.id).toSet();
    return all.where((o) => ids.contains(o.restaurantId)).toList();
  }

  /// Pedido activo del repartidor, si tiene uno.
  Order? activeForCourier(String courierId) {
    for (final o in all) {
      if (o.courierId == courierId &&
          (o.status == OrderStatus.ready || o.status == OrderStatus.onTheWay)) {
        return o;
      }
    }
    return null;
  }

  /// Pedidos entregados por un repartidor.
  List<Order> deliveredBy(String courierId) => all
      .where(
        (o) => o.courierId == courierId && o.status == OrderStatus.delivered,
      )
      .toList();

  /// Pedidos listos sin repartidor, compatibles con zona y medio de transporte.
  List<Order> availableOffers({
    required String courierId,
    required CourierZone zone,
    String? universityId,
    Vehicle? vehicle,
  }) {
    return all.where((o) {
      if (o.status != OrderStatus.ready || o.courierId != null) return false;
      if (o.declinedBy.contains(courierId)) return false;
      if (vehicle != null && !courierCanTake(o, vehicle)) return false;
      if (zone == CourierZone.campus) {
        final r = catalog.restaurantById(o.restaurantId);
        return universityId != null && r?.campusId == universityId;
      }
      return true;
    }).toList();
  }

  // ------------------------------------------------------------ Compra

  /// Totales estimados del borrador sin crear el pedido.
  CartTotals preview(CheckoutDraft d) {
    final lines = [
      for (final i in d.items)
        if (catalog.dishById(i.dishId) case final dish?) PricedLine(dish, i),
    ];
    final point = d.address == null
        ? session.point
        : pointById(d.address!.pointId);
    final buyerData = d.buyer == null ? null : session.dataFor(d.buyer!.id);
    return computeTotals(
      lines: lines,
      restaurant: d.restaurant,
      point: point,
      verifiedUniversityId: buyerData?.verifiedUniversityId,
      gotasBalance: buyerData?.gotas ?? 0,
      useGotas: d.useGotas,
      coupon: d.coupon,
      tip: d.tip,
    );
  }

  /// Errores de validación en español; lista vacía si el pedido es válido.
  List<String> validate(CheckoutDraft d) {
    final errors = <String>[];
    final now = clock.now();
    if (d.buyer == null) errors.add('Inicia sesión para confirmar el pedido.');
    final r = d.restaurant;
    if (r == null || d.items.isEmpty) {
      errors.add('Tu carrito está vacío.');
      return errors;
    }
    if (d.address == null) {
      errors.add('Selecciona una dirección de entrega.');
    } else if (!isReachable(r, pointById(d.address!.pointId))) {
      errors.add('${r.name} no entrega en la zona de esa dirección.');
    }
    for (final i in d.items) {
      final dish = catalog.dishById(i.dishId);
      if (dish == null || !dish.orderable) {
        errors.add('${dish?.name ?? 'Un producto'} ya no está disponible.');
      } else if (dish.remainingPortions != null &&
          dish.remainingPortions! < i.qty) {
        errors.add(
          'Solo quedan ${dish.remainingPortions} porciones de ${dish.name}.',
        );
      }
    }
    if (d.scheduledFor == null) {
      if (!isOpenAt(r, now)) {
        errors.add('${r.name} está cerrado ahora. Programa tu pedido.');
      }
    } else if (!isValidSchedule(r, d.scheduledFor!, now)) {
      errors.add('La fecha y hora programadas ya no son válidas.');
    }
    if (d.coupon != null && d.coupon!.used) {
      errors.add('El cupón ya fue usado.');
    }
    return errors;
  }

  /// Genera un código de pedido libre.
  String _nextId() {
    String id;
    do {
      id = 'BF-${_counter++}';
    } while (repo.exists(id));
    return id;
  }

  /// Crea el pedido de demostración una sola vez. No realiza cobros reales.
  Order placeOrder(CheckoutDraft d) {
    final errors = validate(d);
    if (errors.isNotEmpty) throw OrderException(errors.first);
    final buyer = d.buyer!;
    final r = d.restaurant!;
    final address = d.address!;
    final point = pointById(address.pointId);
    final totals = preview(d);
    final km = distanceTo(r, point);
    final lines = <OrderLine>[];
    for (final i in d.items) {
      final dish = catalog.dishById(i.dishId)!;
      lines.add(
        OrderLine(
          dishId: dish.id,
          name: dish.name,
          emoji: dish.emoji,
          qty: i.qty,
          unitPrice: unitPrice(dish, i.selection),
          selection: i.selection,
          detail: selectionDetail(dish, i.selection),
          note: i.note,
        ),
      );
    }
    final order = Order(
      id: _nextId(),
      buyerId: buyer.id,
      buyerName: buyer.name,
      restaurantId: r.id,
      restaurantName: r.name,
      lines: lines,
      address: address,
      pointId: point.id,
      payment: d.payment,
      createdAt: clock.now(),
      scheduledFor: d.scheduledFor,
      restaurantNote: d.restaurantNote.trim(),
      subtotal: totals.subtotal,
      campusDiscount: totals.campusDiscount,
      couponDiscount: totals.couponDiscount,
      deliveryFee: totals.deliveryFee,
      gotasUsed: totals.gotasUsed,
      tip: totals.tip,
      total: totals.total,
      deliveryCode: fourDigitCode(_rnd),
      pickupCode: fourDigitCode(_rnd),
      etaMin: etaMinutes(r, point, prepMin: _maxPrep(lines, r)),
      courierPay: courierPayFor(km),
      distanceKm: double.parse(km.toStringAsFixed(2)),
      couponId: d.coupon?.id,
    );
    repo.insert(order);
    _remotePlace(order);
    if (totals.gotasUsed > 0) {
      session.spendGotas(buyer.id, totals.gotasUsed, 'Usadas en ${order.id}');
    }
    if (d.coupon != null) session.setCouponUsed(buyer.id, d.coupon!.id, true);
    for (final l in lines) {
      catalog.recordSale(l.dishId, l.qty);
    }
    final when = d.scheduledFor == null
        ? ''
        : ' para ${dateTimeLabel(d.scheduledFor!)}';
    notifications.push(
      title: 'Pedido ${order.id} creado',
      body: 'Pedido de demostración$when · sin cobros reales.',
      audience: 'user:${buyer.id}',
      route: '/pedido/${order.id}',
    );
    notifications.push(
      title: 'Nuevo pedido ${order.id}',
      body: '${order.itemsSummary}$when',
      audience: 'business:${r.businessId}',
      route: '/negocio/pedidos',
    );
    notifyListeners();
    return order;
  }

  /// Crea el pedido en Supabase y guarda su uuid. Si falla, queda local.
  void _remotePlace(Order order) {
    final remote = _remote;
    if (remote == null || order.address.id.isEmpty) return;

    final payload = <String, dynamic>{
      'branch_id': order.restaurantId,
      'address_id': order.address.id,
      'payment': order.payment.name,
      'lines': [
        for (final l in order.lines)
          {
            'dish_id': l.dishId,
            'qty': l.qty,
            'unit_price': l.unitPrice,
            'detail': l.detail,
            'note': l.note,
          },
      ],
      'subtotal': order.subtotal,
      'campus_discount': order.campusDiscount,
      'coupon_discount': order.couponDiscount,
      'delivery_fee': order.deliveryFee,
      'gotas_used': order.gotasUsed,
      'tip': order.tip,
      'total': order.total,
      'eta_min': order.etaMin,
      'courier_pay': order.courierPay,
      'distance_km': order.distanceKm,
      'restaurant_note': order.restaurantNote,
      if (order.scheduledFor != null)
        // En UTC con zona explícita: sin ella Postgres la toma como UTC.
        'scheduled_for': order.scheduledFor!.toUtc().toIso8601String(),
      if (order.couponId != null) 'coupon_id': order.couponId,
    };

    remote.place(payload).then((res) {
      if (res.id != null) {
        order.dbId = res.id;
        notifyListeners();
        return;
      }

      // El servidor rechazó el pedido (fuera de radio, campus, etc.).
      final message = switch (res.error) {
        'out_of_range' => 'La dirección está fuera del radio de entrega.',
        'outside_campus' => 'Esa sede solo entrega dentro del campus.',
        _ => 'No pudimos registrar el pedido en el servidor.',
      };
      // Se marca cancelado para no dejar un pedido fantasma en la lista.
      order.status = OrderStatus.cancelled;
      order.rejectReason = message;
      order.history.add(
        StatusEvent(OrderStatus.cancelled, clock.now(), 'Servidor'),
      );
      notifications.push(
        title: 'Pedido no registrado',
        body: message,
        audience: 'user:${order.buyerId}',
        route: '/pedido/${order.id}',
      );
      notifyListeners();
    });
  }

  /// Tiempo de preparación más alto de las líneas.
  int _maxPrep(List<OrderLine> lines, Restaurant r) {
    var m = 0;
    for (final l in lines) {
      final d = catalog.dishById(l.dishId);
      if (d != null && d.prepMin > m) m = d.prepMin;
    }
    return m == 0 ? r.prepMin : m;
  }

  /// Aplica una transición permitida y registra el evento.
  void _move(Order o, OrderStatus to, String by) {
    if (!canTransition(o.status, to)) {
      throw OrderException(
        'Transición no permitida: ${o.status.name} → ${to.name}',
      );
    }
    o.status = to;
    o.history.add(StatusEvent(to, clock.now(), by));
  }

  /// Negocio dueño de la sede del pedido.
  String? _businessOf(Order o) =>
      catalog.restaurantById(o.restaurantId)?.businessId;

  /// El comprador solo puede cancelar antes de que el restaurante acepte.
  bool cancelByBuyer(String id) {
    final o = byId(id);
    if (o == null || o.status != OrderStatus.pending) return false;
    _move(o, OrderStatus.cancelled, 'Comprador');
    o.rejectReason = 'Cancelado por el comprador';
    _refund(o);
    _sync('buyer_cancel', o);
    notifications.push(
      title: 'Pedido ${o.id} cancelado por el cliente',
      body: o.itemsSummary,
      audience: 'business:${_businessOf(o)}',
      route: '/negocio/pedidos',
    );
    notifyListeners();
    return true;
  }

  /// Devuelve Gotas y libera el cupón al cancelar.
  void _refund(Order o) {
    if (o.gotasUsed > 0) {
      session.creditGotas(o.buyerId, o.gotasUsed, 'Reembolso de ${o.id}');
    }
    if (o.couponId != null) {
      session.setCouponUsed(o.buyerId, o.couponId!, false);
    }
  }

  // ------------------------------------------------------- Restaurante

  /// El restaurante acepta y pasa el pedido a preparación.
  void restaurantAccept(String id) {
    final o = _require(id);
    _move(o, OrderStatus.preparing, 'Restaurante');
    _sync('restaurant_accept', o);
    notifications.push(
      title: 'Pedido aceptado por el restaurante',
      body: '${o.restaurantName} aceptó tu pedido ${o.id}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    notifications.push(
      title: 'Pedido en preparación 👩‍🍳',
      body: 'Tu pedido ${o.id} se está preparando.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    notifyListeners();
  }

  /// El restaurante rechaza con un motivo y reembolsa.
  void restaurantReject(String id, String reason) {
    final o = _require(id);
    if (reason.trim().isEmpty) {
      throw OrderException('Indica el motivo del rechazo.');
    }
    _move(o, OrderStatus.cancelled, 'Restaurante');
    o.rejectReason = reason.trim();
    _refund(o);
    _sync('restaurant_reject', o, {'p_reason': o.rejectReason!});
    notifications.push(
      title: 'Pedido ${o.id} rechazado',
      body: 'Motivo: ${o.rejectReason}. No se realizó ningún cobro.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    notifyListeners();
  }

  /// Marca el pedido listo y publica la oferta a repartidores.
  void markReady(String id) {
    final o = _require(id);
    _move(o, OrderStatus.ready, 'Restaurante');
    _sync('restaurant_ready', o);
    notifications.push(
      title: 'Pedido listo 🛍️',
      body:
          '${o.restaurantName} terminó tu pedido ${o.id}. Buscando repartidor.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    notifications.push(
      title: 'Oferta disponible · ${cop(o.courierPay)}',
      body: '${o.restaurantName} → ${o.address.label} (${o.distanceKm} km).',
      audience: 'couriers',
      route: '/repartidor/oferta/${o.id}',
    );
    notifyListeners();
  }

  // -------------------------------------------------------- Repartidor

  /// Asignación atómica: si otro repartidor ya lo tomó, falla.
  CourierAcceptResult courierAccept(
    String id,
    AppUser courier, {
    Vehicle? vehicle,
  }) {
    final o = byId(id);
    if (o == null || o.status != OrderStatus.ready) {
      return CourierAcceptResult.notAvailable;
    }
    if (o.courierId != null) return CourierAcceptResult.alreadyAssigned;
    if (activeForCourier(courier.id) != null) return CourierAcceptResult.busy;
    if (vehicle != null && !courierCanTake(o, vehicle)) {
      return CourierAcceptResult.outOfRange;
    }
    o.courierId = courier.id;
    o.courierName = courier.name;
    o.history.add(StatusEvent(o.status, clock.now(), 'Repartidor asignado'));
    notifications.push(
      title: 'Repartidor asignado 🛵',
      body: '${courier.name} recogerá tu pedido ${o.id}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    notifications.push(
      title: 'Pedido ${o.id} asignado',
      body: 'Ve a ${o.restaurantName} y muestra el código ${o.pickupCode}.',
      audience: 'courier:${courier.id}',
      route: '/repartidor/recogida/${o.id}',
    );
    notifications.push(
      title: 'Repartidor asignado a ${o.id}',
      body: '${courier.name} va en camino a recoger.',
      audience: 'business:${_businessOf(o)}',
      route: '/negocio/pedidos',
    );
    _sync('courier_accept', o);
    notifyListeners();
    return CourierAcceptResult.ok;
  }

  /// Registra que el repartidor rechazó la oferta.
  void courierDecline(String id, String courierId) {
    final o = byId(id);
    if (o != null) {
      o.declinedBy.add(courierId);
      _sync('courier_decline', o);
    }
    notifyListeners();
  }

  /// Requiere los tres checks de recogida.
  bool confirmPickup(
    String id,
    String courierId, {
    required bool codeValidated,
    required bool bagSealed,
    required bool productsVerified,
  }) {
    final o = byId(id);
    if (o == null ||
        o.courierId != courierId ||
        o.status != OrderStatus.ready) {
      return false;
    }
    if (!(codeValidated && bagSealed && productsVerified)) return false;
    _move(o, OrderStatus.onTheWay, 'Repartidor');
    _sync('courier_pickup', o);
    notifications.push(
      title: 'Pedido en camino 🛵',
      body:
          '${o.courierName} recogió tu pedido ${o.id}. Ten listo el código ${o.deliveryCode}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    notifyListeners();
    return true;
  }

  /// Confirma la entrega con código y evidencia.
  DeliveryResult completeDelivery(
    String id,
    String courierId,
    String code,
    String? evidence, {
    Uint8List? evidenceBytes,
  }) {
    final o = byId(id);
    if (o == null ||
        o.courierId != courierId ||
        o.status != OrderStatus.onTheWay) {
      return DeliveryResult.invalidState;
    }
    if (!validateDeliveryCode(o, code)) return DeliveryResult.wrongCode;
    if (!validateEvidence(evidence)) return DeliveryResult.missingEvidence;
    _move(o, OrderStatus.delivered, 'Repartidor');
    o.evidence = evidence;
    o.deliveredAt = clock.now();
    final remote = _remote;
    if (remote != null && o.dbId != null) {
      // Sube la foto (si hay) y luego confirma la entrega por RPC.
      remote.deliver(o, code, evidence, evidenceBytes);
    }
    if (!o.gotasCredited) {
      o.gotasCredited = true;
      final earned = o.subtotal ~/ 1000;
      session.creditGotas(o.buyerId, earned, 'Pedido ${o.id} entregado');
    }
    notifications.push(
      title: 'Pedido entregado ✅',
      body: '¡Buen provecho! Ganaste ${o.subtotal ~/ 1000} Gotas con ${o.id}.',
      audience: 'user:${o.buyerId}',
      route: '/pedido/${o.id}',
    );
    notifications.push(
      title: 'Pedido ${o.id} entregado',
      body: 'Entregado por ${o.courierName}.',
      audience: 'business:${_businessOf(o)}',
      route: '/negocio/pedidos',
    );
    notifyListeners();
    return DeliveryResult.ok;
  }

  /// Devuelve el pedido o lanza error si no existe.
  Order _require(String id) {
    final o = byId(id);
    if (o == null) throw OrderException('Pedido no encontrado');
    return o;
  }

  /// Inserta pedidos semilla (solo datos de demostración).
  void insertSeed(Order o) => repo.insert(o);
}
