import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/catalog_constants.dart';
import '../../core/widgets/actions.dart';
import '../../core/widgets/ui.dart';
import '../../data/mock/seed_users.dart';
import '../../data/models/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../shared/state/session_controller.dart';

/// Navega tras iniciar sesión: retoma la ruta de origen o el panel del rol.
void navigateAfterAuth(BuildContext context, AppUser user, String? from) {
  final home = homeForRole(user.role);
  if (user.role == UserRole.buyer) {
    if (from != null && from.isNotEmpty) {
      context.go(from);
    } else if (context.canPop()) {
      context.pop(true);
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

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.from});
  final String? from;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    _runLogin();
  }

  Future<void> _runLogin() async {
    try {
      final u = await context.read<SessionController>().loginAsync(
        _email.text,
        _password.text,
      );
      if (!mounted) return;
      showSnack(context, 'Hola, ${u.name.split(' ').first} 👋');
      navigateAfterAuth(context, u, widget.from);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _quick(String email) async {
    final session = context.read<SessionController>();
    try {
      final AppUser u;
      if (session.auth.isRemote) {
        u = await session.loginAsync(email, kDemoPassword);
      } else {
        u = session.auth.login(email, kDemoPassword);
        session.loginAs(u);
      }
      if (!mounted) return;
      showSnack(context, 'Sesión demo: ${u.name}');
      navigateAfterAuth(context, u, widget.from);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop(false) : context.go('/'),
        ),
      ),
      body: MobileFrame(
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
                  'Autenticación simulada y local: no uses una contraseña real.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('login-email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo'),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Escribe un correo válido'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('login-password'),
                  controller: _password,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Contraseña de demostración',
                    suffixIcon: IconButton(
                      tooltip: _obscure
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      icon: Icon(
                        _obscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Escribe la contraseña' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 16),
                PrimaryButton(
                  key: const Key('login-submit'),
                  label: 'Iniciar sesión',
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                SecondaryButton(
                  label: 'Crear cuenta',
                  onPressed: () async {
                    final session = context.read<SessionController>();
                    final ok = await context.push<bool>('/registro');
                    if (ok == true && context.mounted && session.user != null) {
                      navigateAfterAuth(context, session.user!, widget.from);
                    }
                  },
                ),
                const SizedBox(height: 24),
                Text('Acceso rápido de demostración', style: t.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Cuentas ficticias · contraseña $kDemoPassword',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 12),
                _QuickTile(
                  key: const Key('quick-buyer'),
                  emoji: '🛍️',
                  title: 'Comprador · Diego',
                  subtitle:
                      'Estudiante Icesi verificado (simulado), con historial',
                  onTap: () => _quick(kDemoBuyerEmail),
                ),
                _QuickTile(
                  key: const Key('quick-new-buyer'),
                  emoji: '🙋',
                  title: 'Comprador nuevo · Camila',
                  subtitle: 'Sin preferencias ni historial',
                  onTap: () => _quick(kDemoNewBuyerEmail),
                ),
                _QuickTile(
                  key: const Key('quick-courier'),
                  emoji: '🛵',
                  title: 'Repartidor · Andrés',
                  subtitle: 'Moto · campus Icesi',
                  onTap: () => _quick(kDemoCourierEmail),
                ),
                _QuickTile(
                  key: const Key('quick-restaurant'),
                  emoji: '🥪',
                  title: 'Restaurante · Qbano Icesi',
                  subtitle: 'Panel del negocio de demostración',
                  onTap: () => _quick(kDemoRestaurantEmail),
                ),
                TextButton(
                  onPressed: () => showDemoAccountsSheet(context),
                  child: const Text('Ver todas las cuentas demo'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    super.key,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BiffyCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
