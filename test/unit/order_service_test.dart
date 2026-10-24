import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/data/models/cart.dart';
import 'package:biffy/data/models/catalog.dart';
import 'package:biffy/data/models/order.dart';
import 'package:biffy/data/models/user.dart';
import 'package:biffy/domain/order_rules.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:biffy/shared/state/order_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

AppUser user(AppServices s, String id) => s.session.auth.byId(id)!;

void main() {
  late AppServices s;
  setUp(() => s = makeServices());

  group('Creación de pedidos', () {
    test('crea pedidos con ID único y estado inicial', () {
      final a = placeQbano(s);
      final b = placeQbano(s);
      expect(a.id, isNot(b.id));
      expect(s.orders.all.where((o) => o.id == a.id), hasLength(1));
      expect(a.status, OrderStatus.pending);
      expect(a.deliveryCode, hasLength(4));
      expect(a.total, a.subtotal - a.campusDiscount + a.deliveryFee + a.tip);
    });

    test('el pedido aparece para el restaurante correspondiente', () {
      final o = placeQbano(s);
      expect(s.orders.forBusiness('qbano').map((x) => x.id), contains(o.id));
      expect(
        s.orders.forBusiness('verde').map((x) => x.id),
        isNot(contains(o.id)),
      );
    });

    test('sin sesión no se puede confirmar', () {
      final d = CheckoutDraft(
        buyer: null,
        restaurant: s.catalog.restaurantById('qbano-icesi'),
        items: [CartItem(lineId: 'l', dishId: 'qbano-pollo', qty: 1)],
        address: null,
        payment: PaymentMethod.nequi,
      );
      expect(
        s.orders.validate(d),
        contains('Inicia sesión para confirmar el pedido.'),
      );
      expect(() => s.orders.placeOrder(d), throwsA(isA<OrderException>()));
    });

    test('usa Gotas y las reembolsa si el restaurante rechaza', () {
      s.session.login(kDemoBuyerEmail, kDemoPassword);
      final before = s.session.gotas;
      final o = placeQbano(s, useGotas: true);
      expect(o.gotasUsed, greaterThan(0));
      expect(s.session.gotas, before - o.gotasUsed);
      s.orders.restaurantReject(o.id, 'Producto agotado');
      expect(o.status, OrderStatus.cancelled);
      expect(s.session.dataFor('u-diego').gotas, before);
    });
  });

  group('Estados permitidos', () {
    test('tabla de transiciones', () {
      expect(canTransition(OrderStatus.pending, OrderStatus.preparing), isTrue);
      expect(canTransition(OrderStatus.preparing, OrderStatus.ready), isTrue);
      expect(
        canTransition(OrderStatus.pending, OrderStatus.delivered),
        isFalse,
      );
      expect(
        canTransition(OrderStatus.preparing, OrderStatus.delivered),
        isFalse,
      );
      expect(
        canTransition(OrderStatus.delivered, OrderStatus.cancelled),
        isFalse,
      );
    });

    test('no se puede marcar listo sin aceptar', () {
      final o = placeQbano(s);
      expect(() => s.orders.markReady(o.id), throwsA(isA<OrderException>()));
    });

    test('el comprador solo cancela antes de la aceptación', () {
      final o = placeQbano(s);
      s.orders.restaurantAccept(o.id);
      expect(s.orders.cancelByBuyer(o.id), isFalse);
    });
  });

  group('Repartidores', () {
    late Order o;
    setUp(() {
      o = placeQbano(s);
      s.orders.restaurantAccept(o.id);
    });

    test('la oferta solo aparece cuando está lista', () {
      expect(
        s.orders
            .availableOffers(courierId: 'u-andres', zone: CourierZone.general)
            .map((x) => x.id),
        isNot(contains(o.id)),
      );
      s.orders.markReady(o.id);
      expect(
        s.orders
            .availableOffers(courierId: 'u-andres', zone: CourierZone.general)
            .map((x) => x.id),
        contains(o.id),
      );
    });

    test('aceptación y prevención de asignación duplicada', () {
      s.orders.markReady(o.id);
      expect(
        s.orders.courierAccept(o.id, user(s, 'u-andres')),
        CourierAcceptResult.ok,
      );
      expect(
        s.orders.courierAccept(o.id, user(s, 'u-valentina')),
        CourierAcceptResult.alreadyAssigned,
      );
      expect(o.courierId, 'u-andres');
      expect(
        s.orders
            .availableOffers(
              courierId: 'u-valentina',
              zone: CourierZone.general,
            )
            .map((x) => x.id),
        isNot(contains(o.id)),
      );
    });

    test('un repartidor ocupado no acepta otra oferta', () {
      s.orders.markReady(o.id);
      s.orders.courierAccept(o.id, user(s, 'u-andres'));
      expect(
        s.orders.courierAccept('BF-1840', user(s, 'u-andres')),
        CourierAcceptResult.busy,
      );
    });

    test('rechazar descarta la oferta solo para ese repartidor', () {
      s.orders.markReady(o.id);
      s.orders.courierDecline(o.id, 'u-andres');
      expect(
        s.orders
            .availableOffers(courierId: 'u-andres', zone: CourierZone.general)
            .map((x) => x.id),
        isNot(contains(o.id)),
      );
      expect(
        s.orders
            .availableOffers(
              courierId: 'u-valentina',
              zone: CourierZone.general,
            )
            .map((x) => x.id),
        contains(o.id),
      );
    });

    test('recogida exige los tres checks', () {
      s.orders.markReady(o.id);
      s.orders.courierAccept(o.id, user(s, 'u-andres'));
      expect(
        s.orders.confirmPickup(
          o.id,
          'u-andres',
          codeValidated: true,
          bagSealed: false,
          productsVerified: true,
        ),
        isFalse,
      );
      expect(o.status, OrderStatus.ready);
      expect(
        s.orders.confirmPickup(
          o.id,
          'u-andres',
          codeValidated: true,
          bagSealed: true,
          productsVerified: true,
        ),
        isTrue,
      );
      expect(o.status, OrderStatus.onTheWay);
    });

    test('entrega valida código y evidencia, y acredita ganancias', () {
      s.orders.markReady(o.id);
      s.orders.courierAccept(o.id, user(s, 'u-andres'));
      s.orders.confirmPickup(
        o.id,
        'u-andres',
        codeValidated: true,
        bagSealed: true,
        productsVerified: true,
      );
      final wrong = o.deliveryCode == '0000' ? '1111' : '0000';
      expect(
        s.orders.completeDelivery(o.id, 'u-andres', wrong, 'foto'),
        DeliveryResult.wrongCode,
      );
      expect(o.status, OrderStatus.onTheWay);
      expect(
        s.orders.completeDelivery(o.id, 'u-andres', o.deliveryCode, null),
        DeliveryResult.missingEvidence,
      );
      expect(o.status, OrderStatus.onTheWay);
      final before = computeEarnings(s.orders.deliveredBy('u-andres'));
      final gotas = s.session.dataFor('u-diego').gotas;
      expect(
        s.orders.completeDelivery(o.id, 'u-andres', o.deliveryCode, 'foto'),
        DeliveryResult.ok,
      );
      expect(o.status, OrderStatus.delivered);
      final after = computeEarnings(s.orders.deliveredBy('u-andres'));
      expect(after.deliveries, before.deliveries + 1);
      expect(after.gross, before.gross + o.courierPay);
      expect(after.tips, before.tips + o.tip);
      expect(s.session.dataFor('u-diego').gotas, gotas + o.subtotal ~/ 1000);
      expect(s.orders.activeForCourier('u-andres'), isNull);
    });
  });

  group('Reglas puras', () {
    test('validación del código y de la evidencia', () {
      final o = placeQbano(s);
      expect(validateDeliveryCode(o, o.deliveryCode), isTrue);
      expect(validateDeliveryCode(o, '${o.deliveryCode}9'), isFalse);
      expect(validateEvidence(null), isFalse);
      expect(validateEvidence('  '), isFalse);
      expect(validateEvidence('foto.jpg'), isTrue);
    });

    test('ganancias simuladas con tarifa Biffy', () {
      final o = placeQbano(s);
      o.status = OrderStatus.delivered;
      final e = computeEarnings([o]);
      expect(e.deliveries, 1);
      expect(e.biffyFee, (o.courierPay * kBiffyFeeRate).round());
      expect(e.net, o.courierPay - e.biffyFee + o.tip);
      expect(courierPayFor(0.1), 4500);
      expect(courierPayFor(3), 8000);
    });

    test('métricas del restaurante se actualizan', () {
      RestaurantMetricsSnapshot snap() {
        final m = computeMetrics(
          orders: s.orders.forBusiness('qbano'),
          dishes: s.catalog.productsOf('qbano'),
          branches: s.catalog.branchesOf('qbano'),
          now: kTestNow,
        );
        return RestaurantMetricsSnapshot(
          m.newCount,
          m.preparingCount,
          m.salesToday,
          m.rejectedCount,
        );
      }

      final before = snap();
      final o = placeQbano(s);
      expect(snap().newCount, before.newCount + 1);
      s.orders.restaurantAccept(o.id);
      final after = snap();
      expect(after.newCount, before.newCount);
      expect(after.preparing, before.preparing + 1);
      expect(after.salesToday, before.salesToday + o.restaurantRevenue);
      final o2 = placeQbano(s);
      s.orders.restaurantReject(o2.id, 'Cocina saturada');
      expect(snap().rejected, before.rejected + 1);
    });
  });
}

class RestaurantMetricsSnapshot {
  RestaurantMetricsSnapshot(
    this.newCount,
    this.preparing,
    this.salesToday,
    this.rejected,
  );
  final int newCount;
  final int preparing;
  final int salesToday;
  final int rejected;
}
