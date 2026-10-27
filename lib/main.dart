import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'shared/state/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin credenciales de compilación la app arranca en modo demo local y no
  // hace ninguna petición de red.
  if (!AppConfig.hasSupabase) {
    runApp(BiffyApp(services: AppServices.demo()));
    return;
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
  );

  final services = await AppServices.supabase();
  try {
    await services.session.restoreAsync();
  } on Object {
    // Si falla la red se abre sin sesión; el usuario puede volver a entrar.
  }

  runApp(BiffyApp(services: services));
}
