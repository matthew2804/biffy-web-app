import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/clock.dart';
import '../../data/models/business.dart';
import '../../data/models/catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/catalog_rules.dart';
import 'session_controller.dart';

/// Vista del catálogo según el punto de entrega actual. Toda la visibilidad
/// pasa por [isReachable] (fuente única de la regla de cobertura).
class CatalogController extends ChangeNotifier {
  CatalogController(this.repo, this._session, this.clock) {
    _lastPoint = _session.pointId;
    _session.addListener(_onSession);
    // Cambios del backend (Realtime): refresca la vista sin recargar pantalla.
    _changesSub = repo.changes.listen((_) => notifyListeners());
  }

  final CatalogRepository repo;
  final SessionController _session;
  final Clock clock;
  StreamSubscription<void>? _changesSub;
  late String _lastPoint;
  bool _lastLunch = false;
  int _seq = 0;

  void _onSession() {
    final lunch = _session.settings.demoLunch;
    if (_session.pointId != _lastPoint || lunch != _lastLunch) {
      _lastPoint = _session.pointId;
      _lastLunch = lunch;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    _session.removeListener(_onSession);
    super.dispose();
  }

  DeliveryPoint get point => _session.point;
  DateTime get now => clock.now();

  Restaurant? restaurantById(String id) => repo.restaurantById(id);
  Dish? dishById(String id) => repo.dishById(id);
  Business? businessById(String id) => repo.businessById(id);

  /// Sede del caso demo de Qbano: en memoria tiene id fijo; en Supabase es un
  /// uuid, así que se busca por nombre.
  Restaurant? get qbanoIcesi =>
      restaurantById('qbano-icesi') ??
      repo.restaurants.where((r) => r.name == 'Qbano Icesi').firstOrNull;

  bool reachable(Restaurant r) => isReachable(r, point);
  bool isOpen(Restaurant r) => isOpenAt(r, now);

  bool _hasMenu(Restaurant r) =>
      repo.dishes.any((d) => d.restaurantId == r.id && d.active);

  List<Restaurant> get reachableRestaurants =>
      repo.restaurants.where((r) => reachable(r) && _hasMenu(r)).toList()
        ..sort((a, b) => distanceTo(a, point).compareTo(distanceTo(b, point)));

  List<Dish> get reachableDishes {
    final ids = reachableRestaurants.map((r) => r.id).toSet();
    return repo.dishes
        .where((d) => d.active && ids.contains(d.restaurantId))
        .toList();
  }

  List<Dish> get popularDishes {
    final list = reachableDishes.where((d) => d.popular).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }

  List<Restaurant> get topRatedRestaurants =>
      [...reachableRestaurants]..sort((a, b) => b.rating.compareTo(a.rating));

  /// Restaurantes de la universidad compatibles con la zona de entrega.
  List<Restaurant> campusRestaurants(String universityId) =>
      reachableRestaurants.where((r) => r.campusId == universityId).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));

  List<Dish> menuOf(String restaurantId) => repo.dishes
      .where((d) => d.restaurantId == restaurantId && d.active)
      .toList();

  int etaFor(Restaurant r) => etaMinutes(r, point);

  double distanceFor(Restaurant r) => distanceTo(r, point);

  FilterContext filterContext({
    Set<String> allergies = const {},
    String? universityId,
  }) => FilterContext(
    restaurantOf: repo.restaurantById,
    now: now,
    allergies: allergies,
    universityId: universityId,
  );

  // ----------------------------------------------- Gestión del restaurante

  List<Restaurant> branchesOf(String businessId) =>
      repo.restaurants.where((r) => r.businessId == businessId).toList();

  List<Dish> productsOf(String businessId) {
    final ids = branchesOf(businessId).map((r) => r.id).toSet();
    return repo.dishes.where((d) => ids.contains(d.restaurantId)).toList();
  }

  String newDishId() => 'dish-new-${++_seq}';

  void saveDish(Dish d) {
    repo.upsertDish(d);
    notifyListeners();
  }

  void deleteDish(String id) {
    repo.deleteDish(id);
    notifyListeners();
  }

  void setSoldOut(Dish d, bool soldOut) {
    d.soldOut = soldOut;
    notifyListeners();
  }

  void setBusinessPaused(String businessId, bool paused) {
    for (final r in branchesOf(businessId)) {
      r.paused = paused;
    }
    notifyListeners();
  }

  void setNutritionInfo(String businessId, bool value) {
    businessById(businessId)?.nutritionInfo = value;
    for (final r in branchesOf(businessId)) {
      r.showsNutrition = value;
    }
    notifyListeners();
  }

  bool isBusinessPaused(String businessId) =>
      branchesOf(businessId).every((r) => r.paused);

  void registerBusiness(Business b, List<Restaurant> branches) {
    repo.addBusiness(b, branches);
    notifyListeners();
  }

  void recordSale(String dishId, int qty) {
    repo.recordSale(dishId, qty);
    notifyListeners();
  }
}
