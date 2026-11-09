import 'dart:async';

import 'package:biffy/domain/entities/order.dart';
import 'package:biffy/domain/repositories/order_repository.dart';
import 'package:biffy/domain/usecases/orders/order_usecases.dart';
import 'package:biffy/features/orders/bloc/orders_bloc.dart';
import 'package:biffy/shared/adapters/order_adapters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_order_repository.dart';
import '../helpers.dart';

/// El Bloc traduce eventos en casos de uso y publica resultados.
void main() {
  late FakeOrderRepository repo;
  late OrdersBloc bloc;

  Order pending() {
    final s = makeServices();
    final base = s.orders.all.firstWhere((o) => o.status == OrderStatus.pending);
    final o = Order(
      id: 'BF-3001',
      buyerId: base.buyerId,
      buyerName: base.buyerName,
      restaurantId: base.restaurantId,
      restaurantName: base.restaurantName,
      lines: base.lines,
      address: base.address,
      pointId: base.pointId,
      payment: base.payment,
      createdAt: base.createdAt,
      subtotal: 10000,
      campusDiscount: 0,
      couponDiscount: 0,
      deliveryFee: 1500,
      gotasUsed: 0,
      tip: 0,
      total: 11500,
      deliveryCode: '',
      pickupCode: '1',
      etaMin: 20,
      courierPay: 4500,
      distanceKm: 1,
    );
    o.dbId = 'uuid-1';
    return o;
  }

  setUp(() {
    final s = makeServices();
    repo = FakeOrderRepository();
    final session = SessionOrderAdapter(s.session);
    bloc = OrdersBloc(
      OrderUseCases(
        repo: repo,
        catalog: CatalogOrderAdapter(s.catalog),
        buyers: session,
        wallet: RecordingWallet(),
        notifier: RecordingNotifier(),
        clock: s.clock,
      ),
    );
  });

  tearDown(() async {
    await bloc.close();
    repo.dispose();
  });

  test('estado inicial: pedidos del repositorio y sin resultado', () {
    repo.insertSeed(pending());
    final fresh = OrdersBloc(bloc.useCases);
    addTearDown(fresh.close);
    expect(fresh.state.orders, hasLength(1));
    expect(fresh.state.outcome, isNull);
  });

  test('un cambio del repositorio refresca la lista y la revisión', () async {
    final first = bloc.state.revision;
    repo.insertSeed(pending());
    repo.notifyChanged();
    final state = await bloc.stream.first;
    expect(state.orders, hasLength(1));
    expect(state.revision, greaterThan(first));
    expect(state.outcome, isNull, reason: 'refrescar no es un resultado');
  });

  test('request devuelve el resultado de la acción y lo deja en el estado', () async {
    final o = pending();
    repo.insertSeed(o);
    final outcome = await bloc.request(OrderAccepted(o.id));

    expect(outcome.ok, isTrue);
    expect(outcome.action, OrderAction.accept);
    expect(outcome.orderId, o.id);
    expect(bloc.state.outcome, same(outcome));
    expect(repo.calls, ['accept:BF-3001']);
  });

  test('cada resultado tiene un id creciente (para BlocListener)', () async {
    final o = pending();
    repo.insertSeed(o);
    final a = await bloc.request(OrderAccepted(o.id));
    final b = await bloc.request(OrderMarkedReady(o.id));
    expect(b.id, greaterThan(a.id));
  });

  test('un fallo del servidor llega como resultado con mensaje en español', () async {
    final o = pending();
    repo.insertSeed(o);
    repo.responses['accept:BF-3001'] = const OrderResult('forbidden');
    final outcome = await bloc.request(OrderAccepted(o.id));

    expect(outcome.ok, isFalse);
    expect(outcome.result.code, 'forbidden');
    expect(outcome.result.message, contains('No tienes permiso'));
  });

  test('doble toque: la segunda petición idéntica se ignora', () async {
    final o = pending();
    repo.insertSeed(o);
    repo.gate = Completer<void>();

    bloc.add(OrderAccepted(o.id));
    bloc.add(OrderAccepted(o.id));
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, hasLength(1));

    final done = bloc.stream.firstWhere((s) => s.outcome != null);
    repo.gate!.complete();
    final state = await done;
    expect(state.outcome!.ok, isTrue);

    // Terminada la primera, una nueva petición sí se procesa.
    repo.gate = null;
    await bloc.request(OrderAccepted(o.id));
    expect(repo.calls, hasLength(2));
  });

  test('acciones sobre pedidos distintos no se bloquean entre sí', () async {
    final a = pending();
    repo.insertSeed(a);
    final other = Order(
      id: 'BF-3002',
      buyerId: a.buyerId,
      buyerName: a.buyerName,
      restaurantId: a.restaurantId,
      restaurantName: a.restaurantName,
      lines: a.lines,
      address: a.address,
      pointId: a.pointId,
      payment: a.payment,
      createdAt: a.createdAt,
      subtotal: 1,
      campusDiscount: 0,
      couponDiscount: 0,
      deliveryFee: 0,
      gotasUsed: 0,
      tip: 0,
      total: 1,
      deliveryCode: '',
      pickupCode: '',
      etaMin: 1,
      courierPay: 1,
      distanceKm: 1,
    );
    repo.insertSeed(other);
    repo.gate = Completer<void>();
    bloc.add(OrderAccepted(a.id));
    bloc.add(OrderAccepted(other.id));
    await Future<void>.delayed(Duration.zero);
    expect(repo.calls, hasLength(2));
    repo.gate!.complete();
    await Future<void>.delayed(Duration.zero);
  });

  test('una excepción inesperada no se muestra cruda', () async {
    final o = pending();
    repo.insertSeed(o);
    repo.throws = true;
    final outcome = await bloc.request(OrderAccepted(o.id));

    expect(outcome.ok, isFalse);
    expect(outcome.result.code, 'server_error');
    expect(outcome.result.message, isNot(contains('bug')));
    expect(outcome.result.message, contains('Intenta de nuevo'));
  });

  test('las lecturas ven el cambio sin esperar al siguiente estado', () {
    final o = pending();
    repo.insertSeed(o);
    expect(bloc.byId(o.id), same(o));
    expect(bloc.all, hasLength(1));
    expect(bloc.forBuyer(o.buyerId), hasLength(1));
    expect(bloc.isRemote, isTrue);
  });
}
