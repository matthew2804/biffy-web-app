import '../mock/seed_catalog.dart';
import '../models/business.dart';
import '../models/catalog.dart';

/// Contrato del catálogo. En un sprint posterior puede implementarse con
/// Firebase/Firestore sin cambiar las pantallas.
abstract class CatalogRepository {
  List<Business> get businesses;
  List<Restaurant> get restaurants;
  List<Dish> get dishes;

  Business? businessById(String id);
  Restaurant? restaurantById(String id);
  Dish? dishById(String id);

  void addBusiness(Business business, List<Restaurant> branches);
  void upsertDish(Dish dish);
  void deleteDish(String id);
  void recordSale(String dishId, int qty);
}

class InMemoryCatalogRepository implements CatalogRepository {
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

  @override
  List<Business> get businesses => List.unmodifiable(_businesses);
  @override
  List<Restaurant> get restaurants => List.unmodifiable(_restaurants);
  @override
  List<Dish> get dishes => List.unmodifiable(_dishes);

  @override
  Business? businessById(String id) {
    for (final b in _businesses) {
      if (b.id == id) return b;
    }
    return null;
  }

  @override
  Restaurant? restaurantById(String id) {
    for (final r in _restaurants) {
      if (r.id == id) return r;
    }
    return null;
  }

  @override
  Dish? dishById(String id) {
    for (final d in _dishes) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  void addBusiness(Business business, List<Restaurant> branches) {
    _businesses.add(business);
    _restaurants.addAll(branches);
  }

  @override
  void upsertDish(Dish dish) {
    final i = _dishes.indexWhere((d) => d.id == dish.id);
    if (i >= 0) {
      _dishes[i] = dish;
    } else {
      _dishes.insert(0, dish);
    }
  }

  @override
  void deleteDish(String id) => _dishes.removeWhere((d) => d.id == id);

  @override
  void recordSale(String dishId, int qty) {
    final d = dishById(dishId);
    if (d != null) d.soldToday += qty;
  }
}
