// Crea o actualiza las cuentas demo de Biffy en Supabase Auth y sus perfiles.
//
// Uso:
//   $env:SUPABASE_SERVICE_ROLE_KEY = 'sb_secret_...'
//   dart run tool/admin_seed.dart
//
// La `service_role` se lee SIEMPRE de una variable de entorno: nunca se guarda
// en `env.json` ni en el repositorio. El script es idempotente: si la cuenta
// ya existe la reutiliza y solo corrige perfil y perfil de repartidor.
//
// Requiere `env.json` (o `env.example.json`) con SUPABASE_URL.
import 'dart:convert';
import 'dart:io';

/// Contraseña común de las cuentas de demostración.
const _password = 'biffy123';

/// Cuenta demo que debe existir en el proyecto.
class _DemoAccount {
  _DemoAccount({
    required this.email,
    required this.name,
    required this.role,
    required this.phone,
    this.vehicle,
    this.docNumber,
  });

  final String email;
  final String name;
  final String role;
  final String phone;
  final String? vehicle;
  final String? docNumber;
}

/// Punto de entrada: asegura las tres cuentas demo y sus filas asociadas.
Future<void> main() async {
  final env = _env();
  final serviceKey = Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  if (serviceKey == null || serviceKey.isEmpty) {
    stderr.writeln(
      'Falta SUPABASE_SERVICE_ROLE_KEY.\n'
      'Defínela solo en esta terminal:\n'
      r'  $env:SUPABASE_SERVICE_ROLE_KEY = "sb_secret_..."',
    );
    exitCode = 1;
    return;
  }

  final api = _AdminApi(env['SUPABASE_URL']!, serviceKey);
  final accounts = [
    _DemoAccount(
      email: 'diego.demo@icesi.edu.co',
      name: 'Diego (demo)',
      role: 'buyer',
      phone: '300 000 0001',
    ),
    _DemoAccount(
      email: 'andres.repartidor@demo.biffy.co',
      name: 'Andrés (repartidor demo)',
      role: 'courier',
      phone: '300 000 0003',
      vehicle: 'moto',
      docNumber: '1000000001',
    ),
    _DemoAccount(
      email: 'qbano@demo.biffy.co',
      name: 'Qbano (demo)',
      role: 'restaurant',
      phone: '300 000 0005',
    ),
  ];

  for (final account in accounts) {
    final id = await api.ensureUser(account, password: _password);
    await api.patchProfile(
      id,
      fullName: account.name,
      role: account.role,
      phone: account.phone,
    );

    if (account.role == 'courier') {
      await api.upsertCourier(
        id,
        fullName: account.name,
        phone: account.phone,
        vehicle: account.vehicle ?? 'moto',
        docNumber: account.docNumber ?? '1000000001',
      );
    }

    final welcome = await api.countWelcomeGrant(id);
    final business = await api.businessOf(id);
    stdout.writeln(
      '✓ ${account.email} · rol ${account.role} · '
      'bienvenida ${welcome ? "ok" : "PENDIENTE"}'
      '${account.role == 'restaurant' ? ' · negocio ${business ?? "sin negocio"}' : ''}',
    );
  }

  stdout.writeln(
    '\nListo. Si el negocio del restaurante aparece "sin negocio", '
    'ejecuta después:\n  dart run tool/seed_supabase.dart',
  );
}

