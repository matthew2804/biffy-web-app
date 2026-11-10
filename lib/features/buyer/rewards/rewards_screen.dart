import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/rewards.dart';
import '../../../domain/repositories/rewards_repository.dart';
import '../../../shared/state/session_controller.dart';
import 'rewards_cubit.dart';

/// Pantalla de Gotas: saldo, cómo ganarlas, canjes e historial.
///
/// En modo demo usa los beneficios locales (`kBenefits`); con Supabase la
/// maneja un [RewardsCubit] (cajas de la base y el RPC `redeem_reward`).
class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  /// En demo muestra los beneficios locales; con Supabase crea el cubit.
  @override
  Widget build(BuildContext context) {
    final repo = context.read<RewardsRepository?>();
    if (repo == null) return const _RewardsPage(state: null);
    final session = context.read<SessionController>();
    return BlocProvider(
      create: (_) =>
          RewardsCubit(repo, refreshBalance: session.refreshRemote)..load(),
      child: BlocConsumer<RewardsCubit, RewardsState>(
        listenWhen: (a, b) => a.redeemCount != b.redeemCount,
        listener: (context, state) =>
            _showOutcome(context, state.lastBox!, state.lastOutcome!),
        builder: (context, state) => _RewardsPage(state: state),
      ),
    );
  }
}

/// Muestra el resultado de un canje: error, aviso simple o el premio.
Future<void> _showOutcome(
  BuildContext context,
  GotasBox box,
  RedeemOutcome out,
) async {
  if (!out.ok) {
    showSnack(context, out.error ?? 'No pudimos canjear', error: true);
    return;
  }
  if (out.prizeLabel == null) {
    showSnack(context, '¡${box.name} canjeada!');
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('¡Te salió un premio! 🎉'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            out.prizeLabel!,
            style: const TextStyle(
              fontFamily: AppTypography.heading,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text('Gastaste ${box.cost} Gotas · saldo: ${out.balance}'),
          if (out.claimCode != null) ...[
            const SizedBox(height: 12),
            const Text('Muestra este código en el restaurante:'),
            Text(
              out.claimCode!,
              style: const TextStyle(
                fontFamily: AppTypography.heading,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            const Text('Válido por 30 días.'),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Listo'),
        ),
      ],
    ),
  );
}

/// Cuerpo de la pantalla. Con [state] `null` es el modo demo.
class _RewardsPage extends StatelessWidget {
  const _RewardsPage({required this.state});

  final RewardsState? state;

  /// Construye el saldo, los beneficios y el historial.
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
            _BalanceCard(gotas: d.gotas),
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
            if (state == null)
              ..._demoBenefits(context, session, d.gotas)
            else
              ..._remoteBoxes(context, state!, d.gotas),
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
            if (state == null) ..._localHistory(t, session, now),
            if (state != null) ..._remoteHistory(context, state!, t, now),
          ],
        ),
      ),
    );
  }

  /// Sección de beneficios locales (modo demo).
  List<Widget> _demoBenefits(
    BuildContext context,
    SessionController session,
    int gotas,
  ) {
    return [
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
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        b.description,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${b.cost} Gotas',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  key: Key('redeem-${b.id}'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(96, 44),
                  ),
                  onPressed: gotas < b.cost
                      ? null
                      : () async {
                          final ok = await showConfirm(
                            context,
                            title: '¿Canjear ${b.title}?',
                            message:
                                'Se descontarán ${b.cost} Gotas de tu saldo ($gotas).',
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
                    gotas < b.cost ? 'Faltan ${b.cost - gotas}' : 'Canjear',
                  ),
                ),
              ],
            ),
          ),
        ),
    ];
  }

  /// Confirma y pide al cubit que canjee la caja.
  Future<void> _open(BuildContext context, GotasBox box, int gotas) async {
    final ok = await showConfirm(
      context,
      title: '¿Abrir ${box.name}?',
      message: box.isRandom
          ? 'Se descontarán ${box.cost} Gotas y el premio es aleatorio (${box.prizes} posibles).'
          : 'Se descontarán ${box.cost} Gotas de tu saldo ($gotas).',
      confirm: box.isRandom ? 'Abrir' : 'Canjear',
    );
    if (!ok || !context.mounted) return;
    await context.read<RewardsCubit>().redeem(box);
  }

  /// Sección de cajas de Supabase, con el tiempo de recarga de cada una.
  List<Widget> _remoteBoxes(
    BuildContext context,
    RewardsState state,
    int gotas,
  ) {
    final cubit = context.read<RewardsCubit>();
    return [
      const SectionHeader('Cajas y recompensas'),
      if (state.status == RewardsStatus.loading && state.boxes.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (state.status == RewardsStatus.error && state.boxes.isEmpty)
        ErrorView(
          title: 'No pudimos cargar las recompensas',
          onRetry: cubit.load,
        )
      else if (state.boxes.isEmpty)
        const Text('Todavía no hay recompensas activas.')
      else
        for (final box in state.boxes)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _BoxTile(
              box: box,
              gotas: gotas,
              busy: state.busy,
              availableAt: cubit.availableAt(box),
              onOpen: () => _open(context, box, gotas),
            ),
          ),
    ];
  }

  /// Historial de movimientos local (modo demo).
  List<Widget> _localHistory(
    TextTheme t,
    SessionController session,
    DateTime now,
  ) {
    final d = session.data;
    return [
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
    ];
  }

  /// Premios pendientes de reclamar e historial de canjes (Supabase).
  List<Widget> _remoteHistory(
    BuildContext context,
    RewardsState state,
    TextTheme t,
    DateTime now,
  ) {
    final loading = state.status == RewardsStatus.loading;
    final pending = state.pendingPrizes;
    return [
      const SectionHeader('Mis premios'),
      if (loading && state.history.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (pending.isEmpty)
        Text('No tienes premios pendientes de reclamar.', style: t.bodySmall)
      else
        for (final p in pending) _PrizeCard(prize: p),
      const SectionHeader('Movimientos'),
      if (loading && state.ledger.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (state.ledger.isEmpty)
        Text('Aún no tienes movimientos.', style: t.bodySmall)
      else
        for (final m in state.ledger)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(m.reason),
            subtitle: Text(relativeDay(m.at, now)),
            trailing: Text(
              '${m.amount > 0 ? '+' : ''}${m.amount}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: m.amount > 0 ? AppColors.success : AppColors.error,
              ),
            ),
          ),
    ];
  }
}

