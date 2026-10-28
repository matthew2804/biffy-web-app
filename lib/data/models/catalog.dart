/// Modelos del catálogo: categorías, universidades, puntos, restaurantes y platos.
library;

/// Categoría de comida mostrada en el catálogo.
class FoodCategory {
  const FoodCategory(this.id, this.label, this.emoji, [this.imageAsset]);
  final String id;
  final String label;
  final String emoji;

  /// Foto representativa de la categoría; si falta se muestra el emoji.
  final String? imageAsset;
}

/// Universidad con dominio de correo para la verificación.
class University {
  const University({
    required this.id,
    required this.name,
    required this.domain,
    required this.city,
  });
  final String id;
  final String name;
  final String domain;
  final String city;
}

/// Punto de entrega de demostración (no se usa GPS real).
class DeliveryPoint {
  const DeliveryPoint({
    required this.id,
    required this.name,
    required this.detail,
    required this.lat,
    required this.lng,
    this.campusId,
  });
  final String id;
  final String name;
  final String detail;
  final double lat;
  final double lng;
  final String? campusId;
}

/// Medios de pago disponibles en la demo.
enum PaymentMethod {
  nequi('Nequi', '📱'),
  daviplata('Daviplata', '📲'),
  card('Tarjeta •••• 4521', '💳'),
  pse('PSE', '🏦'),
  cash('Efectivo', '💵');

  const PaymentMethod(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// Valores nutricionales de un plato.
class Nutrition {
  const Nutrition({
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
  });
  final int kcal;
  final int protein;
  final int carbs;
  final int fat;
}

/// Opción con precio adicional (tamaño, acompañante o extra).
class DishOption {
  const DishOption(this.id, this.label, this.price);
  final String id;
  final String label;
  final int price;
}

/// Sede de un restaurante visible en el catálogo.
class Restaurant {
  Restaurant({
    required this.id,
    required this.businessId,
    required this.name,
    required this.emoji,
    required this.tagline,
    required this.cuisine,
    required this.address,
    required this.rating,
    required this.prepMin,
    required this.lat,
    required this.lng,
    required this.radiusKm,
    required this.couriersNearby,
    required this.openHour,
    required this.closeHour,
    this.closedWeekdays = const [],
    this.campusId,
    this.studentDiscount = 0,
    this.paused = false,
    this.demo = false,
    this.campusDeliveryOnly = false,
    this.showsNutrition = false,
    this.imageAsset,
    this.branchName = 'Sede principal',
  });

  final String id;
  final String businessId;
  String name;
  final String emoji;
  String tagline;
  final String cuisine;
  String address;
  final double rating;
  final int prepMin;
  final double lat;
  final double lng;
  double radiusKm;
  int couriersNearby;
  int openHour;
  int closeHour;

  /// Días cerrados según `DateTime.weekday` (1 = lunes ... 7 = domingo).
  List<int> closedWeekdays;
  String? campusId;
  double studentDiscount;
  bool paused;
  final bool demo;
  final bool campusDeliveryOnly;
  bool showsNutrition;
  final String? imageAsset;
  String branchName;
}

/// Plato del menú de un restaurante.
class Dish {
  Dish({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.price,
    required this.emoji,
    required this.category,
    required this.section,
    this.prepMin = 15,
    this.rating = 4.6,
    this.ingredients = const [],
    this.allergens = const [],
    this.tags = const [],
    this.nutrition,
    this.sizes = const [],
    this.sides = const [],
    this.extras = const [],
    this.popular = false,
    this.featured = false,
    this.active = true,
    this.soldOut = false,
    this.portionLimit,
    this.soldToday = 0,
    this.imageAsset,
  });

  final String id;
  String restaurantId;
  String name;
  String description;
  int price;
  String emoji;
  String category;
  String section;
  int prepMin;
  double rating;
  List<String> ingredients;
  List<String> allergens;

  /// Etiquetas de estilo de vida: vegano, vegetariano, sin gluten, etc.
  List<String> tags;
  Nutrition? nutrition;

  /// Tamaños (selección única, el primero es el predeterminado).
  List<DishOption> sizes;

  /// Acompañantes (selección única opcional).
  List<DishOption> sides;

  /// Extras (selección múltiple).
  List<DishOption> extras;
  bool popular;
  bool featured;

  /// Publicado en el menú (visible para compradores).
  bool active;

  /// Marcado como agotado por el restaurante.
  bool soldOut;
  int? portionLimit;
  int soldToday;
  String? imageAsset;

  /// `true` si ya se agotó el límite de porciones del día.
  bool get reachedPortionLimit =>
      portionLimit != null && soldToday >= portionLimit!;

  /// Disponible para agregar al carrito.
  bool get orderable => active && !soldOut && !reachedPortionLimit;

  /// Porciones que quedan hoy; `null` si no hay límite.
  int? get remainingPortions =>
      portionLimit == null ? null : (portionLimit! - soldToday).clamp(0, 9999);

  /// Busca una opción (tamaño, acompañante o extra) por id.
  DishOption? optionById(String id) {
    for (final o in [...sizes, ...sides, ...extras]) {
      if (o.id == id) return o;
    }
    return null;
  }
}
