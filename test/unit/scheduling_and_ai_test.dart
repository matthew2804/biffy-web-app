import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/core/utils/clock.dart';
import 'package:biffy/domain/catalog_rules.dart';
import 'package:biffy/data/mock/seed_catalog.dart';
import 'package:biffy/data/models/user.dart';
import 'package:biffy/domain/assistant.dart';
import 'package:biffy/domain/recommendation.dart';
import 'package:biffy/domain/scheduling.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final restaurants = {for (final r in seedRestaurants()) r.id: r};
  final now = DateTime(2026, 10, 20, 12); // martes

  group('Programación', () {
    final rosa = restaurants['dona-rosa']!; // 11–16, cerrado domingo

    test('solo horarios futuros y dentro del horario', () {
      final slots = slotsFor(rosa, now, now);
      expect(slots, isNotEmpty);
      expect(slots.every((s) => s.isAfter(now)), isTrue);
      expect(slots.every((s) => s.hour >= 11 && s.hour < 16), isTrue);
    });

    test('excluye días cerrados', () {
      final days = availableDays(rosa, now);
      expect(days.any((d) => d.weekday == DateTime.sunday), isFalse);
    });

    test('rechaza una hora pasada', () {
      expect(
        isValidSchedule(rosa, DateTime(2026, 10, 20, 11, 30), now),
        isFalse,
      );
      expect(
        isValidSchedule(rosa, DateTime(2026, 10, 21, 11, 30), now),
        isTrue,
      );
    });

    test('al cambiar de día se elimina la hora inválida', () {
      final tomorrow1130 = DateTime(2026, 10, 21, 11, 30);
      // Hoy a las 11:30 ya pasó: se borra.
      expect(keepTimeIfValid(rosa, now, tomorrow1130, now), isNull);
      // Pasado mañana sigue siendo válida.
      expect(
        keepTimeIfValid(rosa, DateTime(2026, 10, 22), tomorrow1130, now),
        DateTime(2026, 10, 22, 11, 30),
      );
    });
  });

  group('Recomendaciones', () {
    final dishes = seedDishes()
        .where((d) => restaurants[d.restaurantId]!.lat < 4)
        .toList(); // zona Cali
    RecommendationInput input(
      Preferences p, {
      List<String> history = const [],
    }) => RecommendationInput(
      dishes: dishes,
      restaurantOf: (id) => restaurants[id],
      prefs: p,
      point: pointById('icesi-biblioteca'),
      historyDishIds: history,
      now: now,
    );

    test('nunca recomienda alérgenos declarados', () {
      final recs = recommend(
        input(const Preferences(allergies: {'gluten', 'lácteos'})),
        limit: 20,
      );
      expect(recs, isNotEmpty);
      expect(
        recs.any(
          (r) =>
              r.dish.allergens.contains('gluten') ||
              r.dish.allergens.contains('lácteos'),
        ),
        isFalse,
      );
    });

    test('respeta restricción vegana', () {
      final recs = recommend(
        input(const Preferences(lifestyle: {'vegano'})),
        limit: 20,
      );
      expect(recs.every((r) => r.dish.tags.contains('vegano')), isTrue);
    });

    test('prioriza gustos e historial', () {
      final recs = recommend(
        input(
          const Preferences(likes: {'pizza'}),
          history: ['bowl-proteico', 'bowl-proteico'],
        ),
      );
      expect(recs.map((r) => r.dish.id), contains('bowl-proteico'));
      expect(recs.where((r) => r.dish.category == 'pizza'), isNotEmpty);
    });

    test('sin perfil devuelve populares y coincidencia acotada', () {
      final recs = recommend(input(const Preferences()));
      expect(recs, hasLength(3));
      expect(recs.every((r) => r.match >= 55 && r.match <= 97), isTrue);
    });

    test('modo económico ordena por precio', () {
      final recs = recommend(
        input(const Preferences()),
        mode: RecommendationMode.cheap,
      );
      expect(recs.first.dish.price <= recs.last.dish.price, isTrue);
    });

    test('asistente: presupuesto, ingredientes y tiempo', () {
      final cheap = answer(
        'Algo barato por menos de 15 mil',
        input(const Preferences()),
      );
      expect(cheap.dishes, isNotEmpty);
      expect(cheap.dishes.every((d) => d.price <= 15000), isTrue);

      final bowl = answer(
        '¿Qué contiene el Bowl Proteico?',
        input(const Preferences()),
      );
      expect(bowl.text, contains('Quinoa'));
      expect(bowl.text, contains('huevo'));

      final pizza = answer('Pizza vegetariana', input(const Preferences()));
      expect(
        pizza.dishes.every(
          (d) => d.category == 'pizza' && d.tags.contains('vegetariano'),
        ),
        isTrue,
      );

      final quick = answer(
        '¿Qué me recomiendas para mi descanso de 20 minutos?',
        input(const Preferences()),
      );
      expect(quick.dishes, isNotEmpty);
    });
  });

  test('horario de demostración fija las 12 y abre restaurantes', () {
    final clock = Clock.fixed(DateTime(2026, 10, 20, 23, 40));
    final qbano = restaurants['qbano-icesi']!;
    expect(isOpenAt(qbano, clock.now()), isFalse);
    clock.simulateLunch = true;
    expect(clock.now(), DateTime(2026, 10, 20, 12, 40));
    expect(isOpenAt(qbano, clock.now()), isTrue);
  });
}
