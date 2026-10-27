import '../../core/constants/catalog_constants.dart';
import '../models/address.dart';
import '../models/user.dart';

class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Autenticación SIMULADA y local. No ofrece seguridad real: las contraseñas
/// de demostración viven solo en memoria durante la sesión de la app.
abstract class AuthRepository {
  List<AppUser> get demoAccounts;
  AppUser login(String email, String password);
  AppUser register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone,
  });
  AppUser? byId(String id);
  AppUser? byBusiness(String businessId);

  /// `true` cuando la autenticación vive en un backend real.
  bool get isRemote => false;

  /// Ruta asíncrona que usan las pantallas. En la demo resuelve al instante
  /// contra los datos en memoria; con Supabase habla con Auth.
  Future<AppUser> signIn(String email, String password);

  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone,
  });

  Future<void> signOut();

  /// Recupera la sesión persistida (solo backend real).
  Future<AppUser?> restoreSession();

  /// Saldo de Gotas en el backend. `null` en modo demo.
  Future<int?> gotasBalance(String userId);

  /// Direcciones guardadas del usuario (vacío en la demo).
  Future<List<Address>> addresses(String userId);
}

class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository(List<AppUser> seedUsers) {    for (final u in seedUsers) {
      _users[u.email.toLowerCase()] = u;
      _passwords[u.email.toLowerCase()] = kDemoPassword;
    }
  }

  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {};
  int _seq = 1;

  @override
  bool get isRemote => false;

  @override
  List<AppUser> get demoAccounts =>
      _users.values.where((u) => u.isDemo).toList();

  @override
  AppUser login(String email, String password) {
    final key = email.trim().toLowerCase();
    final user = _users[key];
    if (user == null) {
      throw AuthException('No encontramos una cuenta con ese correo.');
    }
    if (_passwords[key] != password) {
      throw AuthException('Contraseña incorrecta.');
    }
    return user;
  }

  @override
  AppUser register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) {
    final key = email.trim().toLowerCase();
    if (_users.containsKey(key)) {
      throw AuthException('Ya existe una cuenta con ese correo.');
    }
    final user = AppUser(
      id: 'u-new-${_seq++}',
      name: name.trim(),
      email: key,
      role: role,
      phone: phone,
    );
    _users[key] = user;
    _passwords[key] = password;
    return user;
  }

  @override
  AppUser? byId(String id) {
    for (final u in _users.values) {
      if (u.id == id) return u;
    }
    return null;
  }

  @override
  AppUser? byBusiness(String businessId) {
    for (final u in _users.values) {
      if (u.businessId == businessId) return u;
    }
    return null;
  }

  // ------------------------------------------------------- Ruta asíncrona

  @override
  Future<AppUser> signIn(String email, String password) async =>
      login(email, password);

  @override
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) async => register(
    name: name,
    email: email,
    password: password,
    role: role,
    phone: phone,
  );

  @override
  Future<void> signOut() async {}

  @override
  Future<AppUser?> restoreSession() async => null;

  @override
  Future<int?> gotasBalance(String userId) async => null;

  @override
  Future<List<Address>> addresses(String userId) async => const [];
}
