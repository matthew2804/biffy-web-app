import '../data/models/catalog.dart';

/// Programación de pedidos según el horario simulado del restaurante.
DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Horarios disponibles para un día, en intervalos de 30 minutos, que sean
/// futuros (con margen de preparación) y estén dentro del horario.
List<DateTime> slotsFor(Restaurant r, DateTime day, DateTime now) {
  final d = _dayOf(day);
  if (r.paused || r.closedWeekdays.contains(d.weekday)) return const [];
  final earliest = now.add(Duration(minutes: r.prepMin + 15));
  final slots = <DateTime>[];
  for (var h = r.openHour; h < r.closeHour; h++) {
    for (final m in const [0, 30]) {
      final t = DateTime(d.year, d.month, d.day, h, m);
      if (t.isAfter(earliest)) slots.add(t);
    }
  }
  return slots;
}

/// Próximos días (hasta [days]) que tienen al menos un horario disponible.
List<DateTime> availableDays(Restaurant r, DateTime now, {int days = 7}) {
  final today = _dayOf(now);
  return [
    for (var i = 0; i < days; i++) today.add(Duration(days: i)),
  ].where((d) => slotsFor(r, d, now).isNotEmpty).toList();
}

bool isValidSchedule(Restaurant r, DateTime when, DateTime now) =>
    slotsFor(r, when, now).any((s) => s == when);

/// Al cambiar de día se conserva la hora solo si sigue siendo válida.
DateTime? keepTimeIfValid(
  Restaurant r,
  DateTime newDay,
  DateTime? previous,
  DateTime now,
) {
  if (previous == null) return null;
  final candidate = DateTime(
    newDay.year,
    newDay.month,
    newDay.day,
    previous.hour,
    previous.minute,
  );
  return isValidSchedule(r, candidate, now) ? candidate : null;
}
