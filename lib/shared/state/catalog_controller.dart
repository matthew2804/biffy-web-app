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
  /// Se suscribe a los cambios de sesión y del catálogo remoto.
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

  /// Avisa cuando cambian el punto de entrega o el horario demo.
  void _onSession() {
    final lunch = _session.settings.demoLunch;
    if (_session.pointId != _lastPoint || lunch != _lastLunch) {
      _lastPoint = _session.pointId;
      _lastLunch = lunch;
      notifyListeners();
    }
  }

  /// Libera la suscripción al repositorio y a la sesión.
  @override
  void dispose() {
    _changesSub?.cancel();
    _session.removeListener(_onSession);
    super.dispose();
  }

  /// Punto de entrega activo de la sesión.
  DeliveryPoint get point => _session.point;
  /// Hora actual según el reloj de la app.
  DateTime get now => clock.now();

  /// Sede por id.
  Restaurant? restaurantById(String id) => repo.restaurantById(id);
  /// Plato por id.
  Dish? dishById(String id) => repo.dishById(id);
  /// Negocio por id.
  Business? businessById(String id) => repo.businessById(id);

  /// Sede del caso demo de Qbano: en memoria tiene id fijo; en Supabase es un
  /// uuid, así que se busca por nombre.
  Restaurant? get qbanoIcesi =>
      restaurantById('qbano-icesi') ??
      repo.restaurants.where((r) => r.name == 'Qbano Icesi').firstOrNull;

  /// `true` si la sede llega al punto de entrega actual.
  bool reachable(Restaurant r) => isReachable(r, point);
  /// `true` si la sede está abierta ahora.
  bool isOpen(Restaurant r) => isOpenAt(r, now);

  /// `true` si la sede tiene al menos un plato publicado.
  bool _hasMenu(Restaurant r) =>
      repo.dishes.any((d) => d.restaurantId == r.id && d.active);

  /// Sedes alcanzables con menú, ordenadas por distancia.
  List<Restaurant> get reachableRestaurants =>
      repo.restaurants.where((r) => reachable(r) && _hasMenu(r)).toList()
        ..sort((a, b) => distanceTo(a, point).compareTo(distanceTo(b, point)));

  /// Platos activos de las sedes alcanzables.
  List<Dish> get reachableDishes {
    final ids = reachableRestaurants.map((r) => r.id).toSet();
    return repo.dishes
        .where((d) => d.active && ids.contains(d.restaurantId))
        .toList();
  }

  /// Platos populares alcanzables, mejor calificados primero.
  List<Dish> get popularDishes {
    final list = reachableDishes.where((d) => d.popular).toList()
      ..sort((a, b) => b.rating.compareTo(a.rating));
    return list;
  }

  /// Sedes alcanzables ordenadas por calificación.
  List<Restaurant> get topRatedRestaurants =>
      [...reachableRestaurants]..sort((a, b) => b.rating.compareTo(a.rating));

  /// Restaurantes de la universidad compatibles con la zona de entrega.
  List<Restaurant> campusRestaurants(String universityId) =>
      reachableRestaurants.where((r) => r.campusId == universityId).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));

  /// Platos publicados de una sede.
  List<Dish> menuOf(String restaurantId) => repo.dishes
      .where((d) => d.restaurantId == restaurantId && d.active)
      .toList();

  /// Minutos estimados de entrega de una sede.
  int etaFor(Restaurant r) => etaMinutes(r, point);

  /// Distancia en km entre la sede y el punto actual.
  double distanceFor(Restaurant r) => distanceTo(r, point);

  /// Contexto de filtros para las pantallas de búsqueda.
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

  /// Sedes de un negocio.
  List<Restaurant> branchesOf(String businessId) =>
      repo.restaurants.where((r) => r.businessId == businessId).toList();

  /// Productos de todas las sedes de un negocio.
  List<Dish> productsOf(String businessId) {
    final ids = branchesOf(businessId).map((r) => r.id).toSet();
    return repo.dishes.where((d) => ids.contains(d.restaurantId)).toList();
  }

  /// Genera un id único para un plato nuevo.
  String newDishId() => 'dish-new-${++_seq}';

  /// Guarda un plato en el catálogo compartido.
  void saveDish(Dish d) {
    repo.upsertDish(d);
    notifyListeners();
  }

  /// Elimina un plato del catálogo.
  void deleteDish(String id) {
    repo.deleteDish(id);
    notifyListeners();
  }

  /// Marca o desmarca un plato como agotado.
  void setSoldOut(Dish d, bool soldOut) {
    d.soldOut = soldOut;
    notifyListeners();
  }

  /// Pausa o reanuda todas las sedes de un negocio.
  void setBusinessPaused(String businessId, bool paused) {
    for (final r in branchesOf(businessId)) {
      r.paused = paused;
    }
    notifyListeners();
  }

  /// Activa la información nutricional en un negocio.
  void setNutritionInfo(String businessId, bool value) {
    businessById(businessId)?.nutritionInfo = value;
    for (final r in branchesOf(businessId)) {
      r.showsNutrition = value;
    }
    notifyListeners();
  }

  /// `true` si todas las sedes del negocio están pausadas.
  bool isBusinessPaused(String businessId) =>
      branchesOf(businessId).every((r) => r.paused);

  /// Registra un negocio con sus sedes.
  void registerBusiness(Business b, List<Restaurant> branches) {
    repo.addBusiness(b, branches);
    notifyListeners();
  }

  /// Suma las unidades vendidas de un plato.
  void recordSale(String dishId, int qty) {
    repo.recordSale(dishId, qty);
    notifyListeners();
  }
}
