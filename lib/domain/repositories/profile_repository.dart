import '../entities/address.dart';
import '../entities/user.dart';

/// Contrato de los datos personales del comprador: verificación, preferencias,
/// ajustes, favoritos, direcciones y cupones. El dominio no sabe que detrás
/// está Supabase; en modo demo no hay repositorio (todo vive en memoria).
abstract interface class ProfileRepository {
  /// Lee la verificación universitaria y su fecha de vencimiento.
  Future<
    ({
      bool verified,
      String? universityId,
      String? universityEmail,
      String? status,
      DateTime? expiresAt,
    })
  >
  verification(String userId);

  /// Lee preferencias y sus banderas de encuesta completada/recompensada.
  Future<({Preferences? prefs, bool completed, bool rewarded})> preferences(
    String userId,
  );

  /// Guarda las preferencias del usuario.
  Future<void> savePreferences(
    String userId,
    Preferences p, {
    required bool completed,
  });

  /// Completa la encuesta y devuelve las Gotas acreditadas (o `null`).
  Future<int?> completeSurvey();

  /// Lee los ajustes guardados del usuario.
  Future<AppSettings?> settings(String userId);

  /// Guarda los ajustes del usuario.
  Future<void> saveSettings(String userId, AppSettings s);

  /// Lee los platos y sedes favoritas del usuario.
  Future<({Set<String> dishes, Set<String> branches})> favorites(String userId);

  /// Agrega o quita un plato de favoritos.
  Future<void> setFavoriteDish(String userId, String dishId, bool favorite);

  /// Agrega o quita una sede de favoritos.
  Future<void> setFavoriteBranch(String userId, String branchId, bool favorite);

  /// Crea una dirección y devuelve su uuid.
  Future<String?> addAddress(
    String userId,
    Address a, {
    required bool makeDefault,
  });

  /// Actualiza una dirección guardada.
  Future<void> updateAddress(String dbId, Address a);

  /// Borra (lógicamente) una dirección guardada.
  Future<void> deleteAddress(String dbId);

  /// Marca una dirección como principal.
  Future<void> setDefaultAddress(String userId, String dbId);

  /// Cupones del usuario.
  Future<List<Coupon>> coupons(String userId);
}
