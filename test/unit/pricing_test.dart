import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_catalog.dart';
import 'package:biffy/data/models/cart.dart';
import 'package:biffy/data/models/catalog.dart';
import 'package:biffy/data/models/user.dart';
import 'package:biffy/domain/pricing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final dishes = {for (final d in seedDishes()) d.id: d};
  final restaurants = {for (final r in seedRestaurants()) r.id: r};
  final qbano = restaurants['qbano-icesi']!;
  final especial = dishes['qbano-especial']!;
  final icesi = pointById('icesi-biblioteca');

  PricedLine line(String id, int qty, [DishSelection? s]) => PricedLine(
    dishes[id]!,
    CartItem(
      lineId: id,
      dishId: id,
      qty: qty,
      selection: s ?? defaultSelection(dishes[id]!),
    ),
  );

  group('Precios', () {
    test('precio unitario con tamaño, acompañante y extras', () {
      const sel = DishSelection(
        sizeId: 'qe-30',
        sideId: 'qe-papas',
        extraIds: {'qe-queso', 'qe-tocineta'},
      );
      expect(unitPrice(especial, sel), 24900 + 4500 + 3000 + 3500);
    });

    test('tamaño menor resta precio', () {
      expect(
        unitPrice(especial, const DishSelection(sizeId: 'qe-15')),
        24900 - 8000,
      );
    });

    test('subtotal suma líneas por cantidad', () {
      final t = computeTotals(
        lines: [line('qbano-especial', 2), line('qbano-limonada', 1)],
        restaurant: qbano,
        point: icesi,
      );
      expect(t.subtotal, 24900 * 2 + 6000);
    });

    test('total = subtotal - descuentos + tarifa + propina', () {
      final t = computeTotals(
        lines: [line('qbano-especial', 1)],
        restaurant: qbano,
        point: icesi,
        verifiedUniversityId: 'icesi',
        tip: TipOption.ten,
      );
      expect(t.campusDiscount, 2490);
      expect(t.deliveryFee, 1500);
      expect(t.tip, 2500);
      expect(t.total, 24900 - 2490 + 1500 + 2500);
    });

    test('descuento de campus solo para la universidad verificada', () {
      expect(campusDiscount(10000, qbano, null), 0);
      expect(campusDiscount(10000, qbano, 'unal'), 0);
      expect(campusDiscount(10000, qbano, 'icesi'), 1000);
    });

    test('tarifa menor dentro del mismo campus', () {
      expect(deliveryFee(qbano, icesi), 1500);
      expect(deliveryFee(restaurants['smash-lab']!, icesi), 3500);
    });

    test('propina como porcentaje redondeado a la centena', () {
      expect(tipAmount(24900, TipOption.none), 0);
      expect(tipAmount(24900, TipOption.five), 1200);
      expect(tipAmount(24900, TipOption.fifteen), 3700);
    });

    test('Gotas limitadas por saldo y por el valor a pagar', () {
      final t = computeTotals(
        lines: [line('qbano-limonada', 1)],
        restaurant: qbano,
        point: icesi,
        gotasBalance: 5000,
        useGotas: true,
      );
      expect(t.gotasUsed, 600);
      expect(t.gotasDiscount, 6000);
      expect(t.total, 1500);
    });

    test('cupón de envío gratis descuenta la tarifa', () {
      final t = computeTotals(
        lines: [line('qbano-limonada', 1)],
        restaurant: qbano,
        point: icesi,
        coupon: Coupon(id: 'c', title: 'Envío', kind: CouponKind.freeDelivery),
      );
      expect(t.couponDiscount, 1500);
      expect(t.total, 6000);
    });

    test('carrito vacío no cobra tarifa', () {
      expect(
        computeTotals(lines: [], restaurant: qbano, point: icesi).total,
        0,
      );
    });
  });

  group('Presupuesto', () {
    test('valida rango y pasos de \$1.000', () {
      expect(isValidBudget(5000), isTrue);
      expect(isValidBudget(50000), isTrue);
      expect(isValidBudget(4000), isFalse);
      expect(isValidBudget(51000), isFalse);
      expect(isValidBudget(12500), isFalse);
    });

    test('dentro del presupuesto', () {
      expect(isWithinBudget(18000, 20000), isTrue);
      expect(isWithinBudget(28900, 20000), isFalse);
    });
  });

  test('detalle legible de la selección', () {
    const sel = DishSelection(
      sizeId: 'qe-15',
      extraIds: {'qe-queso'},
      removed: {'Tomate'},
    );
    expect(
      selectionDetail(especial, sel),
      '15 cm · + Extra queso · sin tomate',
    );
  });

  test('las opciones inexistentes invalidan la selección guardada', () {
    expect(
      selectionStillValid(especial, const DishSelection(extraIds: {'nope'})),
      isFalse,
    );
    expect(
      selectionStillValid(especial, const DishSelection(sizeId: 'qe-30')),
      isTrue,
    );
  });

  test('Dish.orderable respeta agotado y límite de porciones', () {
    final d = Dish(
      id: 'x',
      restaurantId: 'r',
      name: 'X',
      description: '',
      price: 1000,
      emoji: '🍽️',
      category: 'cafe',
      section: 'S',
      portionLimit: 2,
    );
    expect(d.orderable, isTrue);
    d.soldToday = 2;
    expect(d.orderable, isFalse);
    d
      ..soldToday = 0
      ..soldOut = true;
    expect(d.orderable, isFalse);
  });
}
