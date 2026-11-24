import 'package:biffy/app/di/injection.dart';
import 'package:biffy/data/repositories/auth_repository.dart';
import 'package:biffy/data/repositories/catalog_repository.dart';
import 'package:biffy/data/repositories/in_memory_order_repository.dart';
import 'package:biffy/domain/repositories/order_repository.dart';
import 'package:biffy/domain/repositories/payment_repository.dart';
import 'package:biffy/domain/repositories/rewards_repository.dart';
import 'package:biffy/domain/usecases/orders/order_usecases.dart';
import 'package:biffy/domain/usecases/payments/start_payment.dart';
import 'package:biffy/domain/usecases/rate_order.dart';
import 'package:biffy/features/buyer/notifications/notifications_cubit.dart';
import 'package:biffy/features/buyer/tracking/rate_order_cubit.dart';
import 'package:biffy/features/courier/earnings/earnings_cubit.dart';
import 'package:biffy/features/orders/bloc/orders_bloc.dart';
import 'package:biffy/features/buyer/cart/bloc/cart_cubit.dart';
import 'package:biffy/shared/state/catalog_controller.dart';
import 'package:biffy/shared/state/notification_center.dart';
import 'package:biffy/shared/state/session_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_order_repository.dart';
import '../helpers.dart';

/// Pruebas del contenedor GetIt: qué se registra, con qué ciclo de vida y cómo
/// se sustituye una dependencia por un doble de prueba.
void main() {
  setUp(() async {
    await makeServices();
  });

  group('Sin credenciales de Supabase se usa memoria (demo)', () {
    test('los repositorios se piden por su interfaz y son en memoria', () {
      expect(getIt<OrderRepository>(), isA<InMemoryOrderRepository>());
      expect(getIt<OrderRepository>().isRemote, isFalse);
      expect(getIt<AuthRepository>().isRemote, isFalse);
      expect(getIt<CatalogRepository>(), isA<InMemoryCatalogRepository>());
    });

    test('los repositorios de Supabase no se registran en demo', () {
      expect(getIt.isRegistered<RewardsRepository>(), isFalse);
    });
  });

  group('Ciclo de vida', () {
    test('repositorios y controladores son una sola instancia', () {
      expect(getIt<OrderRepository>(), same(getIt<OrderRepository>()));
      expect(getIt<SessionController>(), same(getIt<SessionController>()));
      expect(getIt<CatalogController>(), same(getIt<CatalogController>()));
      expect(getIt<CartCubit>(), same(getIt<CartCubit>()));
      expect(getIt<PaymentRepository>(), same(getIt<PaymentRepository>()));
      expect(getIt<NotificationCenter>(), same(getIt<NotificationCenter>()));
      expect(getIt<OrdersBloc>(), same(getIt<OrdersBloc>()));
    });

    test('los casos de uso son Factory: cada petición crea uno nuevo', () {
      expect(getIt<OrderUseCases>(), isNot(same(getIt<OrderUseCases>())));
      expect(getIt<RateOrder>(), isNot(same(getIt<RateOrder>())));
      expect(getIt<StartPayment>(), isNot(same(getIt<StartPayment>())));
    });

    test('los cubits de pantalla son Factory', () {
      final a = getIt<NotificationsCubit>();
      final b = getIt<NotificationsCubit>();
      addTearDown(a.close);
      addTearDown(b.close);
      expect(a, isNot(same(b)));
    });

    test('los cubits con datos de la pantalla reciben sus parámetros', () {
      final earnings = getIt<EarningsCubit>(param1: 'u-andres');
      addTearDown(earnings.close);
      expect(earnings.courierId, 'u-andres');

      final order = getIt<OrdersBloc>().all.first;
      final rate = getIt<RateOrderCubit>(
        param1: RateOrderArgs(
          order: order,
          userId: order.buyerId,
          initialStars: 3,
        ),
      );
      addTearDown(rate.close);
      expect(rate.order, same(order));
      expect(rate.state.stars, 3);
    });
  });

  group('Dobles de prueba', () {
    test(
      'se puede sustituir el repositorio de pedidos por uno falso',
      () async {
        final fake = FakeOrderRepository();
        await makeServices(seed: false);
        getIt.registerLazySingleton<OrderRepository>(() => fake);

        expect(getIt<OrderRepository>(), same(fake));
        // Los casos de uso y el Bloc nuevos usan el doble sin tocar nada más.
        expect(getIt<OrderUseCases>().repo, same(fake));
      },
    );

    test('reset deja el contenedor vacío para la prueba siguiente', () async {
      await getIt.reset();
      expect(getIt.isRegistered<OrderRepository>(), isFalse);
      expect(getIt.isRegistered<SessionController>(), isFalse);
    });
  });
}
