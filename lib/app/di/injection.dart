import 'package:get_it/get_it.dart';

import 'modules/core_module.dart';
import 'modules/data_module.dart';
import 'modules/domain_module.dart';
import 'modules/presentation_module.dart';

export 'package:get_it/get_it.dart' show GetIt;

/// Contenedor de dependencias de la app (GetIt). Es la única raíz de composición.
final GetIt getIt = GetIt.instance;

/// Registra todas las dependencias, por módulos, y espera a las asíncronas.
///
/// Solo registra: no crea nada hasta que alguien lo pide (`LazySingleton` y
/// `Factory`). Así las pruebas pueden cambiar un registro antes del primer uso.
/// Con `AppConfig.hasSupabase` el módulo de datos usa Supabase; sin él, memoria.
Future<void> configureDependencies() async {
  registerCoreModule(getIt);
  registerDataModule(getIt);
  registerDomainModule(getIt);
  registerPresentationModule(getIt);
  await getIt.allReady();
}

/// Descarta todos los registros (pruebas y reinicios).
Future<void> resetDependencies() => getIt.reset();
