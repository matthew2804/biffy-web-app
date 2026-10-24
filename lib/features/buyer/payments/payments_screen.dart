import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../shared/state/session_controller.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final selected = session.data.defaultPayment;
    return Scaffold(
      appBar: AppBar(title: const Text('Métodos de pago')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const DemoBadge('Simulado · no se procesan pagos'),
            const SizedBox(height: 8),
            Text(
              'Elige tu método predeterminado. No pedimos ni guardamos datos bancarios.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final m in PaymentMethod.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: BiffyCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: selected == m
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                  onTap: () {
                    session.setDefaultPayment(m);
                    showSnack(
                      context,
                      '${m.label} es tu método predeterminado',
                    );
                  },
                  child: Row(
                    children: [
                      Text(m.emoji, style: const TextStyle(fontSize: 24)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          m.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Icon(
                        selected == m
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: selected == m ? AppColors.primary : null,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
