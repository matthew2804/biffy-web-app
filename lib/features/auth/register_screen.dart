import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import '../../domain/entities/user.dart';
import '../../shared/state/session_controller.dart';
import '../../shared/state/controller_scope.dart';
import 'bloc/register_cubit.dart';
import 'login_screen.dart';
import '../../app/di/injection.dart';

/// Registro con selección de rol. El restaurante abre un formulario ampliado.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.from});

  /// Ruta de origen para volver después del registro.
  final String? from;

  /// Crea el estado del registro de cuenta.
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

/// Estado del formulario de registro con selección de rol.
class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  late final RegisterCubit _cubit;

  /// Crea el cubit con la sesión de la app.
  @override
  void initState() {
    super.initState();
    _cubit = getIt<RegisterCubit>();
  }

  /// Libera los controladores y el cubit.
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _phone]) {
      c.dispose();
    }
    _cubit.close();
    super.dispose();
  }

  /// Valida el formulario o deriva al registro de negocio.
  void _submit() {
    if (_cubit.state.role == UserRole.restaurant) {
      context.push('/negocio/registro');
      return;
    }
    if (!_form.currentState!.validate()) return;
    _runRegister();
  }

  /// Crea la cuenta y continúa el flujo según el rol elegido.
  Future<void> _runRegister() async {
    final result = await _cubit.submit(
      name: _name.text,
      email: _email.text,
      password: _password.text,
      phone: _phone.text,
    );
    if (!mounted || result.user == null) return;
    showSnack(context, 'Cuenta creada ✅');
    final next = result.nextLocation;
    if (next != null) {
      context.go(next);
    } else if (context.canPop()) {
      // Si venimos del login, este retoma el flujo original.
      context.pop(true);
    } else {
      navigateAfterAuth(context, result.user!, widget.from);
    }
  }

  /// Construye el selector de rol y los campos de la cuenta.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final remote = context.watchController<SessionController>().auth.isRemote;
    return BlocBuilder<RegisterCubit, RegisterState>(
      bloc: _cubit,
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Crear cuenta')),
        body: MobileFrame(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('¿Cómo usarás Biffy?', style: t.titleLarge),
                  const SizedBox(height: 12),
                  for (final r in UserRole.values)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: BiffyCard(
                        key: Key('role-${r.name}'),
                        padding: const EdgeInsets.all(14),
                        border: state.role == r
                            ? Border.all(color: AppColors.primary, width: 2)
                            : null,
                        onTap: () => _cubit.roleChanged(r),
                        child: Row(
                          children: [
                            Text(r.emoji, style: const TextStyle(fontSize: 26)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(switch (r) {
                                    UserRole.buyer =>
                                      'Pide comida en tu campus o casa.',
                                    UserRole.courier =>
                                      'Acepta pedidos y gana entregando. Luego registras tu vehículo.',
                                    UserRole.restaurant =>
                                      'Publica tu menú y recibe pedidos (formulario ampliado).',
                                  }, style: t.bodySmall),
                                ],
                              ),
                            ),
                            Icon(
                              state.role == r
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                              color: state.role == r ? AppColors.primary : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (state.role != UserRole.restaurant) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('reg-name'),
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      onChanged: (_) => _cubit.clearError(),
                      validator: (v) => (v == null || v.trim().length < 2)
                          ? 'Escribe tu nombre'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('reg-email'),
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Correo',
                        helperText: remote
                            ? 'Si es universitario podrás verificarlo en Campus.'
                            : 'Si es universitario podrás verificarlo (simulado) en Campus.',
                      ),
                      onChanged: (_) => _cubit.clearError(),
                      validator: (v) =>
                          (v == null ||
                              !RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(v.trim()))
                          ? 'Escribe un correo válido'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('reg-password'),
                      controller: _password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: remote
                            ? 'Contraseña'
                            : 'Contraseña de demostración',
                        helperText: remote
                            ? 'Mínimo 6 caracteres.'
                            : 'Solo vive en memoria durante la demo. No uses una real.',
                      ),
                      onChanged: (_) => _cubit.clearError(),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Mínimo 6 caracteres'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono (opcional)',
                      ),
                    ),
                  ],
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      state.error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  PrimaryButton(
                    key: const Key('reg-submit'),
                    label: state.role == UserRole.restaurant
                        ? 'Continuar con el registro del negocio'
                        : state.isSubmitting
                        ? 'Creando cuenta…'
                        : 'Crear cuenta',
                    onPressed: state.isSubmitting ? null : _submit,
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
