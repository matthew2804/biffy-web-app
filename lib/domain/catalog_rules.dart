import '../core/constants/catalog_constants.dart';
import '../core/utils/format.dart';
import '../core/utils/geo.dart';
import '../data/models/catalog.dart';

/// Distancia en km entre el restaurante y el punto de entrega.
double distanceTo(Restaurant r, DeliveryPoint p) =>
    distanceKm(r.lat, r.lng, p.lat, p.lng);

/// Regla única de cobertura: el punto está dentro del radio del restaurante,
/// hay repartidores cerca y, si es solo campus, el punto pertenece al campus.
bool isReachable(Restaurant r, DeliveryPoint p) {
  if (r.campusDeliveryOnly && p.campusId != r.campusId) return false;
  return r.couriersNearby > 0 && distanceTo(r, p) <= r.radiusKm;
}

/// Indica si el restaurante está abierto en ese momento.
bool isOpenAt(Restaurant r, DateTime t) =>
    !r.paused &&
    !r.closedWeekdays.contains(t.weekday) &&
    t.hour >= r.openHour &&
    t.hour < r.closeHour;

/// Texto del horario: horas de atención y días cerrados.
String scheduleLabel(Restaurant r) {
  final days = r.closedWeekdays.isEmpty
      ? 'Todos los días'
      : 'Cerrado ${r.closedWeekdays.map(weekdayName).join(', ')}';
  return '${two(r.openHour)}:00 – ${two(r.closeHour)}:00 · $days';
}

/// Tiempo estimado: preparación + trayecto simulado.
int etaMinutes(Restaurant r, DeliveryPoint p, {int? prepMin}) =>
    (prepMin ?? r.prepMin) + (distanceTo(r, p) * 4).round() + 5;

/// Alérgenos del plato que coinciden con las alergias del usuario.
List<String> allergyConflicts(Dish d, Set<String> allergies) =>
    d.allergens.where(allergies.contains).toList();

/// Indica si el plato es bajo en calorías por etiqueta o nutrición.
bool _isLowCalorie(Dish d) =>
    d.tags.contains('bajo en calorías') ||
    (d.nutrition != null && d.nutrition!.kcal <= 550);

/// Indica si el plato cumple un estilo de vida o restricción.
bool matchesLifestyle(Dish d, String style) => switch (style) {
  'vegetariano' => d.tags.contains('vegetariano') || d.tags.contains('vegano'),
  'bajo en calorías' => _isLowCalorie(d),
  _ => d.tags.contains(style),
};

/// Indica si el plato cumple todos los estilos indicados.
bool matchesAllLifestyles(Dish d, Set<String> styles) =>
    styles.every((s) => matchesLifestyle(d, s));

/// Indica si el plato o su restaurante coinciden con la búsqueda.
bool matchesQuery(Dish d, Restaurant? r, String query) {
  final q = normalize(query);
  if (q.isEmpty) return true;
  final haystack = normalize(
    [
      d.name,
      d.description,
      d.section,
      categoryById(d.category).label,
      ...d.tags,
      ...d.ingredients,
      r?.name ?? '',
      r?.tagline ?? '',
    ].join(' '),
  );
  return q.split(RegExp(r'\s+')).every(haystack.contains);
}

/// Filtros combinables que se aplican a la lista de platos.
class DishFilters {
  const DishFilters({
    this.query = '',
    this.categories = const {},
    this.maxPrice,
    this.campusOnly = false,
    this.nutritionOnly = false,
    this.fastOnly = false,
    this.cheapOnly = false,
    this.topRated = false,
    this.openOnly = false,
    this.excludeAllergens = false,
    this.lifestyle = const {},
  });

  static const none = DishFilters();
  static const maxPriceMin = 5000;
  static const maxPriceMax = 40000;

  final String query;
  final Set<String> categories;
  final int? maxPrice;
  final bool campusOnly;
  final bool nutritionOnly;

  /// Preparación menor a 15 minutos.
  final bool fastOnly;

  /// Precio menor a $15.000.
  final bool cheapOnly;

  /// Valoración mínima 4,7.
  final bool topRated;
  final bool openOnly;
  final bool excludeAllergens;
  final Set<String> lifestyle;

  /// Cantidad de filtros activos, sin contar la búsqueda.
  int get activeCount =>
      categories.length +
      lifestyle.length +
      (maxPrice != null ? 1 : 0) +
      [
        campusOnly,
        nutritionOnly,
        fastOnly,
        cheapOnly,
        topRated,
        openOnly,
        excludeAllergens,
      ].where((b) => b).length;

  /// Indica si no hay ningún filtro ni búsqueda aplicada.
  bool get isEmpty => activeCount == 0 && query.trim().isEmpty;

  /// Copia los filtros cambiando solo los valores indicados.
  DishFilters copyWith({
    String? query,
    Set<String>? categories,
    int? maxPrice,
    bool clearMaxPrice = false,
    bool? campusOnly,
    bool? nutritionOnly,
    bool? fastOnly,
    bool? cheapOnly,
    bool? topRated,
    bool? openOnly,
    bool? excludeAllergens,
    Set<String>? lifestyle,
  }) {
    return DishFilters(
      query: query ?? this.query,
      categories: categories ?? this.categories,
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      campusOnly: campusOnly ?? this.campusOnly,
      nutritionOnly: nutritionOnly ?? this.nutritionOnly,
      fastOnly: fastOnly ?? this.fastOnly,
      cheapOnly: cheapOnly ?? this.cheapOnly,
      topRated: topRated ?? this.topRated,
      openOnly: openOnly ?? this.openOnly,
      excludeAllergens: excludeAllergens ?? this.excludeAllergens,
      lifestyle: lifestyle ?? this.lifestyle,
    );
  }

  /// Mantiene solo la búsqueda.
  DishFilters cleared() => DishFilters(query: query);
}

/// Datos externos que necesita el filtrado: restaurantes, hora y usuario.
class FilterContext {
  const FilterContext({
    required this.restaurantOf,
    required this.now,
    this.allergies = const {},
    this.universityId,
  });

  final Restaurant? Function(String id) restaurantOf;
  final DateTime now;
  final Set<String> allergies;
  final String? universityId;
}

/// Aplica los filtros a los platos y devuelve los que cumplen.
List<Dish> filterDishes(
  Iterable<Dish> dishes,
  DishFilters f,
  FilterContext ctx,
) {
  return dishes.where((d) {
    final r = ctx.restaurantOf(d.restaurantId);
    if (r == null) return false;
    if (!matchesQuery(d, r, f.query)) return false;
    if (f.categories.isNotEmpty && !f.categories.contains(d.category)) {
      return false;
    }
    if (f.maxPrice != null && d.price > f.maxPrice!) return false;
    if (f.cheapOnly && d.price >= 15000) return false;
    if (f.fastOnly && d.prepMin >= 15) return false;
    if (f.topRated && d.rating < 4.7) return false;
    if (f.openOnly && !isOpenAt(r, ctx.now)) return false;
    if (f.nutritionOnly && d.nutrition == null) return false;
    if (f.campusOnly) {
      if (r.campusId == null) return false;
      if (ctx.universityId != null && r.campusId != ctx.universityId) {
        return false;
      }
    }
    if (f.excludeAllergens && allergyConflicts(d, ctx.allergies).isNotEmpty) {
      return false;
    }
    if (!matchesAllLifestyles(d, f.lifestyle)) return false;
    return true;
  }).toList();
}