/// Lee la URL del proyecto desde `env.json` o `env.example.json`.
Map<String, String> _env() {
  final file = File('env.json').existsSync()
      ? File('env.json')
      : File('env.example.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {'SUPABASE_URL': json['SUPABASE_URL'] as String};
}

/// Cliente mínimo de administración: Auth admin + PostgREST con service_role.
class _AdminApi {
  _AdminApi(this.base, this.serviceKey);

  final String base;
  final String serviceKey;
  final _client = HttpClient();

  /// Crea la cuenta si no existe y devuelve su uuid.
  Future<String> ensureUser(
    _DemoAccount account, {
    required String password,
  }) async {
    final body = {
      'email': account.email,
      'password': password,
      'email_confirm': true,
      'user_metadata': {
        'full_name': account.name,
        'role': account.role,
        'phone': account.phone,
      },
    };

    final created = await _call(
      'POST',
      '/auth/v1/admin/users',
      body: body,
      allowConflict: true,
    );
    if (created is Map && created['id'] is String) {
      return created['id'] as String;
    }

    // La cuenta ya existía: se busca por correo y se actualiza su metadata.
    final existing = await _findUser(account.email);
    if (existing == null) {
      throw StateError('No se pudo crear ni encontrar ${account.email}');
    }
    final id = existing['id'] as String;
    await _call(
      'PUT',
      '/auth/v1/admin/users/$id',
      body: {
        'password': password,
        'email_confirm': true,
        'user_metadata': {
          'full_name': account.name,
          'role': account.role,
          'phone': account.phone,
        },
      },
    );
    return id;
  }

  /// Busca un usuario por correo en la lista de administración.
  Future<Map<String, dynamic>?> _findUser(String email) async {
    var page = 1;
    while (true) {
      final res = await _call(
        'GET',
        '/auth/v1/admin/users?page=$page&per_page=200',
      );
      final users = (res is Map ? res['users'] : null) as List? ?? const [];
      for (final user in users) {
        if (user is Map && user['email'] == email) {
          return Map<String, dynamic>.from(user);
        }
      }
      if (users.length < 200) return null;
      page++;
    }
  }

  /// Corrige rol, nombre y teléfono en `profiles` (service_role salta RLS).
  Future<void> patchProfile(
    String userId, {
    required String fullName,
    required String role,
    required String phone,
  }) async {
    await _call(
      'PATCH',
      '/rest/v1/profiles?id=eq.$userId',
      body: {'full_name': fullName, 'role': role, 'phone': phone},
    );
  }

  /// Crea o actualiza la fila de `courier_profiles` del repartidor.
  Future<void> upsertCourier(
    String userId, {
    required String fullName,
    required String phone,
    required String vehicle,
    required String docNumber,
  }) async {
    await _call(
      'POST',
      '/rest/v1/courier_profiles?on_conflict=user_id',
      body: {
        'user_id': userId,
        'full_name': fullName,
        'doc_type': 'CC',
        'doc_number': docNumber,
        'phone': phone,
        'vehicle': vehicle,
      },
      prefer: 'resolution=merge-duplicates,return=minimal',
    );
  }

  /// Indica si la cuenta ya tiene la acreditación de bienvenida.
  Future<bool> countWelcomeGrant(String userId) async {
    final res = await _call(
      'GET',
      '/rest/v1/gotas_ledger?select=id&user_id=eq.$userId'
          '&reason=eq.${Uri.encodeQueryComponent('Bienvenida a Biffy')}&limit=1',
    );
    return res is List && res.isNotEmpty;
  }

  /// Devuelve el negocio vinculado al perfil, si existe.
  Future<String?> businessOf(String userId) async {
    final res = await _call(
      'GET',
      '/rest/v1/profiles?select=business_id&id=eq.$userId',
    );
    if (res is List && res.isNotEmpty && res.first is Map) {
      return (res.first as Map)['business_id'] as String?;
    }
    return null;
  }

  /// Ejecuta una petición con las cabeceras de administración.
  Future<dynamic> _call(
    String method,
    String path, {
    Object? body,
    String? prefer,
    bool allowConflict = false,
  }) async {
    final req = await _client.openUrl(method, Uri.parse('$base$path'));
    req.headers.set('apikey', serviceKey);
    req.headers.set('Authorization', 'Bearer $serviceKey');
    if (prefer != null) req.headers.set('Prefer', prefer);
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }

    final res = await req.close();
    final text = await utf8.decodeStream(res);
    if (res.statusCode >= 300 && !(allowConflict && res.statusCode == 422)) {
      throw StateError('$method $path → ${res.statusCode}: $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }
}
