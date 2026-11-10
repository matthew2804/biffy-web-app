import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/domain/entities/cart.dart';
import 'package:biffy/domain/entities/catalog.dart';
import 'package:biffy/domain/entities/order.dart';
import 'package:biffy/domain/entities/user.dart';
import 'package:biffy/domain/order_rules.dart';
import 'package:biffy/domain/usecases/orders/order_usecases.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

AppUser user(AppServices s, String id) => s.session.auth.byId(id)!;

/// Casos de uso del ciclo del pedido sobre el repositorio en memoria (demo).
void main() {
  late AppServices s;
  late OrderUseCases uc;
  setUp(() {
    s = makeServices();
    uc = s.orders.useCases;
  });

  Future<void> toReady(Order o) async {
    await uc.acceptOrder(o.id);
    await uc.markOrderReady(o.id);
  }

  group('Crear pedido', () {
    test('crea pedidos con ID único y estado inicial', () async {
      final a = await placeQbano(s);
      final b = await placeQbano(s);
      expect(a.id, isNot(b.id));
      expect(s.orders.all.where((o) => o.id == a.id), hasLength(1));
      expect(a.status, OrderStatus.pending);
      expect(a.deliveryCode, hasLength(4));
      expect(a.total, a.subtotal - a.campusDiscount + a.deliveryFee + a.tip);
    });

    test('el pedido aparece para el restaurante correspondiente', () async {
      final o = await placeQbano(s);
      expect(s.orders.forBusiness('qbano').map((x) => x.id), contains(o.id));
      expect(
        s.orders.forBusiness('verde').map((x) => x.id),
        isNot(contains(o.id)),
      );
    });

    test('sin sesión no se puede confirmar', () async {
      final d = CheckoutDraft(
        buyer: null,
        restaurant: s.catalog.restaurantById('qbano-icesi'),
        items: [CartItem(lineId: 'l', dishId: 'qbano-pollo', qty: 1)],
        address: null,
        payment: PaymentMethod.nequi,
      );
      expect(uc.validate(d), contains('Inicia sesión para confirmar el pedido.'));
      final r = await uc.placeOrder(d);
      expect(r.ok, isFalse);
      expect(r.code, 'validation');
      expect(r.message, 'Inicia sesión para confirmar el pedido.');
      expect(s.orders.all.where((o) => o.buyerId.isEmpty), isEmpty);
    });

    test('usa Gotas y las reembolsa si el restaurante rechaza', () async {
      s.session.login(kDemoBuyerEmail, kDemoPassword);
      final before = s.session.gotas;
      final o = await placeQbano(s, useGotas: true);
      expect(o.gotasUsed, greaterThan(0));
      expect(s.session.gotas, before - o.gotasUsed);
      final r = await uc.rejectOrder(o.id, 'Producto agotado');
      expect(r.ok, isTrue);
      expect(o.status, OrderStatus.cancelled);
      expect(s.session.dataFor('u-diego').gotas, before);
    });

    test('rechazar exige un motivo', () async {
      final o = await placeQbano(s);
      final r = await uc.rejectOrder(o.id, '   ');
      expect(r.code, 'validation');
      expect(r.message, 'Indica el motivo del rechazo.');
      expect(o.status, OrderStatus.pending);
    });

    test('un reintento con la misma clave no duplica el pedido', () async {
      s.session.login(kDemoBuyerEmail, kDemoPassword);
      CheckoutDraft draft() => CheckoutDraft(
        buyer: s.session.user,
        restaurant: s.catalog.restaurantById('qbano-icesi'),
        items: [CartItem(lineId: 'l', dishId: 'qbano-especial', qty: 1)],
        address: s.session.data.defaultAddress,
        payment: PaymentMethod.cash,
      );
      final before = s.orders.all.length;
      final a = await uc.placeOrder(draft(), clientKey: 'k1');
      final b = await uc.placeOrder(draft(), clientKey: 'k1');
      expect(a.order!.id, b.order!.id);
      expect(s.orders.all.length, before + 1);
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

    test('no se puede marcar listo sin aceptar', () async {
      final o = await placeQbano(s);
      final r = await uc.markOrderReady(o.id);
      expect(r.code, 'invalid_state');
      expect(o.status, OrderStatus.pending);
    });

    test('el comprador solo cancela antes de la aceptación', () async {
      final o = await placeQbano(s);
      await uc.acceptOrder(o.id);
      final r = await uc.cancelOrder(o.id);
      expect(r.code, 'invalid_state');
      expect(o.status, OrderStatus.preparing);
    });

    test('cancelar a tiempo devuelve las Gotas', () async {
      s.session.login(kDemoBuyerEmail, kDemoPassword);
      final before = s.session.gotas;
      final o = await placeQbano(s, useGotas: true);
      expect((await uc.cancelOrder(o.id)).ok, isTrue);
      expect(o.status, OrderStatus.cancelled);
      expect(s.session.dataFor('u-diego').gotas, before);
    });

    test('un pedido inexistente devuelve not_found', () async {
      expect((await uc.acceptOrder('BF-0')).code, 'not_found');
    });
  });

  group('Repartidores', () {
    late Order o;
    setUp(() async {
      o = await placeQbano(s);
      await uc.acceptOrder(o.id);
    });

    test('la oferta solo aparece cuando está lista', () async {
      List<String> offers(String courier) => s.orders
          .availableOffers(courierId: courier, zone: CourierZone.general)
          .map((x) => x.id)
          .toList();
      expect(offers('u-andres'), isNot(contains(o.id)));
      await uc.markOrderReady(o.id);
      expect(offers('u-andres'), contains(o.id));
    });

    test('aceptación y prevención de asignación duplicada', () async {
      await uc.markOrderReady(o.id);
      expect((await uc.acceptOffer(o.id, user(s, 'u-andres'))).ok, isTrue);
      expect(
        (await uc.acceptOffer(o.id, user(s, 'u-valentina'))).code,
        'already_assigned',
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

    test('un repartidor ocupado no acepta otra oferta', () async {
      await uc.markOrderReady(o.id);
      await uc.acceptOffer(o.id, user(s, 'u-andres'));
      expect(
        (await uc.acceptOffer('BF-1840', user(s, 'u-andres'))).code,
        'busy',
      );
    });

    test('un vehículo que no cubre la distancia recibe out_of_range', () async {
      await uc.markOrderReady(o.id);
      final far = Vehicle.values.reduce((a, b) => a.maxKm < b.maxKm ? a : b);
      final tooFar = Order(
        id: 'BF-9999',
        buyerId: o.buyerId,
        buyerName: o.buyerName,
        restaurantId: o.restaurantId,
        restaurantName: o.restaurantName,
        lines: o.lines,
        address: o.address,
        pointId: o.pointId,
        payment: o.payment,
        createdAt: o.createdAt,
        subtotal: o.subtotal,
        campusDiscount: 0,
        couponDiscount: 0,
        deliveryFee: o.deliveryFee,
        gotasUsed: 0,
        tip: 0,
        total: o.total,
        deliveryCode: '1111',
        pickupCode: '2222',
        etaMin: 20,
        courierPay: o.courierPay,
        distanceKm: far.maxKm + 5,
        status: OrderStatus.ready,
      );
      s.orders.useCases.repo.insertSeed(tooFar);
      expect(
        (await uc.acceptOffer(tooFar.id, user(s, 'u-valentina'), vehicle: far))
            .code,
        'out_of_range',
      );
    });

    test('rechazar descarta la oferta solo para ese repartidor', () async {
      await uc.markOrderReady(o.id);
      await uc.declineOffer(o.id, 'u-andres');
      List<String> offers(String courier) => s.orders
          .availableOffers(courierId: courier, zone: CourierZone.general)
          .map((x) => x.id)
          .toList();
      expect(offers('u-andres'), isNot(contains(o.id)));
      expect(offers('u-valentina'), contains(o.id));
    });

    test('recogida exige los tres checks', () async {
      await uc.markOrderReady(o.id);
      await uc.acceptOffer(o.id, user(s, 'u-andres'));
      final incomplete = await uc.confirmPickup(
        o.id,
        'u-andres',
        codeValidated: true,
        bagSealed: false,
        productsVerified: true,
      );
      expect(incomplete.ok, isFalse);
      expect(o.status, OrderStatus.ready);
      final ok = await uc.confirmPickup(
        o.id,
        'u-andres',
        codeValidated: true,
        bagSealed: true,
        productsVerified: true,
      );
      expect(ok.ok, isTrue);
      expect(o.status, OrderStatus.onTheWay);
    });

    test('otro repartidor no puede recoger un pedido ajeno', () async {
      await uc.markOrderReady(o.id);
      await uc.acceptOffer(o.id, user(s, 'u-andres'));
      final r = await uc.confirmPickup(
        o.id,
        'u-valentina',
        codeValidated: true,
        bagSealed: true,
        productsVerified: true,
      );
      expect(r.code, 'forbidden');
      expect(o.status, OrderStatus.ready);
    });

    test('entrega valida código y evidencia, y acredita ganancias', () async {
      await uc.markOrderReady(o.id);
      await uc.acceptOffer(o.id, user(s, 'u-andres'));
      await uc.confirmPickup(
        o.id,
        'u-andres',
        codeValidated: true,
        bagSealed: true,
        productsVerified: true,
      );
      final wrong = o.deliveryCode == '0000' ? '1111' : '0000';
      expect(
        (await uc.completeDelivery(o.id, 'u-andres', wrong, 'foto')).code,
        'wrong_code',
      );
      expect(o.status, OrderStatus.onTheWay);
      expect(
        (await uc.completeDelivery(o.id, 'u-andres', o.deliveryCode, null)).code,
        'missing_evidence',
      );
      expect(o.status, OrderStatus.onTheWay);
      final before = computeEarnings(s.orders.deliveredBy('u-andres'));
      final gotas = s.session.dataFor('u-diego').gotas;
      expect(
        (await uc.completeDelivery(o.id, 'u-andres', o.deliveryCode, 'foto'))
            .ok,
        isTrue,
      );
      expect(o.status, OrderStatus.delivered);
      final after = computeEarnings(s.orders.deliveredBy('u-andres'));
      expect(after.deliveries, before.deliveries + 1);
      expect(after.gross, before.gross + o.courierPay);
      expect(after.tips, before.tips + o.tip);
      expect(s.session.dataFor('u-diego').gotas, gotas + o.subtotal ~/ 1000);
      expect(s.orders.activeForCourier('u-andres'), isNull);
    });

    test('entregar dos veces no acredita Gotas dos veces', () async {
      await toReady(o);
      await uc.acceptOffer(o.id, user(s, 'u-andres'));
      await uc.confirmPickup(
        o.id,
        'u-andres',
        codeValidated: true,
        bagSealed: true,
        productsVerified: true,
      );
      await uc.completeDelivery(o.id, 'u-andres', o.deliveryCode, 'foto');
      final gotas = s.session.dataFor('u-diego').gotas;
      final again =
          await uc.completeDelivery(o.id, 'u-andres', o.deliveryCode, 'foto');
      expect(again.code, 'invalid_state');
      expect(s.session.dataFor('u-diego').gotas, gotas);
    });
  });

  group('Reglas puras', () {
    test('validación del código y de la evidencia', () async {
      final o = await placeQbano(s);
      expect(validateDeliveryCode(o, o.deliveryCode), isTrue);
      expect(validateDeliveryCode(o, '${o.deliveryCode}9'), isFalse);
      expect(validateEvidence(null), isFalse);
      expect(validateEvidence('  '), isFalse);
      expect(validateEvidence('foto.jpg'), isTrue);
    });

    test('ganancias simuladas con tarifa Biffy', () async {
      final o = await placeQbano(s);
      o.status = OrderStatus.delivered;
      final e = computeEarnings([o]);
      expect(e.deliveries, 1);
      expect(e.biffyFee, (o.courierPay * kBiffyFeeRate).round());
      expect(e.net, o.courierPay - e.biffyFee + o.tip);
      expect(courierPayFor(0.1), 4500);
      expect(courierPayFor(3), 8000);
    });

    test('métricas del restaurante se actualizan', () async {
      _Snap snap() {
        final m = computeMetrics(
          orders: s.orders.forBusiness('qbano'),
          dishes: s.catalog.productsOf('qbano'),
          branches: s.catalog.branchesOf('qbano'),
          now: kTestNow,
        );
        return _Snap(
          m.newCount,
          m.preparingCount,
          m.salesToday,
          m.rejectedCount,
        );
      }

      final before = snap();
      final o = await placeQbano(s);
      expect(snap().newCount, before.newCount + 1);
      await uc.acceptOrder(o.id);
      final after = snap();
      expect(after.newCount, before.newCount);
      expect(after.preparing, before.preparing + 1);
      expect(after.salesToday, before.salesToday + o.restaurantRevenue);
      final o2 = await placeQbano(s);
      await uc.rejectOrder(o2.id, 'Cocina saturada');
      expect(snap().rejected, before.rejected + 1);
    });
  });
}

class _Snap {
  _Snap(this.newCount, this.preparing, this.salesToday, this.rejected);
  final int newCount;
  final int preparing;
  final int salesToday;
  final int rejected;
}
