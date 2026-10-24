/// Formateadores en español (Colombia) sin dependencias externas.
library;

String cop(num value) {
  final n = value.round();
  final neg = n < 0;
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${neg ? '-' : ''}\$${buf.toString()}';
}

const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String two(int n) => n.toString().padLeft(2, '0');

String hourLabel(DateTime d) => '${two(d.hour)}:${two(d.minute)}';

String weekdayName(int weekday) => _weekdays[weekday - 1];

String shortDate(DateTime d) =>
    '${_weekdays[d.weekday - 1].substring(0, 3)} ${d.day} ${_months[d.month - 1]}';

String dateTimeLabel(DateTime d) => '${shortDate(d)} · ${hourLabel(d)}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String relativeDay(DateTime d, DateTime now) {
  if (sameDay(d, now)) return 'Hoy';
  if (sameDay(d, now.add(const Duration(days: 1)))) return 'Mañana';
  if (sameDay(d, now.subtract(const Duration(days: 1)))) return 'Ayer';
  return shortDate(d);
}

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Quita tildes y pasa a minúsculas para búsquedas tolerantes.
String normalize(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunAEIOUUN';
  final buf = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    buf.write(i >= 0 ? to[i] : ch);
  }
  return buf.toString().toLowerCase().trim();
}
