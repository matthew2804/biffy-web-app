import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../shared/state/app_services.dart';
import '../shared/state/session_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Raíz de la app: providers de estado, tema y router.
class BiffyApp extends StatefulWidget {
  const BiffyApp({
    super.key,
    required this.services,
    this.initialLocation = '/splash',
  });

  final AppServices services;
  final String initialLocation;

  /// Crea el estado raíz de la app.
  @override
  State<BiffyApp> createState() => _BiffyAppState();
}

/// Estado que crea el router una sola vez y escucha el modo oscuro.
class _BiffyAppState extends State<BiffyApp> {
  late final GoRouter _router = buildRouter(
    widget.services.session,
    initialLocation: widget.initialLocation,
  );

  /// Libera el router al cerrar la app.
  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  /// Envuelve la app con los servicios, el tema y el router configurado.
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: widget.services.providers,
      child: Selector<SessionController, bool>(
        selector: (_, s) => s.settings.darkMode,
        builder: (_, dark, _) => MaterialApp.router(
          title: 'Biffy',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          locale: const Locale('es', 'CO'),
          supportedLocales: const [Locale('es', 'CO'), Locale('es')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: _router,
        ),
      ),
    );
  }
}
