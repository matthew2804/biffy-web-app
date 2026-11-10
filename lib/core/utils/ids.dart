final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// `true` si [value] es un uuid. Así se identifican las filas que ya existen
/// en el servidor; los ids locales de la demo («addr-3») no lo son.
bool isUuid(String value) => _uuidPattern.hasMatch(value);
