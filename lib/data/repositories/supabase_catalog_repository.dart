import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/business.dart';
import '../models/catalog.dart';
import 'catalog_repository.dart';

/// Catálogo real: hidrata una caché en memoria al arrancar y la refresca con
/// Realtime. Así las pantallas siguen leyendo de forma síncrona.
///
/// Las escrituras de comercio llegan en la fase 2d; por ahora se aplican solo
/// en la caché local.
class SupabaseCatalogRepository implements CatalogRepository {
  /// Constructor privado: usar [load].
  SupabaseCatalogRepository._(this._client);

  /// Carga la caché, se suscribe a Realtime y devuelve el repositorio.
  static Future<SupabaseCatalogRepository> load({sb.SupabaseClient? client}) async {
    final repo = SupabaseCatalogRepository._(
      client ?? sb.Supabase.instance.client,
    );
    await repo.refresh();
    repo._subscribe();
    return repo;
  }

  final sb.SupabaseClient _client;
  final _changes = StreamController<void>.broadcast();

  final List<Business> _businesses = [];
  final List<Restaurant> _restaurants = [];
  final List<Dish> _dishes = [];

  sb.RealtimeChannel? _channel;
  StreamSubscription<sb.AuthState>? _authSub;

  /// Emite cuando Realtime trae cambios.
  @override
  Stream<void> get changes => _changes.stream;

  // ------------------------------------------------------------- Lectura

  /// Negocios en caché (solo lectura).
  @override
  List<Business> get businesses => List.unmodifiable(_businesses);
  /// Sedes en caché (solo lectura).
  @override
  List<Restaurant> get restaurants => List.unmodifiable(_restaurants);
  /// Platos en caché (solo lectura).
  @override
  List<Dish> get dishes => List.unmodifiable(_dishes);

