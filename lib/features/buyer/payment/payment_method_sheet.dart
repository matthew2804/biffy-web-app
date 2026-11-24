import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/entities/catalog.dart';

/// Abre la hoja de métodos de pago y devuelve el elegido (o `null`).
Future<PaymentMethod?> showPaymentMethodSheet(
  BuildContext context, {
  required PaymentMethod selected,
}) {
  return showModalBottomSheet<PaymentMethod>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => PaymentMethodSheet(selected: selected),
  );
}

/// Hoja inferior con los métodos de pago, agrupados como en Rappi.
class PaymentMethodSheet extends StatefulWidget {
  const PaymentMethodSheet({super.key, required this.selected});

  /// Método que ya estaba elegido en el carrito o checkout.
  final PaymentMethod selected;

  /// Crea el estado de la hoja.
  @override
  State<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

/// Estado que mantiene la selección antes de confirmar.
class _PaymentMethodSheetState extends State<PaymentMethodSheet> {
  late PaymentMethod _selected = widget.selected;

  /// Dibuja las secciones, los métodos y el botón de continuar.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: SingleChildScrollView(
        key: const Key('payment-method-sheet'),
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '¿Cómo prefieres pagar?',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              'El pago en línea se completa en Wompi. Allí confirmas el método '
              'y, si eliges PSE, el banco.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            _section(t, 'PAGA AHORA', PaymentMethod.online),
            const SizedBox(height: 12),
            _section(t, 'PAGA AL RECIBIR', PaymentMethod.offline),
            const SizedBox(height: 16),
            PrimaryButton(
              key: const Key('payment-method-continue'),
              label: 'Continuar con ${_selected.label}',
              onPressed: () => Navigator.of(context).pop(_selected),
            ),
          ],
        ),
      ),
    );
  }

  /// Pinta un grupo de métodos con su título.
  Widget _section(TextTheme t, String title, List<PaymentMethod> methods) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: t.labelSmall?.copyWith(
            color: AppColors.muted,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        for (final method in methods)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _MethodTile(
              method: method,
              selected: _selected == method,
              onTap: () => setState(() => _selected = method),
            ),
          ),
      ],
    );
  }
}

/// Fila seleccionable con emoji, nombre, explicación y radio.
class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  /// Dibuja la fila y su estado de selección.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return BiffyCard(
      key: Key('pay-${method.name}'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: Border.all(
        color: selected ? AppColors.primary : Colors.transparent,
        width: 2,
      ),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(method.emoji, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  method.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(method.description, style: t.bodySmall),
              ],
            ),
          ),
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? AppColors.primary : AppColors.muted,
          ),
        ],
      ),
    );
  }
}
