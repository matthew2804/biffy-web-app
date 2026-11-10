import 'dart:typed_data';

import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/domain/entities/address.dart';
import 'package:biffy/domain/entities/cart.dart';
import 'package:biffy/domain/entities/catalog.dart';
import 'package:biffy/domain/entities/order.dart';
import 'package:biffy/domain/entities/user.dart';
import 'package:biffy/domain/repositories/order_repository.dart';
import 'package:biffy/domain/usecases/orders/order_usecases.dart';
import 'package:biffy/shared/adapters/order_adapters.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_order_repository.dart';
import '../helpers.dart';

const _addrId = '5b2f0a3e-1c2d-4e5f-8a9b-0c1d2e3f4a5b';
const _orderDbId = '9a8b7c6d-5e4f-4a3b-9c2d-1e0f9a8b7c6d';
const _courierId = 'u-andres';

/// Casos de uso contra un repositorio «con servidor» (falso): comprueban que
/// la app deja decidir al servidor y traduce sus respuestas.
void main() {
  late AppServices s;
  late FakeOrderRepository repo;
  late RecordingWallet wallet;
  late RecordingNotifier notifier;
  late OrderUseCases uc;

  setUp(() {
    s = makeServices();
    repo = FakeOrderRepository();
    wallet = RecordingWallet();
    notifier = RecordingNotifier();
    final sessionAdapter = SessionOrderAdapter(s.session);
    uc = OrderUseCases(
      repo: repo,
      catalog: CatalogOrderAdapter(s.catalog),
      buyers: sessionAdapter,
      wallet: wallet,
      notifier: notifier,
      clock: s.clock,
    );
    s.session.login(kDemoBuyerEmail, kDemoPassword);
  });

  tearDown(() => repo.dispose());

  /// Dirección ya guardada en la cuenta (id = uuid de `addresses`).
  Address serverAddress() {
    final a = s.session.data.defaultAddress!;
    return Address(
      id: _addrId,
      label: a.label,
      line: a.line,
      details: a.details,
      neighborhood: a.neighborhood,
      reference: a.reference,
      pointId: a.pointId,
    );
  }

  CheckoutDraft draft({Address? address, Coupon? coupon, bool gotas = false}) =>
      CheckoutDraft(
        buyer: s.session.user,
        restaurant: s.catalog.restaurantById('qbano-icesi'),
        items: [
          CartItem(
            lineId: 'l1',
            dishId: 'qbano-especial',
            qty: 1,
            selection: const DishSelection(
              sizeId: 'qe-30',
              extraIds: {'qe-queso'},
            ),
          ),
        ],
        address: address ?? serverAddress(),
        payment: PaymentMethod.cash,
        tip: TipOption.ten,
        coupon: coupon,
        useGotas: gotas,
      );

  Order serverOrder(OrderStatus status, {String? courierId, int gotas = 0}) {
    final o = Order(
      id: 'BF-3001',
      buyerId: 'u-diego',
      buyerName: 'Diego',
      restaurantId: 'qbano-icesi',
      restaurantName: 'Qbano Icesi',
      lines: const [],
      address: serverAddress(),
      pointId: 'icesi-biblioteca',
      payment: PaymentMethod.cash,
      createdAt: DateTime(2026, 10, 20, 12),
      subtotal: 10000,
      campusDiscount: 0,
      couponDiscount: 0,
      deliveryFee: 1500,
      gotasUsed: gotas,
      tip: 0,
      total: 11500,
      deliveryCode: '',
      pickupCode: '5678',
      etaMin: 20,
      courierPay: 4500,
      distanceKm: 1,
      status: status,
    );
    o.dbId = _orderDbId;
    o.courierId = courierId;
    repo.insertSeed(o);
    return o;
  }

  OrderResult placedOk(PlaceOrderRequest r) {
    final o = Order(
      id: 'BF-9001',
      buyerId: r.buyer.id,
      buyerName: r.buyer.name,
      restaurantId: r.restaurant.id,
      restaurantName: r.restaurant.name,
      lines: r.lines,
      address: r.address,
      pointId: r.pointId,
      payment: r.payment,
      createdAt: DateTime(2026, 10, 20, 12),
      subtotal: r.totals.subtotal,
      campusDiscount: 0,
      couponDiscount: 0,
      deliveryFee: 1500,
      gotasUsed: r.totals.gotasUsed,
      tip: r.totals.tip,
      total: r.totals.total,
      deliveryCode: '4821',
      pickupCode: '7733',
      etaMin: r.etaMin,
      courierPay: r.courierPay,
      distanceKm: r.distanceKm,
    );
    o.dbId = _orderDbId;
    repo.insertSeed(o);
    return OrderResult.ok(o);
  }

  group('Crear pedido con servidor', () {
    test('manda al repositorio lo que se compra y lo que se espera pagar', () async {
      repo.onPlace = placedOk;
      await uc.placeOrder(draft(), clientKey: 'k-1');

      final r = repo.placed.single;
      expect(r.clientKey, 'k-1');
      expect(r.address.id, _addrId);
      expect(r.lines.single.selection.sizeId, 'qe-30');
      expect(r.lines.single.selection.extraIds, {'qe-queso'});
      expect(r.totals.total, greaterThan(0));
      expect(r.courierPay, greaterThanOrEqualTo(4500));
      expect(r.distanceKm, greaterThan(0));
    });

    test('con éxito: el servidor mueve las Gotas, la app solo relee el saldo', () async {
      repo.onPlace = placedOk;
      final gotas = s.session.gotas;
      final res = await uc.placeOrder(draft(gotas: true));

      expect(res.ok, isTrue);
      expect(res.order!.id, 'BF-9001');
      expect(wallet.log, contains('sync'));
      expect(wallet.log.where((e) => e.startsWith('spend')), isEmpty);
      expect(s.session.gotas, gotas, reason: 'no se descuenta localmente');
      expect(notifier.log, ['placed']);
    });

    test('si el servidor rechaza no hay efectos y el motivo es claro', () async {
      repo.onPlace = (_) =>
          const OrderResult('total_mismatch', data: {'expected': 21000});
      final res = await uc.placeOrder(draft());

      expect(res.ok, isFalse);
      expect(res.message, contains(r'$21.000'));
      expect(res.isTransportError, isFalse);
      expect(wallet.log, isEmpty);
      expect(notifier.log, isEmpty);
    });

    test('un corte de red se marca como error de transporte (reintentable)', () async {
      repo.onPlace = (_) => const OrderResult('network');
      final res = await uc.placeOrder(draft());
      expect(res.isTransportError, isTrue);
      expect(res.message, contains('conexión'));
    });

    test('sin clave explícita genera una distinta por intento', () async {
      repo.onPlace = placedOk;
      await uc.placeOrder(draft());
      await uc.placeOrder(draft());
      final keys = repo.placed.map((p) => p.clientKey).toSet();
      expect(keys, hasLength(2));
      expect(keys.every((k) => k.length == 32), isTrue);
    });

    test('dirección o cupón locales no se envían: se explican', () async {
      final local = s.session.data.defaultAddress!;
      expect(
        uc.validate(draft(address: local)).join(' '),
        contains('no está guardada en tu cuenta'),
      );
      final coupon = Coupon(
        id: 'cup-local',
        title: 'Local',
        kind: CouponKind.fixed,
        amount: 2000,
      );
      expect(uc.validate(draft(coupon: coupon)).join(' '), contains('cupones locales'));
      expect(uc.validate(draft()), isEmpty);

      final res = await uc.placeOrder(draft(address: local));
      expect(res.code, 'validation');
      expect(repo.placed, isEmpty, reason: 'ni siquiera se llama al servidor');
    });
  });

  group('Transiciones: el servidor manda', () {
    test('aceptar: no cambia el estado local; avisa solo si el servidor confirma', () async {
      final o = serverOrder(OrderStatus.pending);
      final res = await uc.acceptOrder(o.id);
      expect(res.ok, isTrue);
      expect(repo.calls, ['accept:BF-3001']);
      expect(o.status, OrderStatus.pending);
      expect(notifier.log, ['accepted']);
    });

    test('un rechazo del servidor llega en español y sin avisos', () async {
      final o = serverOrder(OrderStatus.pending);
      repo.responses['accept:BF-3001'] = const OrderResult('forbidden');
      final res = await uc.acceptOrder(o.id);
      expect(res.ok, isFalse);
      expect(res.message, contains('No tienes permiso'));
      expect(res.message, isNot(contains('forbidden')));
      expect(notifier.log, isEmpty);
    });

    test('estado cambiado por otro → invalid_state se explica', () async {
      final o = serverOrder(OrderStatus.preparing);
      repo.responses['ready:BF-3001'] = const OrderResult('invalid_state');
      final res = await uc.markOrderReady(o.id);
      expect(res.message, contains('ya cambió de estado'));
    });

    test('rechazar y cancelar: el servidor devuelve Gotas y cupón, la app solo relee', () async {
      final o = serverOrder(OrderStatus.pending, gotas: 20);
      await uc.rejectOrder(o.id, 'Sin stock');
      await uc.cancelOrder(o.id);
      expect(wallet.log.where((e) => e.startsWith('credit')), isEmpty);
      expect(wallet.log.where((e) => e.startsWith('coupon')), isEmpty);
      expect(wallet.log.where((e) => e == 'sync'), hasLength(2));
    });

    test('rechazar sin motivo ni siquiera llega al servidor', () async {
      final o = serverOrder(OrderStatus.pending);
      final res = await uc.rejectOrder(o.id, '  ');
      expect(res.code, 'validation');
      expect(repo.calls, isEmpty);
    });
  });

  group('Repartidor', () {
    AppUser courier() => s.session.auth.byId(_courierId)!;

    test('cada resultado del servidor se conserva', () async {
      final o = serverOrder(OrderStatus.ready);
      for (final code in [
        'already_assigned',
        'busy',
        'out_of_range',
        'out_of_zone',
        'not_available',
        'declined_before',
      ]) {
        repo.responses['acceptOffer:BF-3001'] = OrderResult(code);
        final res = await uc.acceptOffer(o.id, courier());
        expect(res.code, code);
        expect(res.message, isNotEmpty);
        expect(res.message, isNot(contains('_')));
      }
      expect(notifier.log, isEmpty);
    });

    test('al aceptar con éxito se avisa a las tres partes', () async {
      final o = serverOrder(OrderStatus.ready);
      expect((await uc.acceptOffer(o.id, courier())).ok, isTrue);
      expect(notifier.log, ['assigned']);
    });

    test('recoger exige los tres checks antes de llamar al servidor', () async {
      final o = serverOrder(OrderStatus.ready, courierId: _courierId);
      final bad = await uc.confirmPickup(
        o.id,
        _courierId,
        codeValidated: true,
        bagSealed: false,
        productsVerified: true,
      );
      expect(bad.ok, isFalse);
      expect(repo.calls, isEmpty);

      final ok = await uc.confirmPickup(
        o.id,
        _courierId,
        codeValidated: true,
        bagSealed: true,
        productsVerified: true,
      );
      expect(ok.ok, isTrue);
      expect(repo.calls.single, 'pickup:BF-3001');
    });

    test('entrega: el código lo valida el servidor, no la app', () async {
      final o = serverOrder(OrderStatus.onTheWay, courierId: _courierId);
      repo.responses['deliver:BF-3001'] = const OrderResult('wrong_code');
      final wrong = await uc.completeDelivery(
        o.id,
        _courierId,
        '9999',
        'foto',
        evidenceBytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(wrong.code, 'wrong_code');
      expect(repo.calls, ['deliver:BF-3001'], reason: 'se consultó al servidor');

      repo.responses.remove('deliver:BF-3001');
      final ok = await uc.completeDelivery(
        o.id,
        _courierId,
        '1234',
        'foto',
        evidenceBytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(ok.ok, isTrue);
      expect(
        wallet.log.where((e) => e.startsWith('credit')),
        isEmpty,
        reason: 'las Gotas por entrega las acredita la base de datos',
      );
      expect(notifier.log, ['delivered']);
    });

    test('sin foto no se molesta al servidor', () async {
      final o = serverOrder(OrderStatus.onTheWay, courierId: _courierId);
      final res = await uc.completeDelivery(o.id, _courierId, '1234', null);
      expect(res.code, 'missing_evidence');
      expect(res.message, contains('foto'));
      expect(repo.calls, isEmpty);
    });

    test('falla la subida de la foto: mensaje claro y reintentable', () async {
      final o = serverOrder(OrderStatus.onTheWay, courierId: _courierId);
      repo.responses['deliver:BF-3001'] = const OrderResult('upload_failed');
      final res = await uc.completeDelivery(
        o.id,
        _courierId,
        '1234',
        'foto',
        evidenceBytes: Uint8List.fromList([1]),
      );
      expect(res.message, contains('No pudimos subir la foto'));
      expect(res.isTransportError, isTrue);
    });

    test('pedido de otro repartidor → invalid_state sin llamar al servidor', () async {
      final o = serverOrder(OrderStatus.onTheWay, courierId: 'u-valentina');
      final res = await uc.completeDelivery(
        o.id,
        _courierId,
        '1234',
        'foto',
        evidenceBytes: Uint8List.fromList([1]),
      );
      expect(res.code, 'invalid_state');
      expect(repo.calls, isEmpty);
    });
  });
}
