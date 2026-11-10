part of 'orders_bloc.dart';

/// Acciones del ciclo del pedido que pueden terminar con un [OrderOutcome].
enum OrderAction {
  place,
  cancel,
  accept,
  reject,
  ready,
  acceptOffer,
  declineOffer,
  pickup,
  deliver,
}

/// Resultado de la última acción, para que la pantalla reaccione una sola vez
/// (aviso, navegación, confeti). [id] crece con cada resultado: un
/// `BlocListener` lo usa en `listenWhen` para no repetir la reacción.
final class OrderOutcome {
  const OrderOutcome(this.id, this.action, this.result, {this.orderId});

  final int id;
  final OrderAction action;
  final OrderResult result;

  /// Pedido afectado; para [OrderAction.place] es el pedido recién creado.
  final String? orderId;

  bool get ok => result.ok;
}

/// Estado del ciclo del pedido.
///
/// Los [Order] son entidades mutables que el repositorio actualiza en sitio;
/// [revision] cambia con cada refresco para que la UI se vuelva a pintar
/// aunque la lista contenga los mismos objetos.
final class OrdersState {
  const OrdersState({
    this.orders = const [],
    this.revision = 0,
    this.outcome,
  });

  final List<Order> orders;
  final int revision;
  final OrderOutcome? outcome;

  OrdersState copyWith({
    List<Order>? orders,
    int? revision,
    OrderOutcome? outcome,
  }) => OrdersState(
    orders: orders ?? this.orders,
    revision: revision ?? this.revision,
    outcome: outcome ?? this.outcome,
  );
}
