import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/utils/clock.dart';
import '../../../data/mock/seed_users.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/in_memory_order_repository.dart';
import '../../../data/repositories/in_memory_payment_repository.dart';
import '../../../data/repositories/review_repository_impl.dart';
import '../../../data/repositories/supabase_auth_repository.dart';
import '../../../data/repositories/supabase_catalog_repository.dart';
import '../../../data/repositories/supabase_notification_repository.dart';
import '../../../data/repositories/supabase_order_repository.dart';
import '../../../data/repositories/supabase_payment_repository.dart';
import '../../../data/repositories/supabase_profile_repository.dart';
import '../../../data/repositories/supabase_rewards_repository.dart';
import '../../../domain/repositories/merchant_boxes_repository.dart';
import '../../../domain/repositories/notification_repository.dart';
import '../../../domain/repositories/order_repository.dart';
import '../../../domain/repositories/payment_repository.dart';
import '../../../domain/repositories/profile_repository.dart';
import '../../../domain/repositories/review_repository.dart';
import '../../../domain/repositories/rewards_repository.dart';

/// Módulo de datos: repositorios. Aquí está la única decisión de entorno de la
/// app: con credenciales de Supabase se usan las implementaciones reales; sin
/// ellas, las de memoria (demo).
void registerDataModule(GetIt g) {
  if (AppConfig.hasSupabase) {
    _registerSupabase(g);
  } else {
    _registerInMemory(g);
  }
}

/// Repositorios en memoria: modo demo y pruebas, sin red.
void _registerInMemory(GetIt g) {
  g.registerLazySingleton<CatalogRepository>(InMemoryCatalogRepository.new);
  g.registerLazySingleton<AuthRepository>(
    () => InMemoryAuthRepository(
      seedUsers(g<CatalogRepository>().businesses),
    ),
  );
  g.registerLazySingleton<OrderRepository>(
    () => InMemoryOrderRepository(g<Clock>()),
  );
  g.registerLazySingleton<PaymentRepository>(
    () => InMemoryPaymentRepository(),
  );
  g.registerLazySingleton<ReviewRepository>(
    () => InMemoryReviewRepository(g<OrderRepository>()),
  );
}

/// Repositorios de Supabase. El catálogo y los pedidos se precargan, por eso
/// son asíncronos y `configureDependencies` espera a que estén listos.
void _registerSupabase(GetIt g) {
  // El cliente se inicializa primero; todo lo demás espera a que esté listo.
  g.registerSingletonAsync<Supabase>(
    () => Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    ),
  );
  g.registerSingletonAsync<CatalogRepository>(
    SupabaseCatalogRepository.load,
    dependsOn: [Supabase],
  );
  g.registerSingletonAsync<OrderRepository>(
    SupabaseOrderRepository.load,
    dependsOn: [Supabase],
    dispose: (repo) {
      if (repo is SupabaseOrderRepository) repo.dispose();
    },
  );
  g.registerLazySingleton<AuthRepository>(SupabaseAuthRepository.new);
  g.registerLazySingleton<PaymentRepository>(
    () => SupabasePaymentRepository(),
    dispose: (repo) => repo.dispose(),
  );
  g.registerLazySingleton<ProfileRepository>(SupabaseProfileRepository.new);
  g.registerLazySingleton<NotificationRepository>(
    SupabaseNotificationRepository.new,
  );
  g.registerLazySingleton<ReviewRepository>(SupabaseReviewRepository.new);
  // Un solo repositorio sirve a las dos interfaces (comprador y restaurante).
  g.registerLazySingleton<RewardsRepository>(SupabaseRewardsRepository.new);
  g.registerLazySingleton<MerchantBoxesRepository>(
    () => g<RewardsRepository>() as MerchantBoxesRepository,
  );
}
