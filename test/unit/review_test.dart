import 'package:biffy/domain/order_rules.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  group('Reglas de calificación', () {
    late AppServices s;
    setUp(() => s = makeServices());

    test('solo el comprador califica su pedido entregado, una vez', () {
      final pending = placeQbano(s);
      expect(
        checkRating(pending, pending.buyerId, 5, ''),
        RateResult.invalidState,
      );
      final o = deliverQbano(s);
      expect(checkRating(o, 'otro', 5, ''), RateResult.forbidden);
      expect(checkRating(null, o.buyerId, 5, ''), RateResult.notFound);
      expect(checkRating(o, o.buyerId, 0, ''), RateResult.invalidRating);
      expect(checkRating(o, o.buyerId, 6, ''), RateResult.invalidRating);
      expect(
        checkRating(o, o.buyerId, 4, 'a' * (kMaxReviewComment + 1)),
        RateResult.commentTooLong,
      );
      expect(checkRating(o, o.buyerId, 4, ''), RateResult.ok);
      o.rating = 4;
      expect(checkRating(o, o.buyerId, 5, ''), RateResult.alreadyRated);
    });

    test('el promedio tiene un decimal como en la base', () {
      expect(averageRating(const []), isNull);
      expect(averageRating(const [4]), 4.0);
      expect(averageRating(const [4, 5]), 4.5);
      expect(averageRating(const [5, 5, 4]), 4.7);
      expect(averageRating(const [1, 2]), 1.5);
    });

    test('traduce los códigos del RPC rate_order', () {
      expect(rateResultFrom('ok'), RateResult.ok);
      expect(rateResultFrom('already_rated'), RateResult.alreadyRated);
      expect(rateResultFrom('forbidden'), RateResult.forbidden);
      expect(rateResultFrom('invalid_state'), RateResult.invalidState);
      expect(rateResultFrom('comment_too_long'), RateResult.commentTooLong);
      expect(rateResultFrom(null), RateResult.offline);
    });
  });

  group('OrderService.rateOrder', () {
    late AppServices s;
    setUp(() => s = makeServices());

    test(
      'guarda la reseña, actualiza el promedio y avisa al restaurante',
      () async {
        final o = deliverQbano(s);
        final before = s.notifications.all.length;
        final res = await s.orders.rateOrder(
          o.id,
          o.buyerId,
          4,
          comment: '  Muy rico  ',
        );
        expect(res, RateResult.ok);
        expect(o.rating, 4);
        expect(o.review, 'Muy rico');
        expect(s.catalog.restaurantById(o.restaurantId)!.rating, 4.0);
        expect(s.notifications.all.length, before + 1);

        final o2 = deliverQbano(s);
        await s.orders.rateOrder(o2.id, o2.buyerId, 5);
        expect(s.catalog.restaurantById(o.restaurantId)!.rating, 4.5);
      },
    );

    test('no deja calificar dos veces ni pedidos ajenos', () async {
      final o = deliverQbano(s);
      expect(await s.orders.rateOrder(o.id, o.buyerId, 5), RateResult.ok);
      expect(
        await s.orders.rateOrder(o.id, o.buyerId, 1),
        RateResult.alreadyRated,
      );
      expect(o.rating, 5);
      expect(
        await s.orders.rateOrder(o.id, 'u-andres', 1),
        RateResult.forbidden,
      );
    });
  });
}
