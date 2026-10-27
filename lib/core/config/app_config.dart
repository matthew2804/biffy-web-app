/// Configuración de compilación.
///
/// Los valores llegan por `--dart-define` / `--dart-define-from-file=env.json`.
/// Si no hay configuración, la app arranca en **modo demo local** (datos en
/// memoria) y no hace ninguna petición de red.
abstract final class AppConfig {
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  /// Clave publicable (`sb_publishable_...`) o anon key. Es pública por
  /// diseño: la protección real son las políticas RLS de la base.
  static const String supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  /// `true` cuando la compilación trae las dos variables.
  static bool get hasSupabase =>
      supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Modo de datos efectivo, útil para rótulos en la interfaz.
  static String get dataMode => hasSupabase ? 'supabase' : 'demo';
}
