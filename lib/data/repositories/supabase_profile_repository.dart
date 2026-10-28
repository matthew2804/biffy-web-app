import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../models/address.dart';
import '../models/user.dart';

/// Datos personales del comprador en Supabase: preferencias, ajustes,
/// favoritos y direcciones.
///
/// La sesión trabaja de forma optimista (actualiza memoria y luego escribe):
/// si una escritura falla, la próxima hidratación corrige el estado.
class SupabaseProfileRepository {
  SupabaseProfileRepository({sb.SupabaseClient? client})
    : _client = client ?? sb.Supabase.instance.client;

  final sb.SupabaseClient _client;

  // ------------------------------------------------------- Preferencias

  /// Lee preferencias y sus banderas de encuesta completada/recompensada.
  Future<({Preferences? prefs, bool completed, bool rewarded})> preferences(
    String userId,
  ) async {
    final row = await _client
        .from('preferences')
        .select('likes, lifestyle, allergies, budget, completed, rewarded')
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) {
      return (prefs: null, completed: false, rewarded: false);
    }
    return (
      prefs: Preferences(
        likes: _set(row['likes']),
        lifestyle: _set(row['lifestyle']),
        allergies: _set(row['allergies']),
        budget: ((row['budget'] as num?) ?? 25000).toInt(),
      ),
      completed: (row['completed'] as bool?) ?? false,
      rewarded: (row['rewarded'] as bool?) ?? false,
    );
  }

  /// Guarda las preferencias del usuario.
  Future<void> savePreferences(
    String userId,
    Preferences p, {
    required bool completed,
  }) async {
    await _client.from('preferences').upsert({
      'user_id': userId,
      'likes': p.likes.toList(),
      'lifestyle': p.lifestyle.toList(),
      'allergies': p.allergies.toList(),
      'budget': p.budget,
      'completed': completed,
    });
  }

  /// Acredita las 300 Gotas de la encuesta (una sola vez, en el servidor).
  Future<int?> completeSurvey() async {
    try {
      final res = await _client.rpc('complete_survey');
      final map = res is Map ? res : const {};
      if (map['result'] != 'ok') return null;
      return ((map['awarded'] as num?) ?? 0).toInt();
    } on Object {
      return null;
    }
  }

  // ------------------------------------------------------------ Ajustes

  /// Lee los ajustes de la app del usuario.
  Future<AppSettings?> settings(String userId) async {
    final row = await _client
        .from('app_settings')
        .select('notifications, promotions, email_summary, dark_mode, demo_lunch')
        .eq('user_id', userId)
        .maybeSingle();

    if (row == null) return null;
    return AppSettings(
      notifications: (row['notifications'] as bool?) ?? true,
      promotions: (row['promotions'] as bool?) ?? true,
      emailSummary: (row['email_summary'] as bool?) ?? false,
      darkMode: (row['dark_mode'] as bool?) ?? false,
      demoLunch: (row['demo_lunch'] as bool?) ?? false,
    );
  }

  /// Guarda los ajustes de la app.
  Future<void> saveSettings(String userId, AppSettings s) async {
    await _client.from('app_settings').upsert({
      'user_id': userId,
      'notifications': s.notifications,
      'promotions': s.promotions,
      'email_summary': s.emailSummary,
      'dark_mode': s.darkMode,
      'demo_lunch': s.demoLunch,
    });
  }

  // ---------------------------------------------------------- Favoritos

  /// Lee los platos y sedes favoritas del usuario.
  Future<({Set<String> dishes, Set<String> branches})> favorites(
    String userId,
  ) async {
    final dishes = await _client
        .from('favorite_dishes')
        .select('dish_id')
        .eq('user_id', userId);
    final branches = await _client
        .from('favorite_branches')
        .select('branch_id')
        .eq('user_id', userId);

    return (
      dishes: {for (final r in dishes) r['dish_id'] as String},
      branches: {for (final r in branches) r['branch_id'] as String},
    );
  }

  /// Agrega o quita un plato de favoritos.
  Future<void> setFavoriteDish(
    String userId,
    String dishId,
    bool favorite,
  ) async {
    if (favorite) {
      await _client.from('favorite_dishes').upsert({
        'user_id': userId,
        'dish_id': dishId,
      });
    } else {
      await _client
          .from('favorite_dishes')
          .delete()
          .eq('user_id', userId)
          .eq('dish_id', dishId);
    }
  }

  /// Agrega o quita una sede de favoritos.
  Future<void> setFavoriteBranch(
    String userId,
    String branchId,
    bool favorite,
  ) async {
    if (favorite) {
      await _client.from('favorite_branches').upsert({
        'user_id': userId,
        'branch_id': branchId,
      });
    } else {
      await _client
          .from('favorite_branches')
          .delete()
          .eq('user_id', userId)
          .eq('branch_id', branchId);
    }
  }

  // --------------------------------------------------------- Direcciones

  /// Crea una dirección y devuelve su uuid.
  Future<String?> addAddress(
    String userId,
    Address a, {
    required bool makeDefault,
  }) async {
    final row = await _client
        .from('addresses')
        .insert({
          'user_id': userId,
          'label': a.label,
          'line': a.line,
          'details': a.details,
          'neighborhood': a.neighborhood,
          'reference': a.reference,
          'point_id': a.pointId,
          'is_default': makeDefault,
        })
        .select('id')
        .single();
    return row['id'] as String?;
  }

  /// Actualiza una dirección existente por su uuid.
  Future<void> updateAddress(String dbId, Address a) async {
    await _client
        .from('addresses')
        .update({
          'label': a.label,
          'line': a.line,
          'details': a.details,
          'neighborhood': a.neighborhood,
          'reference': a.reference,
          'point_id': a.pointId,
        })
        .eq('id', dbId);
  }

  /// Borrado lógico de una dirección.
  Future<void> deleteAddress(String dbId) async {
    await _client
        .from('addresses')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', dbId);
  }

  /// Marca una dirección como predeterminada (y desmarca las demás).
  Future<void> setDefaultAddress(String userId, String dbId) async {
    await _client
        .from('addresses')
        .update({'is_default': false})
        .eq('user_id', userId);
    await _client.from('addresses').update({'is_default': true}).eq('id', dbId);
  }

  /// Convierte el arreglo de Postgres en un conjunto de textos.
  static Set<String> _set(Object? value) =>
      (value as List?)?.map((e) => e.toString()).toSet() ?? {};
}
