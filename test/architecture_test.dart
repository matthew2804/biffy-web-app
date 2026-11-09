import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reglas de dependencia de la Clean Architecture del ciclo de pedidos.
///
///   features/orders (Bloc) ──▶ domain ◀── data (repositorios)
///
/// El dominio es Dart puro: no conoce la UI, Flutter, Supabase ni la capa de
/// datos. El Bloc solo conoce el dominio.
List<String> _violations(String dir, RegExp forbidden) {
  final bad = <String>[];
  final files = Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    for (final line in f.readAsLinesSync()) {
      final t = line.trimLeft();
      if (!(t.startsWith('import ') || t.startsWith('export '))) continue;
      if (forbidden.hasMatch(t)) bad.add('${f.path}: $t');
    }
  }
  return bad;
}

void main() {
  test('domain no depende de data, features, shared, app ni de frameworks', () {
    final bad = _violations(
      'lib/domain',
      RegExp(
        r"(\.\./)+(data|features|shared|app)/"
        r"|package:(flutter|flutter_bloc|supabase_flutter|provider|go_router)",
      ),
    );
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('el Bloc de pedidos solo conoce el dominio (no data ni Supabase)', () {
    final bad = _violations(
      'lib/features/orders',
      RegExp(r"(\.\./)+(data|shared)/|supabase"),
    );
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('los repositorios de pedidos implementan la interfaz del dominio', () {
    for (final f in [
      'lib/data/repositories/in_memory_order_repository.dart',
      'lib/data/repositories/supabase_order_repository.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src, contains('implements OrderRepository'), reason: f);
      expect(
        src,
        contains('domain/repositories/order_repository.dart'),
        reason: f,
      );
    }
  });

  test('las pantallas no importan implementaciones de repositorios de pedidos', () {
    final bad = _violations(
      'lib/features',
      RegExp(r"data/repositories/\w*order"),
    );
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
