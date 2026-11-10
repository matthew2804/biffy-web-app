import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/order.dart';
import '../../../domain/entities/user.dart';
import '../../../domain/pricing.dart';
import '../../../domain/repositories/order_repository.dart';
import '../../../domain/usecases/orders/order_usecases.dart';

part 'orders_event.dart';
part 'orders_state.dart';

/// Bloc del ciclo del pedido (comprador, restaurante y repartidor).
///
/// Traduce eventos en llamadas a los casos de uso y publica el resultado en
/// [OrdersState.outcome]. No contiene reglas de negocio: esas viven en
/// `domain/usecases`. Una acción repetida mientras la anterior sigue en curso
/// (doble toque) se ignora.
class OrdersBloc extends Bloc<OrdersEvent, OrdersState> {
  OrdersBloc(this.useCases) : super(OrdersState(orders: useCases.repo.all)) {
    on<OrdersChanged>(_onChanged);
    on<OrderPlaced>(
      (e, emit) => _run(
        emit,
        OrderAction.place,
        null,
        () => useCases.placeOrder(e.draft, clientKey: e.clientKey),
      ),
    );
    on<OrderCancelled>(
      (e, emit) => _run(
        emit,
        OrderAction.cancel,
        e.orderId,
        () => useCases.cancelOrder(e.orderId),
      ),
    );
    on<OrderAccepted>(
      (e, emit) => _run(
        emit,
        OrderAction.accept,
        e.orderId,
        () => useCases.acceptOrder(e.orderId),
      ),
    );
    on<OrderRejected>(
      (e, emit) => _run(
        emit,
        OrderAction.reject,
        e.orderId,
        () => useCases.rejectOrder(e.orderId, e.reason),
      ),
    );
    on<OrderMarkedReady>(
      (e, emit) => _run(
        emit,
        OrderAction.ready,
        e.orderId,
        () => useCases.markOrderReady(e.orderId),
      ),
    );
    on<OfferAccepted>(
      (e, emit) => _run(
        emit,
        OrderAction.acceptOffer,
        e.orderId,
        () => useCases.acceptOffer(e.orderId, e.courier, vehicle: e.vehicle),
      ),
    );
    on<OfferDeclined>(
      (e, emit) => _run(
        emit,
        OrderAction.declineOffer,
        e.orderId,
        () => useCases.declineOffer(e.orderId, e.courierId),
      ),
    );
    on<PickupConfirmed>(
      (e, emit) => _run(
        emit,
        OrderAction.pickup,
        e.orderId,
        () => useCases.confirmPickup(
          e.orderId,
          e.courierId,
          codeValidated: e.codeValidated,
          bagSealed: e.bagSealed,
          productsVerified: e.productsVerified,
        ),
      ),
    );
    on<DeliveryCompleted>(
      (e, emit) => _run(
        emit,
        OrderAction.deliver,
        e.orderId,
        () => useCases.completeDelivery(
          e.orderId,
          e.courierId,
          e.code,
          e.evidence,
          evidenceBytes: e.evidenceBytes,
        ),
      ),
    );

    _changes = useCases.repo.changes.listen((_) => add(const OrdersChanged()));
  }

  final OrderUseCases useCases;
  StreamSubscription<void>? _changes;
  final Set<String> _inFlight = {};
  int _outcomeSeq = 0;
  bool _syncingWallet = false;

  OrderRepository get _repo => useCases.repo;

  // ------------------------------------------------------------- Lecturas
  // Atajos de solo lectura para las pantallas. Leen el repositorio (la fuente
  // de verdad) y no necesitan esperar al siguiente estado.

  /// `true` cuando los pedidos viven en un servidor.
  bool get isRemote => _repo.isRemote;

