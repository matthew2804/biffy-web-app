import 'package:biffy/data/models/order.dart';
import 'package:biffy/domain/order_rules.dart';
import 'package:biffy/domain/repositories/review_repository.dart';
import 'package:biffy/domain/usecases/rate_order.dart';
import 'package:biffy/features/buyer/tracking/rate_order_cubit.dart';
import 'package:biffy/shared/adapters/review_adapters.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Repositorio falso que responde lo que se le indique.
class _FakeReviews implements ReviewRepository {
  _FakeReviews(this.outcome);
  final ReviewOutcome outcome;

  @override
  Future<ReviewOutcome> submit(Order order, int stars, String comment) async =>
      outcome;
}

void main() {
  late AppServices s;
  late Order o;

  setUp(() async {
    s = makeServices();
    o = await deliverQbano(s);
  });

  RateOrderCubit cubit(ReviewOutcome outcome, {int stars = 0}) =>
      RateOrderCubit(
        rateOrder: RateOrder(
          _FakeReviews(outcome),
          CatalogRatingAdapter(s.catalog),
          LocalReviewNotifier(s.notifications, s.catalog),
        ),
        order: o,
        userId: o.buyerId,
        initialStars: stars,
      );

  test('empieza con las estrellas elegidas en la tarjeta', () {
    final c = cubit(const ReviewOutcome(RateResult.ok), stars: 4);
    expect(c.state, const RateOrderState(stars: 4));
    expect(c.state.canSubmit, isTrue);
    expect(cubit(const ReviewOutcome(RateResult.ok)).state.canSubmit, isFalse);
  });

  blocTest<RateOrderCubit, RateOrderState>(
    'elegir estrellas cambia el estado',
    build: () => cubit(const ReviewOutcome(RateResult.ok)),
    act: (c) => c
      ..selectStars(3)
      ..selectStars(5),
    expect: () => const [RateOrderState(stars: 3), RateOrderState(stars: 5)],
  );

  blocTest<RateOrderCubit, RateOrderState>(
    'enviar pasa por enviando → listo y actualiza el pedido',
    build: () =>
        cubit(const ReviewOutcome(RateResult.ok, branchRating: 4.2), stars: 5),
    act: (c) => c.submit('Rico'),
    expect: () => const [
      RateOrderState(stars: 5, status: RateStatus.sending),
      RateOrderState(stars: 5, status: RateStatus.done),
    ],
    verify: (_) {
      expect(o.rating, 5);
      expect(o.review, 'Rico');
      expect(s.catalog.restaurantById(o.restaurantId)!.rating, 4.2);
    },
  );

  blocTest<RateOrderCubit, RateOrderState>(
    'si la base responde error queda en fallido y el pedido no cambia',
    build: () => cubit(const ReviewOutcome(RateResult.offline), stars: 5),
    act: (c) => c.submit(),
    expect: () => const [
      RateOrderState(stars: 5, status: RateStatus.sending),
      RateOrderState(
        stars: 5,
        status: RateStatus.failed,
        error: RateResult.offline,
      ),
    ],
    verify: (_) => expect(o.rating, isNull),
  );

  blocTest<RateOrderCubit, RateOrderState>(
    'sin estrellas no envía nada',
    build: () => cubit(const ReviewOutcome(RateResult.ok)),
    act: (c) => c.submit(),
    expect: () => const <RateOrderState>[],
  );
}
