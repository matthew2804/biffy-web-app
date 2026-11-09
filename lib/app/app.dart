import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../shared/state/app_services.dart';
import '../shared/state/session_controller.dart';
import '../features/orders/bloc/orders_bloc.dart';
import 'router.dart';
import 'theme/app_colors.dart';
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
  final _messengerKey = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<OrdersState>? _orderErrors;
  int _lastOutcome = 0;

  /// Acciones cuya pantalla no muestra el error por su cuenta.
  static const _globalErrorActions = {
    OrderAction.accept,
    OrderAction.reject,
    OrderAction.ready,
    OrderAction.declineOffer,
  };

  @override
  void initState() {
    super.initState();
    // Errores del servidor ya traducidos (aceptar, rechazar, marcar listo…):
    // los botones sin resultado propio los muestran por aquí.
    _orderErrors = widget.services.orders.stream.listen((state) {
      final o = state.outcome;
      if (o == null || o.id <= _lastOutcome) return;
      _lastOutcome = o.id;
      if (!o.ok && _globalErrorActions.contains(o.action)) {
        _showOrderError(o.result.message);
      }
    });
  }

  void _showOrderError(String message) {
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  void dispose() {
    _orderErrors?.cancel();
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
          scaffoldMessengerKey: _messengerKey,
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
