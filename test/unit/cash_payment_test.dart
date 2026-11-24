import 'package:biffy/domain/cash_payment.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas de los billetes y las vueltas del pago en efectivo.
void main() {
  test('ofrece el pago exacto y los billetes que alcanzan', () {
    expect(cashOptions(13650), [13650, 20000, 50000, 100000]);
    expect(cashOptions(50000), [50000, 100000]);
    expect(cashOptions(150000), [150000]);
  });

  test('calcula las vueltas y valida el billete', () {
    expect(changeFor(13650, 20000), 6350);
    expect(changeFor(13650, 50000), 36350);
    expect(changeFor(13650, 10000), 0);
    expect(isValidCash(13650, 20000), isTrue);
    expect(isValidCash(13650, 13650), isTrue);
    expect(isValidCash(13650, 10000), isFalse);
    expect(isValidCash(13650, null), isFalse);
  });
}
