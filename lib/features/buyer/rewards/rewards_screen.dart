import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/session_controller.dart';

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final d = session.data;
    final t = Theme.of(context).textTheme;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Gotas Biffy')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            BiffyCard(
              color: AppColors.secondary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tu saldo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    '💧 ${d.gotas}',
                    key: const Key('gotas-balance'),
                    style: const TextStyle(
                      fontFamily: AppTypography.heading,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  Text(
                    '≈ ${cop(d.gotas * kGotaValue)} · referencia de la demo (1 Gota = ${cop(kGotaValue)})',
                    style: const TextStyle(color: AppColors.text),
                  ),
                ],
              ),
            ),
            const SectionHeader('Cómo ganar Gotas'),
            BiffyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• $kWelcomeGotas de bienvenida al iniciar sesión por primera vez.',
                    style: t.bodyMedium,
                  ),
                  Text(
                    '• $kSurveyGotas por completar tus preferencias (una sola vez).',
                    style: t.bodyMedium,
                  ),
                  Text(
                    '• 1 Gota por cada ${cop(1000)} de productos en pedidos entregados.',
                    style: t.bodyMedium,
                  ),
                ],
              ),
            ),
            const SectionHeader('Beneficios disponibles'),
            for (final b in kBenefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: BiffyCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(b.description, style: t.bodySmall),
                            Text(
                              '${b.cost} Gotas',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton(
                        key: Key('redeem-${b.id}'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(96, 44),
                        ),
                        onPressed: d.gotas < b.cost
                            ? null
                            : () async {
                                final ok = await showConfirm(
                                  context,
                                  title: '¿Canjear ${b.title}?',
                                  message:
                                      'Se descontarán ${b.cost} Gotas de tu saldo (${d.gotas}).',
                                  confirm: 'Canjear',
                                );
                                if (!ok || !context.mounted) return;
                                final c = session.redeem(b);
                                showSnack(
                                  context,
                                  c == null
                                      ? 'Saldo insuficiente'
                                      : 'Cupón «${c.title}» listo para tu próximo pedido',
                                  error: c == null,
                                );
                              },
                        child: Text(
                          d.gotas < b.cost
                              ? 'Faltan ${b.cost - d.gotas}'
                              : 'Canjear',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (d.coupons.isNotEmpty) ...[
              const SectionHeader('Mis cupones'),
              for (final c in d.coupons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Text('🎟️', style: TextStyle(fontSize: 24)),
                  title: Text(c.title),
                  subtitle: Text(c.used ? 'Usado' : 'Disponible en el carrito'),
                ),
            ],
            const SectionHeader('Historial'),
            if (d.gotasHistory.isEmpty)
              Text('Aún no tienes movimientos.', style: t.bodySmall)
            else
              for (final e in d.gotasHistory)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.title),
                  subtitle: Text(relativeDay(e.at, now)),
                  trailing: Text(
                    '${e.amount > 0 ? '+' : ''}${e.amount}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: e.amount > 0 ? AppColors.success : AppColors.error,
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
