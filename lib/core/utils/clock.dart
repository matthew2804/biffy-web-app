/// Reloj inyectable: permite fijar la hora en pruebas y demostraciones.
class Clock {
  Clock([DateTime Function()? now]) : _now = now ?? DateTime.now;

  /// Reloj fijo (útil para pruebas deterministas).
  factory Clock.fixed(DateTime time) => Clock(() => time);

  final DateTime Function() _now;

  /// Modo demostración: conserva la fecha y los minutos pero fija la hora en
  /// 12 (almuerzo) para probar pedidos inmediatos a cualquier hora.
  bool simulateLunch = false;

  /// Hora actual, respetando el modo de demostración.
  DateTime now() {
    final n = _now();
    return simulateLunch
        ? DateTime(n.year, n.month, n.day, 12, n.minute, n.second)
        : n;
  }
}
