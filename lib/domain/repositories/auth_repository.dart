import '../entities/address.dart';
import '../entities/user.dart';

/// Error de autenticación con mensaje para el usuario.
class AuthException implements Exception {
  /// Crea el error con un mensaje ya traducido a español.
  AuthException(this.message);

  /// Mensaje que ve el usuario.
  final String message;

  /// Muestra solo el mensaje, sin el tipo de excepción.
  @override
  String toString() => message;
}

/// Contrato de autenticación y datos de la cuenta.
///
/// La app depende de esta interfaz; las implementaciones (memoria y Supabase)
/// viven en `lib/data/repositories/`.
abstract class AuthRepository {
  /// Cuentas de demostración para el acceso rápido.
  List<AppUser> get demoAccounts;

  /// Inicia sesión de forma síncrona (solo modo demo).
  AppUser login(String email, String password);

  /// Registra una cuenta nueva y la devuelve (solo modo demo).
  AppUser register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone,
  });

  /// Usuario por id, si existe en la caché local.
  AppUser? byId(String id);

  /// Cuenta dueña del negocio indicado.
  AppUser? byBusiness(String businessId);

  /// `true` cuando la autenticación vive en un backend real.
  bool get isRemote;

  /// Inicia sesión contra el backend.
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
  Future<String?> registerBusiness(Map<String, dynamic> payload);

  /// Guarda nombre y teléfono del perfil en el backend.
  Future<void> saveProfile(String userId, {String? name, String? phone});

  /// Guarda el perfil de repartidor del usuario en el backend.
  Future<void> saveCourierProfile(String userId, CourierProfile profile);

  /// Conecta o desconecta al repartidor en el servidor (cuenta para
  /// `couriers_nearby` de las sedes). Devuelve el código del RPC (`ok`,
  /// `no_profile`, `not_verified`, `network`); en la demo siempre `ok`.
  Future<String> setCourierOnline(
    String userId, {
    required bool online,
    CourierZone? zone,
  });

  /// Verifica el correo universitario contra el backend y devuelve su código.
  Future<String?> verifyUniversity(String universityId, String email);

  /// Envía un código al correo institucional.
  Future<({String result, String? demoCode})> sendUniversityCode({
    required String userId,
    required String universityId,
    required String email,
    bool renewal = false,
  });

  /// Confirma el código recibido en el correo institucional.
  Future<String?> confirmUniversityCode({
    required String userId,
    required String email,
    required String code,
  });
}
