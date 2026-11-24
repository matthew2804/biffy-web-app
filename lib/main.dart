import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di/bootstrap.dart';
import 'app/di/injection.dart';

/// Punto de entrada: registra las dependencias en GetIt (que decide entre
/// Supabase y modo demo), deja la app lista y la abre.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();
  await bootstrapApp();
  runApp(const BiffyApp());
}
