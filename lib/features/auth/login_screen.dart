import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/actions.dart';
import '../../core/widgets/ui.dart';
import '../../domain/entities/user.dart';
import '../../shared/state/session_controller.dart';
import '../../shared/state/controller_scope.dart';
import '../../app/di/injection.dart';
import 'bloc/login_cubit.dart';

/// Navega tras iniciar sesión: retoma la ruta de origen o el panel del rol.
void navigateAfterAuth(BuildContext context, AppUser user, String? from) {
  final home = homeForRole(user.role);
  if (user.role == UserRole.buyer) {
    if (from != null && from.isNotEmpty) {
      context.go(from);
    } else if (context.canPop()) {
      final router = GoRouter.of(context);
      final depth = router.routerDelegate.currentConfiguration.matches.length;
      context.pop(true);
      // El login avisa al router (refreshListenable); si su refresco repone
      // /login encima (pasa desde las pestañas del inicio), se cierra otra vez.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final now = router.routerDelegate.currentConfiguration.matches;
        if (now.length >= depth &&
            now.last.matchedLocation == '/login' &&
            router.canPop()) {
          router.pop(true);
        }
      });
    } else {
      context.go('/');
    }
    return;
  }
  if (from != null && from.startsWith(home)) {
    context.go(from);
  } else {
    context.go(home);
  }
}

/// Pantalla de inicio de sesión con acceso rápido de demostración.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.from});

  /// Ruta de origen para volver después del login.
  final String? from;

  /// Crea el estado del inicio de sesión.
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

/// Estado del formulario de login y de los accesos rápidos.
class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late final LoginCubit _cubit;

  /// Crea el cubit con la sesión de la app.
  @override
  void initState() {
    super.initState();
    _cubit = getIt<LoginCubit>();
  }

  /// Libera los controladores y el cubit.
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _cubit.close();
    super.dispose();
  }

  /// Valida el formulario y lanza el inicio de sesión.
  void _submit() {
    if (!_form.currentState!.validate()) return;
    _runLogin();
  }

  /// Ejecuta el login y navega según el rol autenticado.
  Future<void> _runLogin() async {
    final user = await _cubit.submit(_email.text, _password.text);
    if (!mounted || user == null) return;
    showSnack(context, 'Hola, ${user.name.split(' ').first} 👋');
    navigateAfterAuth(context, user, widget.from);
  }

  /// Construye el formulario de login y las tarjetas de acceso demo.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final remote = context.watchController<SessionController>().auth.isRemote;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop(false) : context.go('/'),
        ),
      ),
      body: BlocBuilder<LoginCubit, LoginState>(
        bloc: _cubit,
        builder: (context, state) => MobileFrame(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(child: BeeLogo(size: 88)),
                  const SizedBox(height: 8),
                  Text('Inicia sesión', style: t.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    remote
                        ? 'Ingresa con tu cuenta de Biffy.'
                        : 'Autenticación simulada y local: no uses una contraseña real.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('login-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    onChanged: (_) => _cubit.clearError(),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Escribe un correo válido'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('login-password'),
                    controller: _password,
                    obscureText: state.obscure,
                    decoration: InputDecoration(
                      labelText: remote
                          ? 'Contraseña'
                          : 'Contraseña de demostración',
                      suffixIcon: IconButton(
                        tooltip: state.obscure
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        icon: Icon(
                          state.obscure
                              ? Icons.visibility
                              : Icons.visibility_off,
                        ),
                        onPressed: _cubit.toggleObscure,
                      ),
                    ),
                    onChanged: (_) => _cubit.clearError(),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Escribe la contraseña'
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 16),
                  PrimaryButton(
                    key: const Key('login-submit'),
                    label: state.isSubmitting ? 'Entrando…' : 'Iniciar sesión',
                    onPressed: state.isSubmitting ? null : _submit,
                  ),
                  const SizedBox(height: 8),
                  SecondaryButton(
                    label: 'Crear cuenta',
                    onPressed: () async {
                      final session = getIt<SessionController>();
                      final ok = await context.push<bool>('/registro');
                      if (ok == true &&
                          context.mounted &&
                          session.user != null) {
                        navigateAfterAuth(context, session.user!, widget.from);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