  /// Negocio por id dentro de la caché.
  @override
  Business? businessById(String id) {
    for (final b in _businesses) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Sede por id dentro de la caché.
  @override
  Restaurant? restaurantById(String id) {
    for (final r in _restaurants) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Plato por id dentro de la caché.
  @override
  Dish? dishById(String id) {
    for (final d in _dishes) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Vuelve a leer el catálogo completo. Nunca lanza: si falla la red se
  /// conserva lo que ya estaba en caché.
  @override
  Future<void> refresh() async {
    try {
      final businessRows = await _client.from('businesses').select();
      final branchRows = await _client.from('branches').select();
      final dishRows = await _client.from('dishes').select();
      final optionRows = await _client.from('dish_options').select();

      final optionsByDish = <String, Map<String, List<DishOption>>>{};
      for (final row in optionRows) {
        final dishId = row['dish_id'] as String?;
        final kind = row['kind'] as String?;
        if (dishId == null || kind == null) continue;
        final option = DishOption(
          row['id'] as String,
          (row['label'] as String?) ?? '',
          ((row['price_delta'] as num?) ?? 0).toInt(),
        );
        optionsByDish
            .putIfAbsent(dishId, () => {'size': [], 'side': [], 'extra': []})
            .putIfAbsent(kind, () => <DishOption>[])
            .add(option);
      }

      _businesses
        ..clear()
        ..addAll(businessRows.map(_business));
      _restaurants
        ..clear()
        ..addAll(branchRows.map(_restaurant));
      _dishes
        ..clear()
        ..addAll(dishRows.map((row) => _dish(row, optionsByDish)));
    } on Object {
      // Sin conexión: se mantiene la última copia buena.
    }
  }

  // ------------------------------------------------------------ Realtime

  /// Abre el canal de Realtime y escucha los cambios de sesión.
  void _subscribe() {
    try {
      _channel = _client
          .channel('biffy-catalog')
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'dishes',
            callback: (_) => _reload(),
          )
          .onPostgresChanges(
            event: sb.PostgresChangeEvent.all,
            schema: 'public',
            table: 'branches',
            callback: (_) => _reload(),
          )
          .subscribe();
    } on Object {
      // Realtime es opcional: si no está habilitado seguimos con la caché.
    }

    // El catálogo se hidrata antes del login; al cambiar la sesión se recarga
    // con el JWT nuevo (p. ej. el comerciante pasa a ver su negocio por RLS).
    _authSub = _client.auth.onAuthStateChange.listen((_) => _reload());
  }

  /// Recarga la caché y avisa a los oyentes.
  Future<void> _reload() async {
    await refresh();
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Libera el canal de Realtime y el stream de cambios.
  Future<void> dispose() async {
    await _authSub?.cancel();
    final channel = _channel;
    if (channel != null) {
      await _client.removeChannel(channel);
      _channel = null;
    }
    await _changes.close();
  }

  // ------------------------------------------- Escrituras (fase 2d)

  /// Agrega un negocio y sus sedes solo en la caché.
  @override
  void addBusiness(Business business, List<Restaurant> branches) {
    _businesses.add(business);
    _restaurants.addAll(branches);
  }

  /// Inserta o reemplaza un plato en la caché.
  @override
  void upsertDish(Dish dish) {
    final i = _dishes.indexWhere((d) => d.id == dish.id);
    if (i >= 0) {
      _dishes[i] = dish;
    } else {
      _dishes.add(dish);
    }
  }

  /// Quita un plato de la caché.
  @override
  void deleteDish(String id) => _dishes.removeWhere((d) => d.id == id);

  /// Suma las unidades vendidas de un plato.
  @override
  void recordSale(String dishId, int qty) {
    final dish = dishById(dishId);
    if (dish != null) dish.soldToday += qty;
  }

  // ------------------------------------------------------------ Mapeo

  /// Convierte una fila de `businesses` al modelo.
  static Business _business(Map<String, dynamic> row) => Business(
    id: row['id'] as String,
    brand: (row['brand'] as String?) ?? '',
    legalName: (row['legal_name'] as String?) ?? '',
    nit: (row['nit'] as String?) ?? '',
    cuisine: (row['cuisine'] as String?) ?? 'almuerzo',
    description: (row['description'] as String?) ?? '',
    ownerName: (row['owner_name'] as String?) ?? '',
    ownerDoc: (row['owner_doc'] as String?) ?? '',
    ownerPhone: (row['owner_phone'] as String?) ?? '',
    ownerEmail: (row['owner_email'] as String?) ?? '',
    bankName: (row['bank_name'] as String?) ?? 'Banco de demostración',
    accountType: (row['account_type'] as String?) ?? 'Ahorros',
    accountNumber: (row['account_number'] as String?) ?? '•••• 0000',
    nutritionInfo: (row['nutrition_info'] as bool?) ?? false,
    isDemo: (row['is_demo'] as bool?) ?? false,
  );

  /// Convierte una fila de `branches` al modelo.
  static Restaurant _restaurant(Map<String, dynamic> row) => Restaurant(
    id: row['id'] as String,
    businessId: row['business_id'] as String,
    name: (row['name'] as String?) ?? '',
    emoji: (row['emoji'] as String?) ?? '🍽️',
    tagline: (row['tagline'] as String?) ?? '',
    cuisine: (row['cuisine'] as String?) ?? 'almuerzo',
    address: (row['address'] as String?) ?? '',
    rating: ((row['rating'] as num?) ?? 4.5).toDouble(),
    prepMin: ((row['prep_min'] as num?) ?? 20).toInt(),
    lat: ((row['lat'] as num?) ?? 0).toDouble(),
    lng: ((row['lng'] as num?) ?? 0).toDouble(),
    radiusKm: ((row['radius_km'] as num?) ?? 3).toDouble(),
    couriersNearby: ((row['couriers_nearby'] as num?) ?? 0).toInt(),
    openHour: ((row['open_hour'] as num?) ?? 8).toInt(),
    closeHour: ((row['close_hour'] as num?) ?? 22).toInt(),
    closedWeekdays:
        (row['closed_weekdays'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [],
    campusId: row['campus_id'] as String?,
    studentDiscount: ((row['student_discount'] as num?) ?? 0).toDouble(),
    paused: (row['paused'] as bool?) ?? false,
    demo: (row['demo'] as bool?) ?? false,
    campusDeliveryOnly: (row['campus_delivery_only'] as bool?) ?? false,
    showsNutrition: (row['shows_nutrition'] as bool?) ?? false,
    imageAsset: row['image_url'] as String?,
    branchName: (row['branch_name'] as String?) ?? 'Sede principal',
  );

  /// Convierte una fila de `dishes` con sus opciones al modelo.
  static Dish _dish(
    Map<String, dynamic> row,
    Map<String, Map<String, List<DishOption>>> optionsByDish,
  ) {
    final id = row['id'] as String;
    final options = optionsByDish[id];
    final nutrition = row['nutrition'];

    return Dish(
      id: id,
      restaurantId: row['branch_id'] as String,
      name: (row['name'] as String?) ?? '',
      description: (row['description'] as String?) ?? '',
      price: ((row['price'] as num?) ?? 0).toInt(),
      emoji: (row['emoji'] as String?) ?? '🍽️',
      category: (row['category_id'] as String?) ?? 'almuerzo',
      section: (row['section'] as String?) ?? 'Menú',
      prepMin: ((row['prep_min'] as num?) ?? 15).toInt(),
      rating: ((row['rating'] as num?) ?? 4.6).toDouble(),
      ingredients: _strings(row['ingredients']),
      allergens: _strings(row['allergens']),
      tags: _strings(row['tags']),
      nutrition: nutrition is Map
          ? Nutrition(
              kcal: ((nutrition['kcal'] as num?) ?? 0).toInt(),
              protein: ((nutrition['protein'] as num?) ?? 0).toInt(),
              carbs: ((nutrition['carbs'] as num?) ?? 0).toInt(),
              fat: ((nutrition['fat'] as num?) ?? 0).toInt(),
            )
          : null,
      sizes: options?['size'] ?? const [],
      sides: options?['side'] ?? const [],
      extras: options?['extra'] ?? const [],
      popular: (row['popular'] as bool?) ?? false,
      featured: (row['featured'] as bool?) ?? false,
      active: (row['active'] as bool?) ?? true,
      soldOut: (row['sold_out'] as bool?) ?? false,
      portionLimit: (row['portion_limit'] as num?)?.toInt(),
      soldToday: ((row['sold_today'] as num?) ?? 0).toInt(),
      imageAsset: row['image_url'] as String?,
    );
  }

  /// Convierte un arreglo JSON en lista de textos.
  static List<String> _strings(Object? value) =>
      (value as List?)?.map((e) => e.toString()).toList() ?? const [];
}
