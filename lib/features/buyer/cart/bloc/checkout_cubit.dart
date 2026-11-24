import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../domain/pricing.dart';
import '../../../../domain/usecases/orders/checkout_draft.dart';
import '../../../../shared/state/session_controller.dart';
import '../../../orders/bloc/orders_bloc.dart';
import 'cart_cubit.dart';
import '../cart_draft.dart';

/// Estado del checkout: envío en curso, errores y pedido creado.
class CheckoutState {
  /// Crea el estado inicial.
  const CheckoutState({
    this.placing = false,
    this.error,
    this.orderId,
    this.message,
  });

  /// `true` mientras se crea el pedido.
  final bool placing;

  /// Error de validación o del servidor.
  final String? error;

  /// Pedido creado cuando el checkout termina bien.
  final String? orderId;

  /// Mensaje de éxito para la pantalla.
  final String? message;

  /// Copia el estado cambiando solo lo indicado.
  CheckoutState copyWith({
    bool? placing,
    String? error,
    String? orderId,
    String? message,
  }) => CheckoutState(
    placing: placing ?? this.placing,
    error: error,
    orderId: orderId ?? this.orderId,
    message: message ?? this.message,
  );
}

/// Cubit del checkout: arma el borrador, valida y delega el pedido a OrdersBloc.
///
/// No guarda líneas ni totales propios: los lee del carrito y de los casos de
/// uso de pedidos, para no duplicar la fuente de verdad.
class CheckoutCubit extends Cubit<CheckoutState> {
  /// Recibe los pedidos, la sesión y el carrito ya compartidos.
  CheckoutCubit({
    required this.orders,
    required this.session,
    required this.cart,
  }) : _clientKey = null,
       super(const CheckoutState());

  /// Bloc compartido de pedidos.
  final OrdersBloc orders;

  /// Sesión con dirección, cupones y usuario.
  final SessionController session;

  /// Carrito compartido.
  final CartCubit cart;

  String? _clientKey;

  /// Borrador actual del checkout.
  CheckoutDraft get draft => draftFromCart(session, cart);

  /// Totales calculados con las reglas de pedidos.
  CartTotals get totals => orders.preview(draft);

  /// Errores que impiden confirmar el pedido.
  List<String> get errors => orders.validate(draft);

  /// `true` si se puede confirmar ahora.
  bool get canSubmit => errors.isEmpty && !state.placing;

  /// Crea el pedido y devuelve su resultado, o `null` si no se envió.
  ///
  /// [clearCart] se apaga cuando el pago es online: si Wompi lo rechaza, el
  /// comprador vuelve al carrito con sus productos intactos.
  Future<OrderOutcome?> submit({bool clearCart = true}) async {
    if (state.placing) return null;
    final current = draft;
    final problems = orders.validate(current);
    if (problems.isNotEmpty) {
      emit(CheckoutState(error: problems.join(' ')));
      return null;
    }

    emit(const CheckoutState(placing: true));
    _clientKey ??= newClientKey();
    final outcome = await orders.request(
      OrderPlaced(current, clientKey: _clientKey),
    );
    if (isClosed) return outcome;

    if (outcome.result.ok) {
      _clientKey = null;
      if (clearCart) cart.clear();
      emit(
        CheckoutState(
          orderId: outcome.orderId,
          message: orders.isRemote
              ? 'Pedido ${outcome.orderId} enviado al restaurante'
              : 'Pedido ${outcome.orderId} creado · demostración sin cobros',
        ),
      );
      return outcome;
    }

    // Un corte de red conserva la clave para reintentar el mismo pedido.
    if (!outcome.result.isTransportError) _clientKey = null;
    emit(CheckoutState(error: outcome.result.message));
    return outcome;
  }
}
