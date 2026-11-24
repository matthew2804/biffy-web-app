import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Hace que las pantallas se redibujen cuando cambia un controlador
/// (`ChangeNotifier`) sin usar Provider. Los controladores salen de GetIt; este
/// widget solo escucha sus cambios y avisa a quien los observa con
/// [ControllerContext.watchController].
///
/// Cada tipo se observa por separado: una pantalla que mira `SessionController`
/// no se redibuja cuando cambia el carrito.
class ControllerScope extends StatefulWidget {
  /// Recibe los controladores a escuchar, indexados por su tipo.
  const ControllerScope({
    super.key,
    required this.controllers,
    required this.child,
  });

  final Map<Type, Listenable> controllers;
  final Widget child;

  /// Crea el estado que escucha a los controladores.
  @override
  State<ControllerScope> createState() => _ControllerScopeState();
}

/// Estado: lleva un contador de cambios por controlador.
class _ControllerScopeState extends State<ControllerScope> {
  final Map<Type, int> _versions = {};
  final Map<Type, VoidCallback> _listeners = {};

  /// Empieza a escuchar cada controlador.
  @override
  void initState() {
    super.initState();
    widget.controllers.forEach((type, controller) {
      _versions[type] = 0;
      void listener() => _bump(type);
      _listeners[type] = listener;
      controller.addListener(listener);
    });
  }

  /// Sube el contador del tipo y redibuja; si llega en pleno dibujado, espera
  /// al final del cuadro.
  void _bump(Type type) {
    if (!mounted) return;
    void apply() {
      if (mounted) setState(() => _versions[type] = _versions[type]! + 1);
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  /// Deja de escuchar al cerrar la app.
  @override
  void dispose() {
    widget.controllers.forEach((type, controller) {
      final listener = _listeners[type];
      if (listener != null) controller.removeListener(listener);
    });
    super.dispose();
  }

  /// Publica los contadores actuales para los widgets que observan.
  @override
  Widget build(BuildContext context) => _ControllerModel(
    versions: Map.of(_versions),
    controllers: widget.controllers,
    child: widget.child,
  );
}

/// Modelo heredado: avisa solo a quien observa el tipo que cambió.
class _ControllerModel extends InheritedModel<Type> {
  const _ControllerModel({
    required this.versions,
    required this.controllers,
    required super.child,
  });

  final Map<Type, int> versions;
  final Map<Type, Listenable> controllers;

  /// Hay cambios si algún contador subió.
  @override
  bool updateShouldNotify(_ControllerModel old) =>
      !mapEquals(versions, old.versions);

  /// Redibuja a quien observa un tipo cuyo contador subió.
  @override
  bool updateShouldNotifyDependent(
    _ControllerModel old,
    Set<Type> dependencies,
  ) => dependencies.any((t) => versions[t] != old.versions[t]);
}

/// Acceso a los controladores observables desde un [BuildContext].
extension ControllerContext on BuildContext {
  /// Devuelve el controlador [T] y redibuja este widget cuando cambie.
  T watchController<T extends Listenable>() {
    final model = InheritedModel.inheritFrom<_ControllerModel>(
      this,
      aspect: T,
    );
    assert(model != null, 'Falta un ControllerScope sobre este widget.');
    final controller = model!.controllers[T];
    assert(controller != null, '$T no está registrado en ControllerScope.');
    return controller! as T;
  }
}
