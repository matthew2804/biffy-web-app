import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/get_courier_earnings.dart';
import '../../orders/bloc/orders_bloc.dart';

/// Cubit de Ganancias: recalcula el resumen cada vez que cambian los pedidos
/// (una entrega nueva, o Realtime con Supabase).
///
/// Flujo: [OrdersBloc] (pedidos compartidos) → [GetCourierEarnings]
/// (cálculo puro) → estado [EarningsSummary] → pantalla.
class EarningsCubit extends Cubit<EarningsSummary> {
  /// Calcula el primer resumen y empieza a escuchar los pedidos.
  EarningsCubit({
    required OrdersBloc orders,
    required this.courierId,
    required DateTime Function() now,
    GetCourierEarnings getEarnings = const GetCourierEarnings(),
  }) : _orders = orders, // ignore: prefer_initializing_formals
       _now = now,
       _getEarnings = getEarnings,
       super(getEarnings(orders.deliveredBy(courierId), now())) {
    _sub = _orders.stream.listen((_) => _refresh());
  }

  final OrdersBloc _orders;
  StreamSubscription<void>? _sub;
  final DateTime Function() _now;
  final GetCourierEarnings _getEarnings;
  final String courierId;

  /// Recalcula el resumen cuando cambian los pedidos.
  void _refresh() {
    if (isClosed) return;
    emit(_getEarnings(_orders.deliveredBy(courierId), _now()));
  }

  /// Deja de escuchar los pedidos al cerrar la pantalla.
  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
