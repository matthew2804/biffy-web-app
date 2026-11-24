import 'package:get_it/get_it.dart';

import '../../../core/utils/clock.dart';

/// Módulo núcleo: servicios sin dependencias de negocio.
void registerCoreModule(GetIt g) {
  g.registerLazySingleton<Clock>(Clock.new);
}
