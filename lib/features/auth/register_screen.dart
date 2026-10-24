import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../core/widgets/ui.dart';
import '../../data/models/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../shared/state/session_controller.dart';
import 'login_screen.dart';

/// Registro con selección de rol. El restaurante abre un formulario ampliado.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.from});
  final String? from;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  UserRole _role = UserRole.buyer;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (_role == UserRole.restaurant) {
      context.push('/negocio/registro');
      return;
    }
    if (!_form.currentState!.validate()) return;
    try {
      final u = context.read<SessionController>().register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        role: _role,
        phone: _phone.text,
      );
      showSnack(context, 'Cuenta de demostración creada ✅');
      if (_role == UserRole.courier) {
        context.go('/repartidor/registro');
      } else {
        // Si venimos del login, este retoma el flujo original.
        if (context.canPop()) {
          context.pop(true);
        } else {
          navigateAfterAuth(context, u, widget.from);
        }
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
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
                      border: _role == r
                          ? Border.all(color: AppColors.primary, width: 2)
                          : null,
                      onTap: () => setState(() => _role = r),
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
                            _role == r
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: _role == r ? AppColors.primary : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_role != UserRole.restaurant) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('reg-name'),
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Escribe tu nombre'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('reg-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Correo',
                      helperText:
                          'Si es universitario podrás verificarlo (simulado) en Campus.',
                    ),
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
                    decoration: const InputDecoration(
                      labelText: 'Contraseña de demostración',
                      helperText:
                          'Solo vive en memoria durante la demo. No uses una real.',
                    ),
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
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                ],
                const SizedBox(height: 20),
                PrimaryButton(
                  key: const Key('reg-submit'),
                  label: _role == UserRole.restaurant
                      ? 'Continuar con el registro del negocio'
                      : 'Crear cuenta',
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
