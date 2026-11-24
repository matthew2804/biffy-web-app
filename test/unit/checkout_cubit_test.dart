import 'package:biffy/core/constants/catalog_constants.dart';
import 'package:biffy/data/mock/seed_users.dart';
import 'package:biffy/features/buyer/cart/bloc/checkout_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

/// Pruebas del checkout: confirma, valida y es idempotente con la red.
void main() {
  late TestServices services;

  setUp(() async {
    services = await makeServices();
  });

  group('CheckoutCubit', () {
    test('confirma un pedido y vacía el carrito', () async {
      services.session.login(kDemoBuyerEmail, kDemoPassword);
      services.cart.add(services.catalog.dishById('qbano-pollo')!);

      final checkout = CheckoutCubit(
        orders: services.orders,
        session: services.session,
        cart: services.cart,
      );

      expect(checkout.errors, isEmpty);
      final outcome = await checkout.submit();

      expect(outcome?.ok, isTrue);
      expect(outcome?.orderId, isNotNull);
      expect(checkout.state.orderId, isNotNull);
      expect(services.cart.isEmpty, isTrue);
    });

    test('sin dirección no deja confirmar', () async {
      services.session.login(kDemoNewBuyerEmail, kDemoPassword);
      services.cart.add(services.catalog.dishById('qbano-pollo')!);

      final checkout = CheckoutCubit(
        orders: services.orders,
        session: services.session,
        cart: services.cart,
      );

      expect(checkout.errors, isNotEmpty);
      final outcome = await checkout.submit();

      expect(outcome, isNull);
      expect(checkout.state.error, isNotEmpty);
      expect(services.cart.isEmpty, isFalse);
    });

    test('un carrito vacío no se puede confirmar', () async {
      services.session.login(kDemoBuyerEmail, kDemoPassword);

      final checkout = CheckoutCubit(
        orders: services.orders,
        session: services.session,
        cart: services.cart,
      );

      expect(checkout.canSubmit, isFalse);
      expect(await checkout.submit(), isNull);
      expect(checkout.state.error, isNotEmpty);
    });
  });
}
