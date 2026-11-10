import 'package:biffy/data/models/address.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pruebas del modelo de dirección: copia y texto legible.
void main() {
  group('Address', () {
    test('copyWith conserva el uuid de la base', () {
      final address = Address(
        id: 'addr-1',
        label: 'Casa',
        line: 'Calle 1',
        neighborhood: 'Pance',
        pointId: 'icesi-biblioteca',
      )..dbId = 'uuid-9';

      final copy = address.copyWith(label: 'Oficina');

      expect(copy.label, 'Oficina');
      expect(copy.dbId, 'uuid-9');
      expect(copy.id, 'addr-1');
    });

    test('full une línea, detalle y barrio sin vacíos', () {
      final address = Address(
        id: 'a',
        label: 'Casa',
        line: 'Calle 1',
        details: 'Apto 302',
        neighborhood: 'Pance',
        pointId: 'p',
      );

      expect(address.full, 'Calle 1 · Apto 302 · Pance');

      final withoutDetails = address.copyWith();
      expect(withoutDetails.details, 'Apto 302');
      expect(withoutDetails.full, contains('Pance'));
    });
  });
}
