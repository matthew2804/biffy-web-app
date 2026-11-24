import '../../core/constants/catalog_constants.dart';
import '../../domain/repositories/auth_repository.dart';
import '../models/address.dart';
import '../models/user.dart';

export '../../domain/repositories/auth_repository.dart';

/// Autenticación de demostración con usuarios y contraseñas en memoria.
class InMemoryAuthRepository implements AuthRepository {
  /// Registra las cuentas semilla con la contraseña de demo.
  InMemoryAuthRepository(List<AppUser> seedUsers) {
    for (final u in seedUsers) {
      _users[u.email.toLowerCase()] = u;
      _passwords[u.email.toLowerCase()] = kDemoPassword;
    }
  }

  final Map<String, AppUser> _users = {};
  final Map<String, String> _passwords = {};
  final Map<String, String> _uniCodes = {};
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

  /// La demo guarda el perfil solo en memoria.
  @override
  Future<void> saveProfile(
    String userId, {
    String? name,
    String? phone,
  }) async {}

  /// La demo guarda el perfil de repartidor solo en memoria.
  @override
  Future<void> saveCourierProfile(
    String userId,
    CourierProfile profile,
  ) async {}

  /// En la demo la disponibilidad del repartidor vive solo en memoria.
  @override
  Future<String> setCourierOnline(
    String userId, {
    required bool online,
    CourierZone? zone,
  }) async => 'ok';

  /// La verificación universitaria de la demo es local.
  @override
  Future<String?> verifyUniversity(String universityId, String email) async =>
      null;

  /// En la demo el código siempre es 123456 y se muestra en la app.
  @override
  Future<({String result, String? demoCode})> sendUniversityCode({
    required String userId,
    required String universityId,
    required String email,
    bool renewal = false,
  }) async {
    _uniCodes[userId] = '123456';
    return (result: 'ok', demoCode: '123456');
  }

  /// Valida el código de demostración.
  @override
  Future<String?> confirmUniversityCode({
    required String userId,
    required String email,
    required String code,
  }) async {
    if (_uniCodes[userId] != code.trim()) return 'invalid_token';
    _uniCodes.remove(userId);
    return 'ok';
  }
}
