import 'package:get_it/get_it.dart';

import '../../../core/utils/clock.dart';
import '../../../domain/ports/order_ports.dart';
import '../../../domain/ports/review_ports.dart';
import '../../../domain/repositories/merchant_boxes_repository.dart';
import '../../../domain/repositories/order_repository.dart';
import '../../../domain/repositories/payment_repository.dart';
import '../../../domain/repositories/review_repository.dart';
import '../../../domain/repositories/rewards_repository.dart';
import '../../../domain/usecases/get_courier_earnings.dart';
import '../../../domain/usecases/merchant_boxes_usecases.dart';
import '../../../domain/usecases/orders/get_delivery_evidence.dart';
import '../../../domain/usecases/orders/order_usecases.dart';
import '../../../domain/usecases/payments/check_payment_status.dart';
import '../../../domain/usecases/payments/retry_payment.dart';
import '../../../domain/usecases/payments/start_payment.dart';
import '../../../domain/usecases/rate_order.dart';
import '../../../domain/usecases/rewards_usecases.dart';
import '../../../shared/adapters/order_adapters.dart';
import '../../../shared/adapters/review_adapters.dart';
import '../../../shared/adapters/server_order_notifier.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/session_controller.dart';

/// Módulo de dominio: puertos (con sus adaptadores) y casos de uso.
///
/// Los puertos son `LazySingleton` y se piden siempre por su interfaz; los
/// casos de uso son `Factory`: no guardan estado, cada petición crea uno nuevo.
void registerDomainModule(GetIt g) {
  _registerPorts(g);
  _registerUseCases(g);
}

/// Conecta los puertos del dominio con los controladores de la app.
void _registerPorts(GetIt g) {
  g.registerLazySingleton<OrderCatalogPort>(
    () => CatalogOrderAdapter(g<CatalogController>()),
  );
  g.registerLazySingleton<OrderBuyerPort>(
    () => SessionOrderAdapter(g<SessionController>()),
  );
  g.registerLazySingleton<OrderWalletPort>(
    () => SessionOrderAdapter(g<SessionController>()),
  );
  // Con servidor los avisos los crea la base (0022); en demo, la app.
  g.registerLazySingleton<OrderNotifier>(
    () => g<OrderRepository>().isRemote
        ? const ServerOrderNotifier()
        : NotificationOrderAdapter(g<NotificationCenter>(), demo: true),
  );
  g.registerLazySingleton<BranchRatingPort>(
    () => CatalogRatingAdapter(g<CatalogController>()),
  );
  g.registerLazySingleton<ReviewNotifier>(
    () => g<OrderRepository>().isRemote
        ? const ServerReviewNotifier()
        : LocalReviewNotifier(g<NotificationCenter>(), g<CatalogController>()),
  );
}

/// Un caso de uso nuevo por cada petición al contenedor.
void _registerUseCases(GetIt g) {
  g.registerFactory<OrderUseCases>(
    () => OrderUseCases(
      repo: g<OrderRepository>(),
      catalog: g<OrderCatalogPort>(),
      buyers: g<OrderBuyerPort>(),
      wallet: g<OrderWalletPort>(),
      notifier: g<OrderNotifier>(),
      clock: g<Clock>(),
    ),
  );
  g.registerFactory<RateOrder>(
    () => RateOrder(
      g<ReviewRepository>(),
      g<BranchRatingPort>(),
      g<ReviewNotifier>(),
    ),
  );
  g.registerFactory<GetCourierEarnings>(GetCourierEarnings.new);
  g.registerFactory<GetDeliveryEvidence>(
    () => GetDeliveryEvidence(g<OrderRepository>()),
  );

  // Pagos: iniciar, consultar y reintentar (sin estado propio).
  g.registerFactory<StartPayment>(() => StartPayment(g<PaymentRepository>()));
  g.registerFactory<CheckPaymentStatus>(
    () => CheckPaymentStatus(g<PaymentRepository>()),
  );
  g.registerFactory<RetryPayment>(() => RetryPayment(g<PaymentRepository>()));

  // Recompensas y cajas: solo se piden cuando hay repositorio (Supabase).
  g.registerFactory<LoadRewards>(() => LoadRewards(g<RewardsRepository>()));
  g.registerFactory<RedeemReward>(() => RedeemReward(g<RewardsRepository>()));
  g.registerFactory<LoadMerchantBoxes>(
    () => LoadMerchantBoxes(g<MerchantBoxesRepository>()),
  );
  g.registerFactory<AddDishToBox>(
    () => AddDishToBox(g<MerchantBoxesRepository>()),
  );
  g.registerFactory<ClaimBoxPrize>(
    () => ClaimBoxPrize(g<MerchantBoxesRepository>()),
  );
}
