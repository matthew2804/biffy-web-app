import 'dart:math' as math;

import '../core/utils/format.dart';
import '../data/models/catalog.dart';
import '../data/models/order.dart';
import '../data/models/user.dart';

/// Transiciones permitidas. El restaurante nunca marca «entregado»: esa
/// transición pertenece al flujo del repartidor.
const Map<OrderStatus, Set<OrderStatus>> kAllowedTransitions = {
  OrderStatus.pending: {OrderStatus.preparing, OrderStatus.cancelled},
  OrderStatus.preparing: {OrderStatus.ready},
  OrderStatus.ready: {OrderStatus.onTheWay},
  OrderStatus.onTheWay: {OrderStatus.delivered},
  OrderStatus.delivered: {},
  OrderStatus.cancelled: {},
};

/// Indica si el pedido puede pasar de un estado a otro.
bool canTransition(OrderStatus from, OrderStatus to) =>
    kAllowedTransitions[from]!.contains(to);

/// Tarifa Biffy simulada sobre el pago al repartidor.
const kBiffyFeeRate = 0.10;

/// Pago estimado al repartidor según la distancia (mínimo $4.500).
int courierPayFor(double km) {
  final raw = 3500 + km * 1500;
  return math.max(4500, (raw / 100).round() * 100);
}

/// Genera el código de entrega de cuatro dígitos.
String fourDigitCode(math.Random rnd) => (1000 + rnd.nextInt(9000)).toString();

/// Valida el código de entrega que ingresa el comprador.
bool validateDeliveryCode(Order order, String input) =>
    input.trim() == order.deliveryCode;

/// Indica si hay una foto o evidencia de entrega válida.
bool validateEvidence(String? evidence) =>
    evidence != null && evidence.trim().isNotEmpty;

/// Un repartidor puede tomar el pedido si su medio cubre la distancia.
bool courierCanTake(Order order, Vehicle vehicle) =>
    order.distanceKm <= vehicle.maxKm;

/// Resumen de ganancias del repartidor en un periodo.
class CourierEarnings {
  const CourierEarnings({
    required this.deliveries,
    required this.gross,
    required this.tips,
  });

  final int deliveries;
  final int gross;
  final int tips;

  /// Comisión que retiene Biffy sobre la ganancia bruta.
  int get biffyFee => (gross * kBiffyFeeRate).round();
  /// Ganancia neta del repartidor con propinas y comisión descontada.
  int get net => gross - biffyFee + tips;
}

/// Calcula las ganancias de los pedidos entregados.
CourierEarnings computeEarnings(Iterable<Order> delivered) {
  var gross = 0, tips = 0, n = 0;
  for (final o in delivered) {
    if (o.status != OrderStatus.delivered) continue;
    n++;
    gross += o.courierPay;
    tips += o.tip;
  }
  return CourierEarnings(deliveries: n, gross: gross, tips: tips);
}

/// Metas diarias de demostración (los bonos no se liquidan).
const kCourierGoals = <(int deliveries, int bonus)>[
  (3, 5000),
  (6, 12000),
  (10, 25000),
];

/// Producto más vendido con su cantidad e ingresos.
class TopProduct {
  const TopProduct(this.name, this.qty, this.revenue);
  final String name;
  final int qty;
  final int revenue;
}

/// Métricas del negocio calculadas a partir de sus pedidos.
class RestaurantMetrics {
  const RestaurantMetrics({
    required this.salesToday,
    required this.salesTotal,
    required this.ordersTotal,
    required this.newCount,
    required this.preparingCount,
    required this.readyCount,
    required this.completedCount,
    required this.rejectedCount,
    required this.activeProducts,
    required this.salesByBranch,
    required this.topProducts,
  });

  final int salesToday;
  final int salesTotal;
  final int ordersTotal;
  final int newCount;
  final int preparingCount;
  final int readyCount;
  final int completedCount;
  final int rejectedCount;
  final int activeProducts;
  final Map<String, int> salesByBranch;
  final List<TopProduct> topProducts;

  /// Pedidos aceptados: total menos nuevos y rechazados.
  int get acceptedCount => ordersTotal - newCount - rejectedCount;
  /// Ticket promedio por pedido aceptado.
  int get averageTicket => acceptedCount == 0 ? 0 : salesTotal ~/ acceptedCount;
}

/// Métricas derivadas exclusivamente de los pedidos y productos locales.
RestaurantMetrics computeMetrics({
  required List<Order> orders,
  required List<Dish> dishes,
  required List<Restaurant> branches,
  required DateTime now,
}) {
  var salesToday = 0, salesTotal = 0;
  var nNew = 0, nPrep = 0, nReady = 0, nDone = 0, nRejected = 0;
  final byBranch = <String, int>{for (final b in branches) b.branchName: 0};
  final top = <String, (int, int)>{};
  for (final o in orders) {
    switch (o.status) {
      case OrderStatus.pending:
        nNew++;
        continue;
      case OrderStatus.cancelled:
        nRejected++;
        continue;
      case OrderStatus.preparing:
        nPrep++;
      case OrderStatus.ready:
        nReady++;
      case OrderStatus.onTheWay || OrderStatus.delivered:
        nDone++;
    }
    salesTotal += o.restaurantRevenue;
    if (sameDay(o.createdAt, now)) salesToday += o.restaurantRevenue;
    final branch = branches
        .where((b) => b.id == o.restaurantId)
        .map((b) => b.branchName)
        .firstOrNull;
    if (branch != null) {
      byBranch[branch] = (byBranch[branch] ?? 0) + o.restaurantRevenue;
    }
    for (final l in o.lines) {
      final prev = top[l.name] ?? (0, 0);
      top[l.name] = (prev.$1 + l.qty, prev.$2 + l.total);
    }
  }
  final topList =
      top.entries.map((e) => TopProduct(e.key, e.value.$1, e.value.$2)).toList()
        ..sort((a, b) => b.qty.compareTo(a.qty));
  return RestaurantMetrics(
    salesToday: salesToday,
    salesTotal: salesTotal,
    ordersTotal: orders.length,
    newCount: nNew,
    preparingCount: nPrep,
    readyCount: nReady,
    completedCount: nDone,
    rejectedCount: nRejected,
    activeProducts: dishes.where((d) => d.active && !d.soldOut).length,
    salesByBranch: byBranch,
    topProducts: topList.take(5).toList(),
  );
}