/// Tarjeta con el saldo actual de Gotas.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.gotas});

  final int gotas;

  /// Dibuja el saldo de Gotas con su equivalencia aproximada.
  @override
  Widget build(BuildContext context) {
    return BiffyCard(
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
            '💧 $gotas',
            key: const Key('gotas-balance'),
            style: const TextStyle(
              fontFamily: AppTypography.heading,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: AppColors.text,
            ),
          ),
          Text(
            '≈ ${cop(gotas * kGotaValue)} · referencia de la demo (1 Gota = ${cop(kGotaValue)})',
            style: const TextStyle(color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de un premio pendiente con su código de reclamación.
class _PrizeCard extends StatelessWidget {
  const _PrizeCard({required this.prize});

  final RewardRedemption prize;

  /// Muestra el plato ganado y el código que se dicta en la sede.
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BiffyCard(
        color: AppColors.secondary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              prize.prizeLabel ?? 'Premio',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text('Muéstralo en la sede y dicta este código:'),
            Text(
              prize.claimCode ?? '',
              key: const Key('claim-code'),
              style: const TextStyle(
                fontFamily: AppTypography.heading,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
            if (prize.branchName != null)
              Text(
                'Reclama en: ${prize.branchName}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const Text('Válido por 30 días desde el canje.'),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de una caja remota con su botón de apertura.
class _BoxTile extends StatelessWidget {
  const _BoxTile({
    required this.box,
    required this.gotas,
    required this.busy,
    required this.onOpen,
    this.availableAt,
  });

  final GotasBox box;
  final int gotas;
  final bool busy;
  final VoidCallback onOpen;

  /// Si no es null, la caja está en recarga hasta esa hora.
  final DateTime? availableAt;

  /// Dibuja la caja con su costo, el límite y el botón de apertura.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cooling = availableAt != null;
    final canPay = gotas >= box.cost && !busy && !cooling;

    return BiffyCard(
      child: Row(
        children: [
          Text(box.emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  box.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  box.isRandom
                      ? '${box.prizes} premios · ${box.limitLabel}'
                      : box.limitLabel,
                  style: t.bodySmall,
                ),
                Text(
                  '${box.cost} Gotas',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          FilledButton(
            key: Key('open-${box.code}'),
            style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
            onPressed: canPay ? onOpen : null,
            child: Text(
              cooling
                  ? _remaining(availableAt!)
                  : (!canPay && gotas < box.cost
                        ? 'Faltan ${box.cost - gotas}'
                        : 'Abrir'),
            ),
          ),
        ],
      ),
    );
  }

  /// Texto corto del tiempo que falta para la recarga.
  static String _remaining(DateTime until) {
    final diff = until.difference(DateTime.now());
    if (diff.inMinutes <= 0) return 'Lista';
    if (diff.inHours >= 1) return 'En ${diff.inHours} h';
    return 'En ${diff.inMinutes} min';
  }
}
