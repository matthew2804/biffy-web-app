// Carga el catálogo de demostración (negocios, sedes, platos y opciones) en
// Supabase usando el mismo seed que la app. Es idempotente: lo que ya existe
// se omite y solo se completan los campos que faltan.
//
// Uso:
//   dart run tool/seed_supabase.dart
//
// Requiere `env.json` (o `env.example.json`) con SUPABASE_URL y SUPABASE_KEY.
import 'dart:convert';
import 'dart:io';

import 'package:biffy/data/mock/seed_catalog.dart';
import 'package:biffy/data/models/catalog.dart';

const _password = 'biffy123';

/// Punto de entrada: recorre el seed y lo replica en Supabase.
Future<void> main() async {
  final env = _env();
  final api = _Api(env['SUPABASE_URL']!, env['SUPABASE_KEY']!);

  final businesses = seedBusinesses();
  final branches = seedRestaurants();
  final dishes = seedDishes();

  var createdBusinesses = 0;
  var createdBranches = 0;
  var createdDishes = 0;

  for (final business in businesses) {
    try {
      final session = await api.signInOrUp(business.ownerEmail, business.ownerName);
      final token = session['access_token'] as String;
      final userId = (session['user'] as Map)['id'] as String;

      // 1) Negocio: se crea solo si el perfil aún no tiene uno.
      final profile = await api.get(
        '/rest/v1/profiles?select=business_id&id=eq.$userId',
        token,
      );
      String? businessId = profile[0]['business_id'] as String?;

      final myBranches =
          branches.where((r) => r.businessId == business.id).toList();

      if (businessId == null) {
        final res = await api.rpc('register_business', {
          'brand': business.brand,
          'legal_name': business.legalName,
          'nit': business.nit,
          'cuisine': business.cuisine,
          'description': business.description,
          'owner_name': business.ownerName,
          'owner_doc': business.ownerDoc,
          'owner_phone': business.ownerPhone,
          'owner_email': business.ownerEmail,
          'bank_name': business.bankName,
          'account_type': business.accountType,
          'account_number': business.accountNumber,
          'legal_docs': business.legalDocs,
          'nutrition_info': business.nutritionInfo,
          'branches': [for (final r in myBranches) _branchPayload(r)],
        }, token);
        businessId = res['business_id'] as String?;
        createdBusinesses++;
      }
      if (businessId == null) {
        stdout.writeln('  ! ${business.brand}: no se pudo crear el negocio');
        continue;
      }

      // 2) Sedes: se completan los campos que el RPC no recibe.
      final dbBranches = await api.get(
        '/rest/v1/branches?select=id,name&business_id=eq.$businessId',
        token,
      );

      for (final r in myBranches) {
        var branchId = _findBranchId(dbBranches, r.name);
        if (branchId == null) {
          final inserted = await api.post('/rest/v1/branches', {
            'business_id': businessId,
            ..._branchPayload(r),
          }, token);
          branchId = inserted[0]['id'] as String;
          createdBranches++;
        }

        await api.patch('/rest/v1/branches?id=eq.$branchId', {
          'rating': r.rating,
          'prep_min': r.prepMin,
          'couriers_nearby': r.couriersNearby == 0 ? 1 : r.couriersNearby,
          'closed_weekdays': r.closedWeekdays,
          'campus_delivery_only': r.campusDeliveryOnly,
          'shows_nutrition': r.showsNutrition,
          'image_url': r.imageAsset,
          'demo': true,
        }, token);

        // 3) Platos de esa sede (por nombre para no duplicar).
        for (final d in dishes.where((d) => d.restaurantId == r.id)) {
          final exists = await api.get(
            '/rest/v1/dishes?select=id&branch_id=eq.$branchId'
            '&name=eq.${Uri.encodeComponent(d.name)}&limit=1',
            token,
          );
          if (exists.isNotEmpty) continue;

          final inserted = await api.post(
            '/rest/v1/dishes',
            _dishPayload(d, branchId),
            token,
          );
          final dishId = inserted[0]['id'] as String;
          createdDishes++;

          final options = _optionRows(d, dishId);
          if (options.isNotEmpty) {
            await api.post('/rest/v1/dish_options', options, token);
          }
        }
      }

      stdout.writeln('✓ ${business.brand}');
    } catch (e) {
      stdout.writeln('✗ ${business.brand}: $e');
    }
  }

  stdout.writeln(
    '\nListo · negocios nuevos: $createdBusinesses · '
    'sedes nuevas: $createdBranches · platos nuevos: $createdDishes',
  );
}

/// Lee las credenciales del proyecto desde `env.json` o `env.example.json`.
Map<String, String> _env() {
  final file = File('env.json').existsSync()
      ? File('env.json')
      : File('env.example.json');
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return {
    'SUPABASE_URL': json['SUPABASE_URL'] as String,
    'SUPABASE_KEY': json['SUPABASE_KEY'] as String,
  };
}