  List<Order> get all => useCases.queries.all;
  Order? byId(String id) => useCases.queries.byId(id);
  List<Order> forBuyer(String userId) => useCases.queries.forBuyer(userId);
  List<Order> forBusiness(String businessId) =>
      useCases.queries.forBusiness(businessId);
  Order? activeForCourier(String courierId) =>
      useCases.queries.activeForCourier(courierId);
  List<Order> deliveredBy(String courierId) =>
      useCases.queries.deliveredBy(courierId);
  List<Order> availableOffers({
    required String courierId,
    required CourierZone zone,
    String? universityId,
    Vehicle? vehicle,
  }) => useCases.queries.availableOffers(
    courierId: courierId,
    zone: zone,
    universityId: universityId,
    vehicle: vehicle,
  );

  CartTotals preview(CheckoutDraft d) => useCases.preview(d);
  List<String> validate(CheckoutDraft d) => useCases.validate(d);

  // -------------------------------------------------------------- Eventos

  /// Despacha [event] y espera su [OrderOutcome].
  ///
  /// Para flujos secuenciales (confirmar → navegar, entregar → celebrar) donde
  /// la pantalla necesita el resultado en el mismo `onPressed`. Sigue siendo
  /// Bloc: el evento entra por `add` y la respuesta sale del estado.
  Future<OrderOutcome> request(OrdersEvent event) {
    final (action, orderId) = _describe(event);
    final since = _outcomeSeq;
    final outcome = stream
        .map((s) => s.outcome)
        .where(
          (o) =>
              o != null &&
              o.id > since &&
              o.action == action &&
              (orderId == null || o.orderId == orderId),
        )
        .cast<OrderOutcome>()
        .first
        .timeout(
          const Duration(seconds: 60),
          onTimeout: () => OrderOutcome(
            0,
            action,
            const OrderResult('network'),
            orderId: orderId,
          ),
        );
    add(event);
    return outcome;
  }

  (OrderAction, String?) _describe(OrdersEvent event) => switch (event) {
    OrderPlaced() => (OrderAction.place, null),
    OrderCancelled(:final orderId) => (OrderAction.cancel, orderId),
    OrderAccepted(:final orderId) => (OrderAction.accept, orderId),
    OrderRejected(:final orderId) => (OrderAction.reject, orderId),
    OrderMarkedReady(:final orderId) => (OrderAction.ready, orderId),
    OfferAccepted(:final orderId) => (OrderAction.acceptOffer, orderId),
    OfferDeclined(:final orderId) => (OrderAction.declineOffer, orderId),
    PickupConfirmed(:final orderId) => (OrderAction.pickup, orderId),
    DeliveryCompleted(:final orderId) => (OrderAction.deliver, orderId),
    OrdersChanged() => throw ArgumentError('OrdersChanged no tiene resultado'),
  };

  void _onChanged(OrdersChanged event, Emitter<OrdersState> emit) {
    emit(state.copyWith(orders: _repo.all, revision: state.revision + 1));
    // Con servidor las Gotas las mueven los RPC de cualquier rol: se relee el
    // saldo cuando cambian los pedidos.
    if (_repo.isRemote && !_syncingWallet) {
      _syncingWallet = true;
      useCases.syncWallet().whenComplete(() => _syncingWallet = false);
    }
  }

  Future<void> _run(
    Emitter<OrdersState> emit,
    OrderAction action,
    String? orderId,
    Future<OrderResult> Function() operation,
  ) async {
    final key = '${action.name}:${orderId ?? ''}';
    if (!_inFlight.add(key)) return; // doble toque
    OrderResult result;
    try {
      result = await operation();
    } on Object {
      // Los casos de uso no deberían lanzar; si ocurre no se muestra la
      // excepción cruda.
      result = const OrderResult('server_error');
    } finally {
      _inFlight.remove(key);
    }
    if (isClosed) return;
    emit(
      state.copyWith(
        orders: _repo.all,
        revision: state.revision + 1,
        outcome: OrderOutcome(
          ++_outcomeSeq,
          action,
          result,
          orderId: orderId ?? result.order?.id,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _changes?.cancel();
    return super.close();
  }
}
