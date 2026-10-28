import '../../core/constants/catalog_constants.dart';
import '../models/address.dart';
import '../models/user.dart';

/// Error de autenticación con mensaje para el usuario.
class AuthException implements Exception {
  AuthException(this.message);
  final String message;
  /// Muestra solo el mensaje, sin el tipo de excepción.
  @override
  String toString() => message;
}

/// Autenticación SIMULADA y local. No ofrece seguridad real: las contraseñas
/// de demostración viven solo en memoria durante la sesión de la app.
abstract class AuthRepository {
  /// Cuentas de demostración para el acceso rápido.
  List<AppUser> get demoAccounts;
  /// Inicia sesión de forma síncrona.
  AppUser login(String email, String password);
  /// Registra una cuenta nueva y la devuelve.
  AppUser register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone,
  });
  /// Usuario por id, si existe en la sesión.
  AppUser? byId(String id);
  /// Cuenta dueña del negocio indicado.
  AppUser? byBusiness(String businessId);

  /// `true` cuando la autenticación vive en un backend real.
  bool get isRemote => false;

  /// Ruta asíncrona que usan las pantallas. En la demo resuelve al instante
  /// contra los datos en memoria; con Supabase habla con Auth.
  Future<AppUser> signIn(String email, String password);

  /// Registra la cuenta y devuelve el usuario.
  Future<AppUser> signUp({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone,
  });

  /// Cierra la sesión y limpia el estado guardado.
  Future<void> signOut();

  /// Recupera la sesión persistida (solo backend real).
  Future<AppUser?> restoreSession();

  /// Saldo de Gotas en el backend. `null` en modo demo.
  Future<int?> gotasBalance(String userId);

  /// Direcciones guardadas del usuario (vacío en la demo).
  Future<List<Address>> addresses(String userId);

  /// Perfil de repartidor (solo rol `courier`). `null` en la demo.
  Future<CourierProfile?> courierProfile(String userId);

  /// Crea el negocio y sus sedes del usuario autenticado.
  /// Devuelve el id del negocio o `null` si falló.
  Future<String?> registerBusiness(Map<String, dynamic> payload);
}

/// Autenticación de demostración con usuarios y contraseñas en memoria.
class InMemoryAuthRepository implements AuthRepository {
  /// Registra las cuentas semilla con la contraseña de demo.
  InMemoryAuthRepository(List<AppUser> seedUsers) {    for (final u in seedUsers) {
      _users[u.email.toLowerCase()] = u;
      _passwords[u.email.toLowerCase()] = kDemoPassword;
    }
  }

  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {};
  int _seq = 1;

  /// La demo nunca habla con un backend.
  @override
  bool get isRemote => false;

  /// Cuentas marcadas como de demostración.
  @override
  List<AppUser> get demoAccounts =>
      _users.values.where((u) => u.isDemo).toList();

  /// Inicia sesión validando correo y contraseña locales.
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

  /// Crea una cuenta nueva en memoria.
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

  /// Busca un usuario por id.
  @override
  AppUser? byId(String id) {
    for (final u in _users.values) {
      if (u.id == id) return u;
    }
    return null;
  }

  /// Busca la cuenta dueña de un negocio.
  @override
  AppUser? byBusiness(String businessId) {
    for (final u in _users.values) {
      if (u.businessId == businessId) return u;
    }
    return null;
  }

  // ------------------------------------------------------- Ruta asíncrona

  /// Inicia sesión en la demo (resuelve al instante).
  @override
  Future<AppUser> signIn(String email, String password) async =>
      login(email, password);

  /// Registra la cuenta en la demo.
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

  /// La demo no guarda sesión persistente.
  @override
  Future<void> signOut() async {}

  /// No hay sesión persistida en la demo.
  @override
  Future<AppUser?> restoreSession() async => null;

  /// Saldo de Gotas: no aplica en la demo.
  @override
  Future<int?> gotasBalance(String userId) async => null;

  /// Direcciones guardadas: vacío en la demo.
  @override
  Future<List<Address>> addresses(String userId) async => const [];

  /// Perfil de repartidor: no aplica en la demo.
  @override
  Future<CourierProfile?> courierProfile(String userId) async => null;

  @override
  Future<String?> registerBusiness(Map<String, dynamic> payload) async =>
      throw AuthException('El alta de negocios necesita Supabase.');
}
