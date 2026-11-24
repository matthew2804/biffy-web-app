import 'package:get_it/get_it.dart';

import '../../../core/utils/clock.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../domain/repositories/merchant_boxes_repository.dart';
import '../../../domain/repositories/notification_repository.dart';
import '../../../domain/repositories/profile_repository.dart';
import '../../../domain/usecases/get_courier_earnings.dart';
import '../../../domain/usecases/merchant_boxes_usecases.dart';
import '../../../domain/usecases/orders/get_delivery_evidence.dart';
import '../../../domain/usecases/orders/order_usecases.dart';
import '../../../domain/usecases/rate_order.dart';
import '../../../domain/usecases/rewards_usecases.dart';
import '../../../features/buyer/cart/bloc/cart_cubit.dart';
import '../../../features/buyer/cart/bloc/checkout_cubit.dart';
import '../../../features/buyer/notifications/notifications_cubit.dart';
import '../../../features/buyer/rewards/rewards_cubit.dart';
import '../../../features/buyer/tracking/delivery_evidence_cubit.dart';
import '../../../features/buyer/tracking/rate_order_cubit.dart';
import '../../../features/auth/bloc/login_cubit.dart';
import '../../../features/auth/bloc/register_cubit.dart';
import '../../../features/auth/bloc/university_verification_cubit.dart';
import '../../../features/courier/earnings/earnings_cubit.dart';
import '../../../features/orders/bloc/orders_bloc.dart';
import '../../../features/restaurant_owner/boxes/merchant_boxes_cubit.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/session_controller.dart';

/// Módulo de presentación: estado que consumen las pantallas.
///
/// - Controladores (`ChangeNotifier`, aún sin migrar) y `OrdersBloc`: un solo
///   objeto para toda la app (`LazySingleton`).
/// - Cubits de una pantalla: `Factory`, uno nuevo cada vez que se abre.
void registerPresentationModule(GetIt g) {
  _registerControllers(g);
  _registerBlocs(g);
}

/// Devuelve la dependencia si el módulo de datos la registró; si no, `null`.
T? _optional<T extends Object>(GetIt g) => g.isRegistered<T>() ? g<T>() : null;

/// Controladores compartidos por todas las pantallas.
void _registerControllers(GetIt g) {
  g.registerLazySingleton<NotificationCenter>(() {
    final repo = _optional<NotificationRepository>(g);
    return NotificationCenter(
      g<Clock>(),
      persist: repo?.save,
      onRead: repo?.markRead,
    );
  });
  g.registerLazySingleton<SessionController>(
    () => SessionController(
      g<AuthRepository>(),
      g<NotificationCenter>(),
      g<Clock>(),
      profile: _optional<ProfileRepository>(g),
      notificationsRepo: _optional<NotificationRepository>(g),
    ),
  );
  g.registerLazySingleton<CatalogController>(
    () => CatalogController(
      g<CatalogRepository>(),
      g<SessionController>(),
      g<Clock>(),
    ),
  );
  g.registerLazySingleton<CartCubit>(() => CartCubit(g<CatalogRepository>()));
}

/// Bloc de pedidos (global) y cubits de pantalla.
void _registerBlocs(GetIt g) {
  g.registerLazySingleton<OrdersBloc>(
    () => OrdersBloc(g<OrderUseCases>()),
    dispose: (bloc) => bloc.close(),
  );
  g.registerFactory<NotificationsCubit>(
    () => NotificationsCubit(
      center: g<NotificationCenter>(),
      session: g<SessionController>(),
    ),
  );
  g.registerFactory<RewardsCubit>(
    () => RewardsCubit(
      load: g<LoadRewards>(),
      redeem: g<RedeemReward>(),
      refreshBalance: g<SessionController>().refreshRemote,
    ),
  );
  g.registerFactoryParam<RateOrderCubit, RateOrderArgs, void>(
    (args, _) => RateOrderCubit(
      rateOrder: g<RateOrder>(),
      order: args.order,
      userId: args.userId,
      initialStars: args.initialStars,
    ),
  );
  g.registerFactoryParam<DeliveryEvidenceCubit, String, void>(
    (orderId, _) => DeliveryEvidenceCubit(
      getEvidence: g<GetDeliveryEvidence>(),
      orderId: orderId,
    ),
  );
  g.registerFactoryParam<EarningsCubit, String, void>(
    (courierId, _) => EarningsCubit(
      orders: g<OrdersBloc>(),
      courierId: courierId,
      now: () => g<CatalogController>().now,
      getEarnings: g<GetCourierEarnings>(),
    ),
  );
  g.registerFactory<MerchantBoxesCubit>(
    () => MerchantBoxesCubit(
      repo: g<MerchantBoxesRepository>(),
      load: g<LoadMerchantBoxes>(),
      add: g<AddDishToBox>(),
      claim: g<ClaimBoxPrize>(),
    ),
  );
  // Cubits de una sola pantalla (login, registro, campus y checkout).
  g.registerFactory<LoginCubit>(() => LoginCubit(g<SessionController>()));
  g.registerFactory<RegisterCubit>(() => RegisterCubit(g<SessionController>()));
  g.registerFactory<UniversityVerificationCubit>(
    () => UniversityVerificationCubit(g<SessionController>()),
  );
  g.registerFactory<CheckoutCubit>(
    () => CheckoutCubit(
      orders: g<OrdersBloc>(),
      session: g<SessionController>(),
      cart: g<CartCubit>(),
    ),
  );
}
