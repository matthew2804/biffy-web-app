import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/orders/bloc/orders_bloc.dart';
import '../features/buyer/cart/bloc/cart_cubit.dart';
import '../shared/state/catalog_controller.dart';
import '../shared/state/controller_scope.dart';
import '../shared/state/notification_center.dart';
import '../shared/state/session_controller.dart';
import 'di/injection.dart';
import 'router.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

/// Raíz de la app: estado (desde GetIt), tema y router.
///
/// Requiere que `configureDependencies()` ya se haya ejecutado.
class BiffyApp extends StatefulWidget {
  const BiffyApp({super.key, this.initialLocation = '/splash'});

  final String initialLocation;

  /// Crea el estado raíz de la app.
  @override
  State<BiffyApp> createState() => _BiffyAppState();
}

/// Estado que crea el router una sola vez y escucha el modo oscuro.
class _BiffyAppState extends State<BiffyApp> {
  late final GoRouter _router = buildRouter(
    getIt<SessionController>(),
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
    _orderErrors = getIt<OrdersBloc>().stream.listen((state) {
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

  /// Libera el router al cerrar la app.
  @override
  void dispose() {
    _orderErrors?.cancel();
    _router.dispose();
    super.dispose();
  }

  /// Envuelve la app con el estado compartido, el tema y el router.
  @override
  Widget build(BuildContext context) {
    return ControllerScope(
      controllers: {
        SessionController: getIt<SessionController>(),
        CatalogController: getIt<CatalogController>(),
        NotificationCenter: getIt<NotificationCenter>(),
      },
      child: MultiBlocProvider(
        providers: [
          BlocProvider<OrdersBloc>.value(value: getIt<OrdersBloc>()),
          BlocProvider<CartCubit>.value(value: getIt<CartCubit>()),
        ],
        child: _DarkModeBuilder(
          session: getIt<SessionController>(),
          builder: (dark) => MaterialApp.router(
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
      ),
    );
  }
}

/// Reconstruye el tema solo cuando cambia el modo oscuro de la sesión.
class _DarkModeBuilder extends StatefulWidget {
  const _DarkModeBuilder({required this.session, required this.builder});

  final SessionController session;
  final Widget Function(bool dark) builder;

  /// Crea el estado que escucha el ajuste.
  @override
  State<_DarkModeBuilder> createState() => _DarkModeBuilderState();
}

/// Estado: recuerda el último valor del modo oscuro.
class _DarkModeBuilderState extends State<_DarkModeBuilder> {
  late bool _dark = widget.session.settings.darkMode;

  /// Empieza a escuchar la sesión.
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
  }

  /// Redibuja solo si el modo oscuro cambió.
  void _onSession() {
    final dark = widget.session.settings.darkMode;
    if (dark != _dark) setState(() => _dark = dark);
  }

  /// Deja de escuchar la sesión.
  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  /// Construye la app con el modo actual.
  @override
  Widget build(BuildContext context) => widget.builder(_dark);
}
