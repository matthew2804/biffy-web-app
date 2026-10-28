/// Dirección de entrega guardada (dato local de demostración).
class Address {
  const Address({
    required this.id,
    required this.label,
    required this.line,
    required this.neighborhood,
    required this.pointId,
    this.details = '',
    this.reference = '',
  });

  final String id;

  /// Nombre del lugar (p. ej. «Biblioteca», «Casa»).
  final String label;
  final String line;
  final String details;
  final String neighborhood;
  final String reference;

  /// Zona de cobertura simulada asociada a la dirección.
  final String pointId;

  /// Devuelve una copia con los campos indicados reemplazados.
  Address copyWith({
    String? label,
    String? line,
    String? details,
    String? neighborhood,
    String? reference,
    String? pointId,
  }) {
    return Address(
      id: id,
      label: label ?? this.label,
      line: line ?? this.line,
      details: details ?? this.details,
      neighborhood: neighborhood ?? this.neighborhood,
      reference: reference ?? this.reference,
      pointId: pointId ?? this.pointId,
    );
  }

  /// Dirección completa en una sola línea legible.
  String get full =>
      [line, if (details.isNotEmpty) details, neighborhood].join(' · ');
}
