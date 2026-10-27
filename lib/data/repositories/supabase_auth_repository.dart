import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/user.dart';
import 'auth_repository.dart';

/// Autenticación real contra Supabase Auth.
///
/// El perfil (rol, nombre, teléfono, negocio y Gotas) vive en la tabla
/// `profiles` y lo crea el trigger `handle_new_user` en el registro.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({sb.SupabaseClient? client})
    : _client = client ?? sb.Supabase.instance.client;

  final sb.SupabaseClient _client;
  final Map<String, AppUser> _cache = {};

  @override
  bool get isRemote => true;

  @override
  List<AppUser> get demoAccounts => const [];

  // ------------------------------------------------------------- Escrituras

  @override
  Future<AppUser> signIn(String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) {
        throw AuthException('No pudimos iniciar sesión.');
      }
      return _loadProfile(user.id, fallbackEmail: user.email ?? email);
    } on sb.AuthException catch (e) {
      throw AuthException(_message(e.message));
    } on sb.PostgrestException catch (e) {
      throw AuthException('No pudimos leer tu perfil: ${e.message}');
    }
  }

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) async {
    try {
      final res = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': name.trim(),
          'role': _roleValue(role),
          if (phone.isNotEmpty) 'phone': phone,
        },
      );

      final user = res.user;
      if (user == null) {
        throw AuthException('No pudimos crear la cuenta.');
      }
      if (res.session == null) {
        throw AuthException(
          'Revisa tu correo para confirmar la cuenta antes de entrar.',
        );
      }
      return _loadProfile(user.id, fallbackEmail: user.email ?? email);
    } on sb.AuthException catch (e) {
      throw AuthException(_message(e.message));
    } on sb.PostgrestException catch (e) {
      throw AuthException('No pudimos leer tu perfil: ${e.message}');
    }
  }

  @override
  Future<void> signOut() async {
    _cache.clear();
    await _client.auth.signOut();
  }

  @override
  Future<AppUser?> restoreSession() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      return await _loadProfile(user.id, fallbackEmail: user.email ?? '');
    } on Object {
      return null;
    }
  }

  @override
  Future<int?> gotasBalance(String userId) async {
    try {
      final row = await _client
          .from('profiles')
          .select('gotas')
          .eq('id', userId)
          .maybeSingle();
      return (row?['gotas'] as num?)?.toInt();
    } on Object {
      return null;
    }
  }

  // --------------------------------------------------------- Lectura local

  @override
  AppUser? byId(String id) => _cache[id];

  @override
  AppUser? byBusiness(String businessId) {
    for (final u in _cache.values) {
      if (u.businessId == businessId) return u;
    }
    return null;
  }

  /// En modo remoto la sesión se abre con [signIn]; el acceso síncrono solo
  /// existe para los datos de demostración.
  @override
  AppUser login(String email, String password) =>
      throw AuthException('Usa loginAsync cuando Supabase está configurado.');

  @override
  AppUser register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) => throw AuthException(
    'Usa registerAsync cuando Supabase está configurado.',
  );

  // -------------------------------------------------------------- Interno

  Future<AppUser> _loadProfile(
    String id, {
    required String fallbackEmail,
  }) async {
    final row = await _client
        .from('profiles')
        .select('id, email, full_name, role, phone, business_id, is_demo')
        .eq('id', id)
        .maybeSingle();

    final fallbackName = fallbackEmail.split('@').first;
    final fullName = (row?['full_name'] as String?)?.trim() ?? '';
    final user = AppUser(
      id: row?['id'] as String? ?? id,
      name: fullName.isNotEmpty ? fullName : fallbackName,
      email: (row?['email'] as String?) ?? fallbackEmail,
      role: _roleFrom(row?['role'] as String?),
      phone: (row?['phone'] as String?) ?? '',
      businessId: row?['business_id'] as String?,
      isDemo: (row?['is_demo'] as bool?) ?? false,
    );
    _cache[user.id] = user;
    return user;
  }

  static String _roleValue(UserRole role) => switch (role) {
    UserRole.buyer => 'buyer',
    UserRole.courier => 'courier',
    UserRole.restaurant => 'restaurant',
  };

  static UserRole _roleFrom(String? value) => switch (value) {
    'courier' => UserRole.courier,
    'restaurant' => UserRole.restaurant,
    _ => UserRole.buyer,
  };

  static String _message(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('already registered') || m.contains('already exists')) {
      return 'Ya existe una cuenta con ese correo.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirma tu correo antes de entrar.';
    }
    if (m.contains('password') && m.contains('least')) {
      return 'La contraseña es demasiado corta.';
    }
    if (m.contains('rate limit')) {
      return 'Demasiados intentos. Espera un momento.';
    }
    return raw;
  }
}
