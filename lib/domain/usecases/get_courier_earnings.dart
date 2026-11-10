import '../../core/utils/format.dart';
import '../../data/models/order.dart';
import '../order_rules.dart';

/// Resumen de ganancias del repartidor para la pantalla de Ganancias.
class EarningsSummary {
  const EarningsSummary({
    required this.today,
    required this.total,
    required this.week,
    required this.settlement,
    required this.history,
  });

  /// Entregas, pagos, tarifa y propinas de hoy.
  final CourierEarnings today;

  /// Acumulado de todas las entregas.
  final CourierEarnings total;

  /// Neto de los últimos 7 días; el último es hoy.
  final List<({DateTime day, int net})> week;

  /// Próximo lunes de liquidación.
  final DateTime settlement;

  /// Entregas de la más reciente a la más antigua.
  final List<Order> history;
}

/// Caso de uso: calcula las ganancias con las entregas reales del repartidor.
/// Es una función pura (no sabe de Flutter ni de Supabase); la pantalla solo
/// pinta el [EarningsSummary].
class GetCourierEarnings {
  const GetCourierEarnings();

  /// Resume [delivered] tomando [now] como el día de hoy.
  EarningsSummary call(Iterable<Order> delivered, DateTime now) {
    DateTime at(Order o) => o.deliveredAt ?? o.createdAt;
    final history =
        delivered.where((o) => o.status == OrderStatus.delivered).toList()
          ..sort((a, b) => at(b).compareTo(at(a)));

    Iterable<Order> on(DateTime day) => history.where(
      (o) => o.deliveredAt != null && sameDay(o.deliveredAt!, day),
    );

    final daysToMonday = (8 - now.weekday) % 7 == 0 ? 7 : (8 - now.weekday) % 7;
    return EarningsSummary(
      today: computeEarnings(on(now)),
      total: computeEarnings(history),
      week: [
        for (var i = 6; i >= 0; i--)
          (
            day: now.subtract(Duration(days: i)),
            net: computeEarnings(on(now.subtract(Duration(days: i)))).net,
          ),
      ],
      settlement: now.add(Duration(days: daysToMonday)),
      history: history,
    );
  }
}
