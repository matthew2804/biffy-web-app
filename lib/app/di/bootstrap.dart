import '../../data/mock/seed_state.dart';
import '../../domain/repositories/order_repository.dart';
import '../../shared/state/catalog_controller.dart';
import '../../shared/state/notification_center.dart';
import '../../shared/state/session_controller.dart';
import '../../core/utils/clock.dart';
import 'injection.dart';

/// Deja la app lista para usarse una vez registradas las dependencias.
///
/// Con servidor intenta restaurar la sesión guardada (si falla la red se abre
/// sin sesión). En demo carga los datos de ejemplo ([seedData]) y el aviso de
/// bienvenida.
Future<void> bootstrapApp({bool seedData = true}) async {
  if (getIt<OrderRepository>().isRemote) {
    try {
      await getIt<SessionController>().restoreAsync();
    } on Object {
      // Sin red se abre sin sesión; la persona puede volver a entrar.
    }
    return;
  }
  bootstrapDemo(seedData: seedData);
}

/// Prepara el modo demo: pedidos y cuentas de ejemplo ([seedData]) y el aviso
/// de bienvenida. No toca la red.
void bootstrapDemo({bool seedData = true}) {
  if (seedData) {
    applyDemoSeed(
      getIt<SessionController>(),
      getIt<OrderRepository>(),
      getIt<CatalogController>(),
      getIt<Clock>(),
    );
  }
  getIt<NotificationCenter>().push(
    title: 'Bienvenido a Biffy 🐝',
    body: 'Explora sin registrarte. Todo es una demostración sin cobros reales.',
    audience: 'all',
  );
}
