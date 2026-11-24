/// Billetes colombianos que se pueden usar para pagar en efectivo.
const List<int> kCopBills = [
  1000,
  2000,
  5000,
  10000,
  20000,
  50000,
  100000,
];

/// Opciones de billete para un total: el pago exacto primero y luego los
/// billetes que alcanzan. Si el total supera el billete más alto, solo queda
/// el pago exacto (el comprador puede escribir otro monto en la UI).
List<int> cashOptions(int total) {
  if (total <= 0) return const [0];
  final bills = kCopBills.where((bill) => bill > total).toList();
  return [total, ...bills];
}

/// Vueltas para un billete. Devuelve 0 si no alcanza.
int changeFor(int total, int tendered) {
  if (tendered <= total) return 0;
  return tendered - total;
}

/// `true` si el billete alcanza para el total.
bool isValidCash(int total, int? tendered) =>
    tendered != null && tendered >= total;
