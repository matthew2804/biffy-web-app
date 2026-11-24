import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reglas de dependencia de la Clean Architecture del ciclo de pedidos.
///
///   features/orders (Bloc) ──▶ domain ◀── data (repositorios)
///
/// El dominio es Dart puro: no conoce la UI, Flutter, Supabase ni la capa de
/// datos. El Bloc solo conoce el dominio.
List<String> _violations(
  String dir,
  RegExp forbidden, {
  List<String> except = const [],
}) {
  final bad = <String>[];
  final files = Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) {
        final path = f.path.replaceAll(r'\', '/');
        return !except.any(path.contains);
      });
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
        r"|package:(flutter|flutter_bloc|supabase_flutter|provider|go_router|get_it)",
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

  test('los cubits de autenticación no importan data ni Supabase', () {
    final bad = _violations(
      'lib/features/auth/bloc',
      RegExp(r"(\.\./)+data/|supabase"),
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

  test(
    'las pantallas no importan implementaciones de repositorios de pedidos',
    () {
      final bad = _violations(
        'lib/features',
        RegExp(r"data/repositories/\w*order"),
      );
      expect(bad, isEmpty, reason: bad.join('\n'));
    },
  );

  test('solo lib/app/di conoce las implementaciones concretas', () {
    // Ninguna pantalla, controlador ni caso de uso importa un repositorio en
    // memoria o de Supabase: los piden a GetIt por su interfaz.
    final bad = _violations(
      'lib',
      RegExp(
        r"(in_memory_\w+|supabase_\w*repository|review_repository_impl)\.dart",
      ),
      except: ['lib/app/di/', 'lib/data/'],
    );
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('Supabase solo lo conocen la capa de datos y el módulo de datos', () {
    final bad = _violations(
      'lib',
      RegExp(r"package:supabase_flutter"),
      except: ['lib/data/', 'lib/app/di/modules/data_module.dart'],
    );
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no queda Provider ni AppServices: todo sale de GetIt', () {
    final bad = _violations('lib', RegExp(r"package:provider|app_services"));
    expect(bad, isEmpty, reason: bad.join('\n'));
    expect(
      File('lib/shared/state/app_services.dart').existsSync(),
      isFalse,
      reason: 'AppServices fue reemplazado por lib/app/di/injection.dart',
    );
  });

  test(
    'los módulos de GetIt separan núcleo, datos, dominio y presentación',
    () {
      for (final m in ['core', 'data', 'domain', 'presentation']) {
        expect(
          File('lib/app/di/modules/${m}_module.dart').existsSync(),
          isTrue,
          reason: 'falta el módulo $m',
        );
      }
      final injection = File('lib/app/di/injection.dart').readAsStringSync();
      expect(injection, contains('registerCoreModule'));
      expect(injection, contains('registerDataModule'));
      expect(injection, contains('registerDomainModule'));
      expect(injection, contains('registerPresentationModule'));
    },
  );

  test('la única decisión de entorno vive en el módulo de datos', () {
    final bad = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
          final path = f.path.replaceAll(r'\', '/');
          return !path.contains('lib/app/di/modules/data_module.dart') &&
              !path.contains('lib/core/config/');
        });
    for (final f in files) {
      for (final line in f.readAsLinesSync()) {
        final code = line.trimLeft();
        if (code.startsWith('//')) continue; // comentarios y /// no cuentan
        if (code.contains('AppConfig.hasSupabase')) bad.add('${f.path}: $code');
      }
    }
    expect(bad, isEmpty, reason: bad.join('\n'));
  });
}
