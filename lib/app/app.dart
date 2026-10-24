import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../shared/state/app_services.dart';
import '../shared/state/session_controller.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class BiffyApp extends StatefulWidget {
  const BiffyApp({
    super.key,
    required this.services,
    this.initialLocation = '/splash',
  });

  final AppServices services;
  final String initialLocation;

  @override
  State<BiffyApp> createState() => _BiffyAppState();
}

class _BiffyAppState extends State<BiffyApp> {
  late final GoRouter _router = buildRouter(
    widget.services.session,
    initialLocation: widget.initialLocation,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

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
