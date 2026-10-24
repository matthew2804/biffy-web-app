import '../../core/constants/catalog_constants.dart';
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
}

class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository(List<AppUser> seedUsers) {
    for (final u in seedUsers) {
      _users[u.email.toLowerCase()] = u;
      _passwords[u.email.toLowerCase()] = kDemoPassword;
    }
  }

  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {};
  int _seq = 1;

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
}
