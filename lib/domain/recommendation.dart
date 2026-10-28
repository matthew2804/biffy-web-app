import 'dart:math' as math;

import '../core/constants/catalog_constants.dart';
import '../core/utils/format.dart';
import '../data/models/catalog.dart';
import '../data/models/user.dart';
import 'catalog_rules.dart';

/// Modos de recomendación que ofrece el motor local.
enum RecommendationMode {
  tastes('Mis gustos', '💛'),
  fast('Rápido', '⚡'),
  cheap('Económico', '💸'),
  healthy('Saludable', '🥗'),
  favorites('Favoritos', '❤️'),
  surprise('Sorpréndeme', '🎲');

  const RecommendationMode(this.label, this.emoji);
  final String label;
  final String emoji;
}

/// Datos de entrada necesarios para calcular recomendaciones.
class RecommendationInput {
  const RecommendationInput({
    required this.dishes,
    required this.restaurantOf,
    required this.prefs,
    required this.point,
    this.historyDishIds = const [],
    this.favoriteDishIds = const {},
    this.universityId,
    this.now,
    this.seed = 0,
  });

  /// Platos ya filtrados por cobertura (zona de entrega).
  final List<Dish> dishes;
  final Restaurant? Function(String) restaurantOf;
  final Preferences prefs;
  final DeliveryPoint point;
  final List<String> historyDishIds;
  final Set<String> favoriteDishIds;
  final String? universityId;
  final DateTime? now;
  final int seed;
}

/// Plato recomendado con su puntaje, coincidencia y motivos.
class Recommendation {
  const Recommendation({
    required this.dish,
    required this.score,
    required this.match,
    required this.reasons,
  });
  final Dish dish;
  final double score;

  /// Coincidencia estimada del prototipo (0–100), no es una métrica real.
  final int match;
  final List<String> reasons;
}

/// Motor de recomendaciones local. Prioridad:
/// 1) alergias y restricciones, 2) gustos, 3) historial, 4) presupuesto,
/// 5) tiempo, 6) universidad y disponibilidad, 7) popularidad y valoración.
List<Recommendation> recommend(
  RecommendationInput input, {
  RecommendationMode mode = RecommendationMode.tastes,
  int limit = 3,
}) {
  final prefs = input.prefs;
  final strict = prefs.lifestyle.intersection(kStrictLifestyles);
  final historyCount = <String, int>{};
  for (final id in input.historyDishIds) {
    historyCount[id] = (historyCount[id] ?? 0) + 1;
  }
  final historyCategories = {
    for (final d in input.dishes)
      if (historyCount.containsKey(d.id)) d.category,
  };
  final hasProfile = !prefs.isEmpty || historyCount.isNotEmpty;
  final rnd = math.Random(input.seed);

  final results = <Recommendation>[];
  for (final d in input.dishes) {
    if (!d.orderable) continue;
    final r = input.restaurantOf(d.restaurantId);
    if (r == null) continue;
    // 1. Restricciones duras.
    if (allergyConflicts(d, prefs.allergies).isNotEmpty) continue;
    if (!matchesAllLifestyles(d, strict)) continue;
    if (mode == RecommendationMode.favorites &&
        !input.favoriteDishIds.contains(d.id)) {
      continue;
    }
    if (mode == RecommendationMode.healthy &&
        d.category != 'saludable' &&
        !d.tags.contains('bajo en calorías') &&
        !(d.nutrition != null && d.nutrition!.kcal <= 600)) {
      continue;
    }

    var score = 0.0;
    final reasons = <String>[];
    if (prefs.allergies.isNotEmpty) reasons.add('Sin tus alérgenos declarados');
    if (strict.isNotEmpty) reasons.add('Cumple: ${strict.join(', ')}');

    // 2. Gustos.
    if (prefs.likes.contains(d.category)) {
      score += 30;
      reasons.add('Te gusta ${categoryById(d.category).label.toLowerCase()}');
    }
    for (final s in prefs.lifestyle.difference(kStrictLifestyles)) {
      if (matchesLifestyle(d, s)) {
        score += 8;
        reasons.add(capitalize(s));
      }
    }
    // 3. Historial.
    final times = historyCount[d.id] ?? 0;
    if (times > 0) {
      score += 18 + math.min(times, 3) * 2;
      reasons.add('Lo pediste $times ${times == 1 ? 'vez' : 'veces'}');
    } else if (historyCategories.contains(d.category)) {
      score += 8;
    }
    // 4. Presupuesto.
    if (d.price <= prefs.budget) {
      score += 14;
      if (!prefs.isEmpty) {
        reasons.add('Dentro de tu presupuesto (${cop(prefs.budget)})');
      }
    } else {
      score -= 18;
    }
    // 5. Tiempo.
    final eta = etaMinutes(r, input.point, prepMin: d.prepMin);
    score += math.max(0, 12 - eta / 4);
    // 6. Universidad y disponibilidad.
    if (input.universityId != null && r.campusId == input.universityId) {
      score += 10;
      reasons.add('Cerca de tu campus');
    }
    if (input.now != null && !isOpenAt(r, input.now!)) {
      score -= 25;
      reasons.add('Cerrado ahora · puedes programarlo');
    }
    // 7. Popularidad y valoración.
    if (d.popular) score += 8;
    score += (d.rating - 4) * 10;

    switch (mode) {
      case RecommendationMode.fast:
        score = 100 - eta * 2.0 + d.rating;
        reasons.insert(0, 'Llega en ~$eta min');
      case RecommendationMode.cheap:
        score = 100 - d.price / 500 + d.rating;
        reasons.insert(0, 'Precio bajo: ${cop(d.price)}');
      case RecommendationMode.healthy:
        score += 20;
        reasons.insert(0, 'Opción saludable');
      case RecommendationMode.favorites:
        score += 30;
        reasons.insert(0, 'Está en tus favoritos');
      case RecommendationMode.surprise:
        score = rnd.nextDouble() * 100;
        reasons.insert(0, 'Elegido al azar entre opciones seguras');
      case RecommendationMode.tastes:
        if (!hasProfile) {
          reasons.insert(
            0,
            d.popular ? 'Lo más pedido en tu zona' : 'Bien valorado en tu zona',
          );
        }
    }
    if (reasons.isEmpty) reasons.add('Disponible en tu zona');
    results.add(
      Recommendation(dish: d, score: score, match: 0, reasons: reasons),
    );
  }

  results.sort((a, b) => b.score.compareTo(a.score));
  final top = results.take(limit).toList();
  if (top.isEmpty) return top;
  final best = top.first.score;
  return [
    for (final (i, rec) in top.indexed)
      Recommendation(
        dish: rec.dish,
        score: rec.score,
        // Indicador heurístico, acotado a 55–97 %.
        match: (97 - i * 4 - (best - rec.score).clamp(0, 30)).round().clamp(
          55,
          97,
        ),
        reasons: rec.reasons.take(3).toList(),
      ),
  ];
}
