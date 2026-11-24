import 'dart:io';

/// Regenera `supabase/apply_all.sql` concatenando las migraciones en orden.
///
/// Uso:
///   dart run tool/generate_apply_all.dart
void main() {
  final migrations =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  const separator =
      '-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>';
  final now = DateTime.now();
  final stamp =
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')} '
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';

  final out = StringBuffer()
    ..writeln(
      '-- ============================================================================',
    )
    ..writeln('-- Biffy · Bootstrap de base de datos (generado)')
    ..writeln(
      '-- ============================================================================',
    )
    ..writeln(
      '-- Uso: Supabase Dashboard -> SQL Editor -> New query -> pegar todo -> Run.',
    )
    ..writeln(
      '-- Se genera concatenando supabase/migrations/*.sql. No editar a mano.',
    )
    ..writeln('-- Proyecto: jwdzpwsfwtkdeeuceaco')
    ..writeln('-- Generado: $stamp')
    ..writeln('--')
    ..writeln(
      '-- AVISO: la migración 0000 reemplaza las tablas de public. Las tablas con',
    )
    ..writeln(
      '-- filas NO se borran: se conservan como legacy_<nombre> con RLS activo.',
    )
    ..writeln(
      '-- ============================================================================',
    );

  for (final file in migrations) {
    final name = file.uri.pathSegments.last;
    final body = file.readAsStringSync().replaceFirst(RegExp(r'\s+$'), '');
    out
      ..writeln(separator)
      ..writeln('-- $name')
      ..writeln(separator)
      ..writeln(body)
      ..writeln();
  }

  File('supabase/apply_all.sql').writeAsStringSync(out.toString());
  stdout.writeln(
    'apply_all.sql regenerado con ${migrations.length} migraciones.',
  );
}
