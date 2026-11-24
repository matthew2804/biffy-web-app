import 'package:flutter/material.dart';

import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../domain/scheduling.dart';

/// Selector de día y hora compatible con el horario simulado del restaurante.
/// Selector de día y hora compatible con el horario simulado del restaurante.
Future<DateTime?> showScheduleSheet(
  BuildContext context, {
  required Restaurant restaurant,
  required DateTime now,
  DateTime? initial,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _ScheduleSheet(restaurant: restaurant, now: now, initial: initial),
  );
}

/// Hoja inferior para elegir día y hora del pedido programado.
class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({
    required this.restaurant,
    required this.now,
    this.initial,
  });
  final Restaurant restaurant;
  final DateTime now;
  final DateTime? initial;

  /// Crea el estado del selector de horario.
  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

/// Estado con el día y la hora seleccionados.
class _ScheduleSheetState extends State<_ScheduleSheet> {
  late final List<DateTime> _days = availableDays(
    widget.restaurant,
    widget.now,
  );
  DateTime? _day;
  DateTime? _time;

  /// Preselecciona la hora inicial si sigue siendo válida.
  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null && isValidSchedule(widget.restaurant, init, widget.now)) {
      _day = DateTime(init.year, init.month, init.day);
      _time = init;
    } else if (_days.isNotEmpty) {
      _day = _days.first;
    }
  }

  /// Construye las pastillas de día, hora y el botón de confirmación.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final slots = _day == null
        ? <DateTime>[]
        : slotsFor(widget.restaurant, _day!, widget.now);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text('Programar pedido', style: t.titleLarge),
            Text(
              'Horario de ${widget.restaurant.name}: ${two(widget.restaurant.openHour)}:00 – ${two(widget.restaurant.closeHour)}:00',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_days.isEmpty)
              const EmptyState(
                emoji: '📅',
                title: 'No hay horarios disponibles en los próximos 7 días',
              )
            else ...[
              Text('Día', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in _days)
                    SelectPill(
                      key: Key('day-${d.day}'),
                      label: relativeDay(d, widget.now),
                      selected: _day != null && sameDay(_day!, d),
                      onTap: () => setState(() {
                        // Al cambiar de día se elimina la hora si deja de ser válida.
                        _time = keepTimeIfValid(
                          widget.restaurant,
                          d,
                          _time,
                          widget.now,
                        );
                        _day = d;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Hora', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in slots)
                    SelectPill(
                      key: Key('slot-${hourLabel(s)}'),
                      label: hourLabel(s),
                      selected: _time == s,
                      onTap: () => setState(() => _time = s),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                key: const Key('schedule-confirm'),
                label: _time == null
                    ? 'Elige una hora'
                    : 'Programar para ${dateTimeLabel(_time!)}',
                onPressed: _time == null
                    ? null
                    : () => Navigator.pop(context, _time),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
