/// Estado de la última carga de datos remotos (catálogo o pedidos).
///
/// Sirve para distinguir «no hay nada» de «no pudimos cargar»: una lista vacía
/// con [failed] muestra error con reintento, no un vacío falso.
enum SyncStatus {
  /// Aún no llega la primera respuesta del servidor.
  loading,

  /// La última carga terminó bien (en la demo siempre es así).
  ready,

  /// La última carga falló; se conserva la copia anterior si la había.
  failed,
}
