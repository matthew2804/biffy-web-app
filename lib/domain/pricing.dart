import 'dart:math' as math;

import '../core/constants/catalog_constants.dart';
import '../data/models/cart.dart';
import '../data/models/catalog.dart';
import '../data/models/user.dart';

/// Selección inicial de un plato: primer tamaño, sin acompañante ni extras.
DishSelection defaultSelection(Dish d) =>
    DishSelection(sizeId: d.sizes.isEmpty ? null : d.sizes.first.id);

/// Precio unitario con tamaño, acompañante y extras.
int unitPrice(Dish d, DishSelection s) {
  var price = d.price;
  for (final o in d.sizes) {
    if (o.id == s.sizeId) price += o.price;
  }
  for (final o in d.sides) {
    if (o.id == s.sideId) price += o.price;
  }
  for (final o in d.extras) {
    if (s.extraIds.contains(o.id)) price += o.price;
  }
  return math.max(0, price);
}

int lineTotal(Dish d, DishSelection s, int qty) => unitPrice(d, s) * qty;

/// Texto legible de la personalización elegida.
String selectionDetail(Dish d, DishSelection s) {
  final parts = <String>[];
  for (final o in d.sizes) {
    if (o.id == s.sizeId && d.sizes.length > 1) parts.add(o.label);
  }
  for (final o in d.sides) {
    if (o.id == s.sideId) parts.add('con ${o.label.toLowerCase()}');
  }
  for (final o in d.extras) {
    if (s.extraIds.contains(o.id)) parts.add('+ ${o.label}');
  }
  for (final r in s.removed) {
    parts.add('sin ${r.toLowerCase()}');
  }
  return parts.join(' · ');
}

/// Valida que una selección guardada siga siendo válida para el plato actual.
bool selectionStillValid(Dish d, DishSelection s) {
  if (s.sizeId != null && !d.sizes.any((o) => o.id == s.sizeId)) return false;
  if (s.sideId != null && !d.sides.any((o) => o.id == s.sideId)) return false;
  for (final id in s.extraIds) {
    if (!d.extras.any((o) => o.id == id)) return false;
  }
  return true;
}

/// Propina como porcentaje del subtotal, redondeada a la centena.
int tipAmount(int subtotal, TipOption option) {
  if (option.percent == 0 || subtotal <= 0) return 0;
  return ((subtotal * option.percent / 100) / 100).round() * 100;
}

/// El descuento de campus aplica a estudiantes con verificación simulada de la
/// misma universidad del restaurante.
bool campusEligible(Restaurant r, String? verifiedUniversityId) =>
    r.campusId != null &&
    r.studentDiscount > 0 &&
    verifiedUniversityId != null &&
    verifiedUniversityId == r.campusId;

int campusDiscount(int subtotal, Restaurant r, String? verifiedUniversityId) =>
    campusEligible(r, verifiedUniversityId)
    ? (subtotal * r.studentDiscount).round()
    : 0;

/// Tarifa de entrega simulada: menor dentro del mismo campus.
int deliveryFee(Restaurant r, DeliveryPoint p) =>
    (r.campusId != null && r.campusId == p.campusId) ? 1500 : 3500;

bool isWithinBudget(int price, int budget) => price <= budget;

/// Valida el presupuesto de la encuesta ($5.000–$50.000 en pasos de $1.000).
bool isValidBudget(int budget) =>
    budget >= 5000 && budget <= 50000 && budget % 1000 == 0;

class PricedLine {
  const PricedLine(this.dish, this.item);
  final Dish dish;
  final CartItem item;
  int get total => lineTotal(dish, item.selection, item.qty);
}

class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.campusDiscount,
    required this.couponDiscount,
    required this.deliveryFee,
    required this.gotasUsed,
    required this.tip,
  });

  static const empty = CartTotals(
    subtotal: 0,
    campusDiscount: 0,
    couponDiscount: 0,
    deliveryFee: 0,
    gotasUsed: 0,
    tip: 0,
  );

  final int subtotal;
  final int campusDiscount;
  final int couponDiscount;
  final int deliveryFee;
  final int gotasUsed;
  final int tip;

  int get gotasDiscount => gotasUsed * kGotaValue;

  int get total => math.max(
    0,
    subtotal -
        campusDiscount -
        couponDiscount -
        gotasDiscount +
        deliveryFee +
        tip,
  );
}

CartTotals computeTotals({
  required List<PricedLine> lines,
  required Restaurant? restaurant,
  required DeliveryPoint point,
  String? verifiedUniversityId,
  int gotasBalance = 0,
  bool useGotas = false,
  Coupon? coupon,
  TipOption tip = TipOption.none,
}) {
  if (lines.isEmpty || restaurant == null) return CartTotals.empty;
  final subtotal = lines.fold<int>(0, (s, l) => s + l.total);
  final campus = campusDiscount(subtotal, restaurant, verifiedUniversityId);
  final fee = deliveryFee(restaurant, point);
  var couponOff = 0;
  if (coupon != null && !coupon.used) {
    couponOff = switch (coupon.kind) {
      CouponKind.freeDelivery => fee,
      CouponKind.fixed => math.min(coupon.amount, subtotal - campus),
    };
  }
  final payable = math.max(0, subtotal - campus - couponOff);
  final gotas = useGotas
      ? math.min(math.max(0, gotasBalance), payable ~/ kGotaValue)
      : 0;
  return CartTotals(
    subtotal: subtotal,
    campusDiscount: campus,
    couponDiscount: couponOff,
    deliveryFee: fee,
    gotasUsed: gotas,
    tip: tipAmount(subtotal, tip),
  );
}
