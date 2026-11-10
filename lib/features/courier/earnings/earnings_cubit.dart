import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/get_courier_earnings.dart';
import '../../../shared/state/order_service.dart';

/// Cubit de Ganancias: recalcula el resumen cada vez que cambian los pedidos
/// (una entrega nueva, o Realtime con Supabase).
///
/// Flujo: [OrderService] (pedidos compartidos) → [GetCourierEarnings]
/// (cálculo puro) → estado [EarningsSummary] → pantalla.
class EarningsCubit extends Cubit<EarningsSummary> {
  EarningsCubit({
    required OrderService orders,
    required this.courierId,
    required DateTime Function() now,
    GetCourierEarnings getEarnings = const GetCourierEarnings(),
  }) : _orders = orders, // ignore: prefer_initializing_formals
       _now = now,
       _getEarnings = getEarnings,
       super(getEarnings(orders.deliveredBy(courierId), now())) {
    _orders.addListener(_refresh);
  }

  final OrderService _orders;
  final DateTime Function() _now;
  final GetCourierEarnings _getEarnings;
  final String courierId;

  void _refresh() {
    if (isClosed) return;
    emit(_getEarnings(_orders.deliveredBy(courierId), _now()));
  }

  /// Deja de escuchar los pedidos al cerrar la pantalla.
  @override
  Future<void> close() {
    _orders.removeListener(_refresh);
    return super.close();
  }
}
