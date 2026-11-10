import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/order.dart';
import '../../../domain/order_rules.dart';
import '../../../domain/usecases/rate_order.dart';

/// Etapa de la hoja de calificar.
enum RateStatus { editing, sending, done, failed }

/// Estado de la calificación: estrellas elegidas, etapa y el último error.
class RateOrderState {
  /// Crea el estado; por defecto sin estrellas y editando.
  const RateOrderState({
    this.stars = 0,
    this.status = RateStatus.editing,
    this.error,
  });

  final int stars;
  final RateStatus status;
  final RateResult? error;

  /// Se puede enviar con al menos una estrella y si no está enviando.
  bool get canSubmit => stars > 0 && status != RateStatus.sending;

  /// Copia el estado cambiando solo lo indicado.
  RateOrderState copyWith({
    int? stars,
    RateStatus? status,
    RateResult? error,
  }) => RateOrderState(
    stars: stars ?? this.stars,
    status: status ?? this.status,
    error: error,
  );

  /// Dos estados son iguales si coinciden estrellas, etapa y error.
  @override
  bool operator ==(Object other) =>
      other is RateOrderState &&
      other.stars == stars &&
      other.status == status &&
      other.error == error;

  /// Código hash acorde con la igualdad.
  @override
  int get hashCode => Object.hash(stars, status, error);

  /// Texto legible para depurar y para las pruebas.
  @override
  String toString() => 'RateOrderState($stars, $status, $error)';
}

/// Cubit de la hoja de calificar: la pantalla solo emite intenciones
/// (elegir estrellas, enviar) y pinta el estado.
///
/// Flujo: pantalla → [RateOrderCubit] → [RateOrder] (regla + puertos) →
/// `ReviewRepository` (Supabase o demo).
class RateOrderCubit extends Cubit<RateOrderState> {
  /// Recibe el caso de uso, el pedido y quién lo califica.
  RateOrderCubit({
    required RateOrder rateOrder,
    required this.order,
    required this.userId,
    int initialStars = 0,
  }) : _rateOrder = rateOrder, // ignore: prefer_initializing_formals
       super(RateOrderState(stars: initialStars));

  final RateOrder _rateOrder;
  final Order order;
  final String userId;

  /// Cambia las estrellas elegidas (1..5).
  void selectStars(int stars) {
    if (state.status == RateStatus.sending) return;
    emit(state.copyWith(stars: stars, status: RateStatus.editing));
  }

  /// Envía la calificación con el comentario opcional.
  Future<void> submit([String comment = '']) async {
    if (!state.canSubmit) return;
    emit(state.copyWith(status: RateStatus.sending));
    final out = await _rateOrder(
      order: order,
      userId: userId,
      stars: state.stars,
      comment: comment,
    );
    if (isClosed) return;
    if (!out.ok) {
      emit(state.copyWith(status: RateStatus.failed, error: out.result));
      return;
    }
    emit(state.copyWith(status: RateStatus.done));
  }
}