/// Cuerpo de una sede para `register_business` o para el insert directo.
Map<String, dynamic> _branchPayload(Restaurant r) => {
  'name': r.name,
  'branch_name': r.branchName,
  'address': r.address,
  'city': r.campusId == 'icesi' ? 'Cali' : 'Bogotá',
  'lat': r.lat,
  'lng': r.lng,
  'radius_km': r.radiusKm,
  'open_hour': r.openHour,
  'close_hour': r.closeHour,
  'campus_id': r.campusId,
  'student_discount': r.studentDiscount,
  'emoji': r.emoji,
  'tagline': r.tagline,
};

/// Cuerpo de un plato listo para la tabla `dishes`.
Map<String, dynamic> _dishPayload(Dish d, String branchId) => {
  'branch_id': branchId,
  'name': d.name,
  'description': d.description,
  'price': d.price,
  'emoji': d.emoji,
  'category_id': d.category,
  'section': d.section,
  'prep_min': d.prepMin,
  'rating': d.rating,
  'ingredients': d.ingredients,
  'allergens': d.allergens,
  'tags': d.tags,
  'nutrition': d.nutrition == null
      ? null
      : {
          'kcal': d.nutrition!.kcal,
          'protein': d.nutrition!.protein,
          'carbs': d.nutrition!.carbs,
          'fat': d.nutrition!.fat,
        },
  'popular': d.popular,
  'featured': d.featured,
  'active': d.active,
  'sold_out': d.soldOut,
  'portion_limit': d.portionLimit,
  'sold_today': d.soldToday,
  'image_url': d.imageAsset,
};

/// Filas de `dish_options` para tamaños, acompañantes y extras.
List<Map<String, dynamic>> _optionRows(Dish d, String dishId) => [
  for (var i = 0; i < d.sizes.length; i++)
    {
      'dish_id': dishId,
      'kind': 'size',
      'label': d.sizes[i].label,
      'price_delta': d.sizes[i].price,
      'sort': i,
    },
  for (var i = 0; i < d.sides.length; i++)
    {
      'dish_id': dishId,
      'kind': 'side',
      'label': d.sides[i].label,
      'price_delta': d.sides[i].price,
      'sort': i,
    },
  for (var i = 0; i < d.extras.length; i++)
    {
      'dish_id': dishId,
      'kind': 'extra',
      'label': d.extras[i].label,
      'price_delta': d.extras[i].price,
      'sort': i,
    },
];

/// Busca el id de una sede por nombre dentro de las ya existentes.
String? _findBranchId(List<dynamic> rows, String name) {
  for (final row in rows) {
    if (row is Map && row['name'] == name) return row['id'] as String?;
  }
  return null;
}

/// Cliente HTTP mínimo contra Supabase (Auth + PostgREST).
class _Api {
  _Api(this.base, this.key);

  final String base;
  final String key;
  final _client = HttpClient();

  /// Inicia sesión o registra al dueño; devuelve la sesión con `access_token`.
  Future<Map<String, dynamic>> signInOrUp(String email, String name) async {
    try {
      final res = await _call(
        'POST',
        '/auth/v1/signup',
        body: {
          'email': email,
          'password': _password,
          'data': {'full_name': name, 'role': 'restaurant'},
        },
      );
      if (res is Map && res['access_token'] != null) {
        return Map<String, dynamic>.from(res);
      }
    } on Object {
      // La cuenta ya existe: se intenta iniciar sesión.
    }
    final res = await _call(
      'POST',
      '/auth/v1/token?grant_type=password',
      body: {'email': email, 'password': _password},
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// Ejecuta una función RPC con el token del dueño.
  Future<Map<String, dynamic>> rpc(
    String fn,
    Map<String, dynamic> payload,
    String token,
  ) async {
    final res = await _call(
      'POST',
      '/rest/v1/rpc/$fn',
      body: {'p_payload': payload},
      token: token,
    );
    return Map<String, dynamic>.from(res as Map);
  }

  /// GET a PostgREST (siempre devuelve una lista).
  Future<List<dynamic>> get(String path, String token) async {
    final res = await _call('GET', path, token: token);
    return (res as List?) ?? const [];
  }

  /// INSERT y devuelve las filas creadas.
  Future<List<dynamic>> post(
    String path,
    Object body,
    String token,
  ) async {
    final res = await _call(
      'POST',
      path,
      body: body,
      token: token,
      preferReturn: true,
    );
    return (res as List?) ?? const [];
  }

  /// UPDATE por filtro en la URL.
  Future<void> patch(
    String path,
    Map<String, dynamic> body,
    String token,
  ) async {
    await _call('PATCH', path, body: body, token: token);
  }

  /// Envía una petición y devuelve el JSON (o null si viene vacío).
  Future<dynamic> _call(
    String method,
    String path, {
    Object? body,
    String? token,
    bool preferReturn = false,
  }) async {
    final req = await _client.openUrl(method, Uri.parse('$base$path'));
    req.headers.set('apikey', key);
    req.headers.set('Authorization', 'Bearer ${token ?? key}');
    if (preferReturn) {
      req.headers.set('Prefer', 'return=representation');
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await utf8.decodeStream(res);
    if (res.statusCode >= 300) {
      throw Exception('$method $path → ${res.statusCode}: $text');
    }
    return text.isEmpty ? null : jsonDecode(text);
  }
}
