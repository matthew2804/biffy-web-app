import 'dart:async';
import 'dart:typed_data';

import '../mock/seed_catalog.dart';
import '../models/business.dart';
import '../models/catalog.dart';

/// Contrato del catálogo. En un sprint posterior puede implementarse con
/// Firebase/Firestore sin cambiar las pantallas.
abstract class CatalogRepository {
  /// Negocios con sus datos legales y de contacto.
  List<Business> get businesses;
  /// Sedes visibles en el catálogo.
  List<Restaurant> get restaurants;
  /// Platos del catálogo.
  List<Dish> get dishes;

  /// Negocio por id, o `null` si no existe.
  Business? businessById(String id);
  /// Sede por id, o `null` si no existe.
  Restaurant? restaurantById(String id);
  /// Plato por id, o `null` si no existe.
  Dish? dishById(String id);

  /// Agrega un negocio con sus sedes.
  void addBusiness(Business business, List<Restaurant> branches);
  /// Crea o actualiza un plato (remoto cuando hay backend).
  Future<void> upsertDish(Dish dish);
  /// Elimina un plato del catálogo.
  Future<void> deleteDish(String id);
  /// Suma unidades vendidas para controlar las porciones.
  void recordSale(String dishId, int qty);

  /// Marca o desmarca un plato como agotado.
  Future<void> setDishSoldOut(String dishId, bool soldOut);

  /// Pausa o reanuda una sede.
  Future<void> setBranchPaused(String branchId, bool paused);

  /// Sube la foto de un plato y devuelve su URL pública (null en demo).
  Future<String?> uploadDishPhoto({
    required String businessId,
    required Uint8List bytes,
  }) async => null;

  /// Emite cuando el backend trae cambios (Realtime). Vacío en memoria.
  Stream<void> get changes => const Stream<void>.empty();

  /// Vuelve a leer el catálogo del backend. No-op en la demo.
  Future<void> refresh() async {}
}

/// Catálogo de demostración guardado en memoria.
class InMemoryCatalogRepository implements CatalogRepository {
  /// Crea el catálogo con los datos semilla por defecto.
  InMemoryCatalogRepository({
    List<Business>? businesses,
    List<Restaurant>? restaurants,
    List<Dish>? dishes,
  }) : _businesses = businesses ?? seedBusinesses(),
       _restaurants = restaurants ?? seedRestaurants(),
       _dishes = dishes ?? seedDishes();

  final List<Business> _businesses;
  final List<Restaurant> _restaurants;
  final List<Dish> _dishes;

  /// En memoria no hay cambios remotos que emitir.
  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<void> refresh() async {}

  /// Negocios registrados (solo lectura).
  @override
  List<Business> get businesses => List.unmodifiable(_businesses);
  /// Sedes registradas (solo lectura).
  @override
  List<Restaurant> get restaurants => List.unmodifiable(_restaurants);
  /// Platos registrados (solo lectura).
  @override
  List<Dish> get dishes => List.unmodifiable(_dishes);

  /// Negocio por id dentro del catálogo.
  @override
  Business? businessById(String id) {
    for (final b in _businesses) {
      if (b.id == id) return b;
    }
    return null;
  }

  /// Sede por id dentro del catálogo.
  @override
  Restaurant? restaurantById(String id) {
    for (final r in _restaurants) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Plato por id dentro del catálogo.
  @override
  Dish? dishById(String id) {
    for (final d in _dishes) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Registra un negocio y sus sedes.
  @override
  void addBusiness(Business business, List<Restaurant> branches) {
    _businesses.add(business);
    _restaurants.addAll(branches);
  }

  /// Inserta o reemplaza un plato.
  @override
  Future<void> upsertDish(Dish dish) async {
    final i = _dishes.indexWhere((d) => d.id == dish.id);
    if (i >= 0) {
      _dishes[i] = dish;
    } else {
      _dishes.insert(0, dish);
    }
  }

  /// Quita un plato del catálogo.
  @override
  Future<void> deleteDish(String id) async =>
      _dishes.removeWhere((d) => d.id == id);

  /// Suma las unidades vendidas de un plato.
  @override
  void recordSale(String dishId, int qty) {
    final d = dishById(dishId);
    if (d != null) d.soldToday += qty;
  }

  /// Marca el plato como agotado (solo en memoria).
  @override
  Future<void> setDishSoldOut(String dishId, bool soldOut) async {
    final d = dishById(dishId);
    if (d != null) d.soldOut = soldOut;
  }

  /// Pausa la sede (solo en memoria).
  @override
  Future<void> setBranchPaused(String branchId, bool paused) async {
    final r = restaurantById(branchId);
    if (r != null) r.paused = paused;
  }

  /// En demo no hay Storage: la foto no se sube.
  @override
  Future<String?> uploadDishPhoto({
    required String businessId,
    required Uint8List bytes,
  }) async => null;
}
