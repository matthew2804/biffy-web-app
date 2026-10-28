import '../core/constants/catalog_constants.dart';
import '../core/utils/format.dart';
import '../data/models/catalog.dart';
import 'catalog_rules.dart';
import 'recommendation.dart';

/// Respuesta del asistente local basado en reglas (no hay un LLM conectado).
class AssistantReply {
  const AssistantReply(this.text, [this.dishes = const []]);
  final String text;
  final List<Dish> dishes;
}

const _categoryWords = {
  'pizza': 'pizza',
  'sandwich': 'sandwich',
  'sanduche': 'sandwich',
  'hamburguesa': 'hamburguesa',
  'burger': 'hamburguesa',
  'saludable': 'saludable',
  'bowl': 'saludable',
  'ensalada': 'saludable',
  'cafe': 'cafe',
  'postre': 'postres',
  'dulce': 'postres',
  'taco': 'mexicana',
  'burrito': 'mexicana',
  'mexicana': 'mexicana',
  'sushi': 'asiatica',
  'ramen': 'asiatica',
  'asiatica': 'asiatica',
  'almuerzo': 'almuerzo',
  'corrientazo': 'almuerzo',
};

const _lifestyleWords = {
  'vegetarian': 'vegetariano',
  'vegan': 'vegano',
  'sin gluten': 'sin gluten',
  'proteina': 'alto en proteína',
  'proteico': 'alto en proteína',
  'calorias': 'bajo en calorías',
  'light': 'bajo en calorías',
};

/// Extrae el presupuesto mencionado en la pregunta ("15 mil", "$20.000").
int? _parseBudget(String q) {
  final mil = RegExp(r'(\d{1,3})\s*(mil|k)\b').firstMatch(q);
  if (mil != null) return int.parse(mil.group(1)!) * 1000;
  final full = RegExp(r'\$?\s*(\d{1,3}(?:[.,]\d{3})+|\d{4,6})').firstMatch(q);
  if (full != null) {
    return int.tryParse(full.group(1)!.replaceAll(RegExp(r'[.,]'), ''));
  }
  return null;
}

/// Extrae los minutos máximos mencionados en la pregunta.
int? _parseMinutes(String q) {
  final m = RegExp(r'(\d{1,3})\s*(min|minutos)').firstMatch(q);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Busca el plato del catálogo cuyo nombre aparece en la pregunta.
Dish? _findDishByName(String q, List<Dish> dishes) {
  Dish? best;
  var bestLen = 0;
  for (final d in dishes) {
    final name = normalize(d.name);
    if (q.contains(name) && name.length > bestLen) {
      best = d;
      bestLen = name.length;
    }
  }
  return best;
}

/// Interpreta preguntas frecuentes usando solo los datos locales.
AssistantReply answer(String question, RecommendationInput input) {
  final q = normalize(question);
  if (q.isEmpty) {
    return const AssistantReply('Escríbeme qué se te antoja 🐝');
  }

  // «¿Qué contiene el Bowl Proteico?»
  if (q.contains('contiene') ||
      q.contains('ingrediente') ||
      q.contains('que tiene') ||
      q.contains('alergeno')) {
    final dish = _findDishByName(q, input.dishes);
    if (dish == null) {
      return const AssistantReply(
        'No encontré ese plato en tu zona. Prueba con el nombre exacto, por ejemplo «¿Qué contiene el Bowl Proteico?».',
      );
    }
    final allergens = dish.allergens.isEmpty
        ? 'El restaurante no declaró alérgenos en esta demo (no garantiza ausencia de contaminación cruzada).'
        : 'Alérgenos declarados: ${dish.allergens.join(', ')}.';
    final ingredients = dish.ingredients.isEmpty
        ? 'No hay ingredientes registrados.'
        : 'Ingredientes: ${dish.ingredients.join(', ')}.';
    return AssistantReply(
      '${dish.name} (${cop(dish.price)}). $ingredients $allergens',
      [dish],
    );
  }

  var pool = input.dishes.where((d) => d.orderable).toList();
  final applied = <String>[];
  pool = pool
      .where((d) => allergyConflicts(d, input.prefs.allergies).isEmpty)
      .toList();
  if (input.prefs.allergies.isNotEmpty) applied.add('sin tus alérgenos');

  final budget = _parseBudget(q);
  final wantsCheap = q.contains('barat') || q.contains('economic');
  if (budget != null) {
    pool = pool.where((d) => d.price <= budget).toList();
    applied.add('hasta ${cop(budget)}');
  } else if (wantsCheap) {
    pool = pool.where((d) => d.price < 15000).toList();
    applied.add('menos de ${cop(15000)}');
  }

  final categories = {
    for (final e in _categoryWords.entries)
      if (q.contains(e.key)) e.value,
  };
  if (categories.isNotEmpty) {
    pool = pool.where((d) => categories.contains(d.category)).toList();
    applied.add(
      categories.map((c) => categoryById(c).label.toLowerCase()).join(' o '),
    );
  }

  final styles = {
    for (final e in _lifestyleWords.entries)
      if (q.contains(e.key)) e.value,
  };
  if (styles.isNotEmpty) {
    pool = pool.where((d) => matchesAllLifestyles(d, styles)).toList();
    applied.add(styles.join(', '));
  }
  final healthy = q.contains('saludable') || q.contains('sano');

  final minutes = _parseMinutes(q);
  if (minutes != null) {
    pool = pool.where((d) {
      final r = input.restaurantOf(d.restaurantId);
      return r != null &&
          etaMinutes(r, input.point, prepMin: d.prepMin) <= minutes;
    }).toList();
    applied.add('llega en $minutes min o menos');
  }

  if (applied.length <= (input.prefs.allergies.isNotEmpty ? 1 : 0) &&
      !healthy) {
    final recs = recommend(input);
    return AssistantReply(
      'Puedo ayudarte con presupuesto («algo por menos de 15 mil»), tipo de comida («pizza vegetariana»), ingredientes («¿qué contiene el Bowl Proteico?») o tiempo («descanso de 20 minutos»). Mientras tanto, esto es lo mejor para ti:',
      recs.map((r) => r.dish).toList(),
    );
  }

  if (pool.isEmpty) {
    return AssistantReply(
      'No encontré platos disponibles en tu zona que cumplan: ${applied.join(' · ')}. Prueba ampliando el presupuesto o cambiando el punto de entrega.',
    );
  }
  final ranked = recommend(
    RecommendationInput(
      dishes: pool,
      restaurantOf: input.restaurantOf,
      prefs: input.prefs,
      point: input.point,
      historyDishIds: input.historyDishIds,
      favoriteDishIds: input.favoriteDishIds,
      universityId: input.universityId,
      now: input.now,
    ),
    mode: healthy ? RecommendationMode.healthy : RecommendationMode.tastes,
  );
  final dishes = ranked.isEmpty
      ? pool.take(3).toList()
      : ranked.map((r) => r.dish).toList();
  return AssistantReply(
    'Encontré ${pool.length} ${pool.length == 1 ? 'opción' : 'opciones'} (${applied.join(' · ')}). Mis favoritas:',
    dishes,
  );
}
