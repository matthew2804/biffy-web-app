import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/repositories/supabase_rewards_repository.dart';
import '../../../shared/state/session_controller.dart';

/// Pantalla de Gotas: saldo, cómo ganarlas, canjes e historial.
///
/// En modo demo usa los beneficios locales (`kBenefits`); con Supabase usa las
/// cajas de la base y el RPC `redeem_reward`.
class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen> {
  /// Repositorio remoto; null en modo demo.
  SupabaseRewardsRepository? _repo;

  /// Cajas cargadas desde Supabase.
  Future<List<GotasBox>>? _boxes;

  /// Historial de canjes remoto.
  Future<List<RewardRedemption>>? _history;

  /// Evita doble toque mientras un canje está en curso.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Solo se conecta a la base si la sesión es remota.
    if (context.read<SessionController>().auth.isRemote) {
      _repo = SupabaseRewardsRepository();
      _reload();
    }
  }

  /// Dispara la carga de cajas e historial.
  void _reload() {
    _boxes = _repo!.boxes();
    _history = _repo!.history();
  }

  /// Canjea una caja/recompensa y muestra el premio sorteado.
  Future<void> _open(GotasBox box, int gotas) async {
    final ok = await showConfirm(
      context,
      title: '¿Abrir ${box.name}?',
      message: box.isRandom
          ? 'Se descontarán ${box.cost} Gotas y el premio es aleatorio (${box.prizes} posibles).'
          : 'Se descontarán ${box.cost} Gotas de tu saldo ($gotas).',
      confirm: box.isRandom ? 'Abrir' : 'Canjear',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final out = await _repo!.redeem(box.code);
    if (!mounted) return;

    // El saldo real vive en la base: se refresca tras el canje.
    await context.read<SessionController>().refreshRemote();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _reload();
    });

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
            if (_repo == null) ..._demoBenefits(context, session, d.gotas) else ..._remoteBoxes(context, d.gotas),
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
            if (_repo == null) ..._localHistory(t, session, now),
            if (_repo != null) ..._remoteHistory(t, now),
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
                      Text(b.description, style: Theme.of(context).textTheme.bodySmall),
                      Text(
                        '${b.cost} Gotas',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  key: Key('redeem-${b.id}'),
                  style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
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

  /// Sección de cajas de Supabase.
  List<Widget> _remoteBoxes(BuildContext context, int gotas) {
    return [
      const SectionHeader('Cajas y recompensas'),
      FutureBuilder<List<GotasBox>>(
        future: _boxes,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Text('No pudimos cargar las recompensas.');
          }
          final boxes = snapshot.data ?? const <GotasBox>[];
          if (boxes.isEmpty) {
            return const Text('Todavía no hay recompensas activas.');
          }
          return Column(
            children: [
              for (final box in boxes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BoxTile(
                    box: box,
                    gotas: gotas,
                    busy: _busy,
                    onOpen: () => _open(box, gotas),
                  ),
                ),
            ],
          );
        },
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

  /// Historial de canjes remoto (Supabase).
  List<Widget> _remoteHistory(TextTheme t, DateTime now) {
    return [
      const SectionHeader('Mis canjes'),
      FutureBuilder<List<RewardRedemption>>(
        future: _history,
        builder: (context, snapshot) {
          final rows = snapshot.data ?? const <RewardRedemption>[];
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (rows.isEmpty) {
            return Text('Aún no has canjeado recompensas.', style: t.bodySmall);
          }
          return Column(
            children: [
              for (final r in rows)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Text('🎁', style: TextStyle(fontSize: 24)),
                  title: Text(r.prizeLabel ?? 'Recompensa canjeada'),
                  subtitle: Text(relativeDay(r.at, now)),
                  trailing: Text(
                    '-${r.spent}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.error,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ];
  }
}

/// Tarjeta con el saldo actual de Gotas.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.gotas});

  final int gotas;

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

/// Tarjeta de una caja remota con su botón de apertura.
class _BoxTile extends StatelessWidget {
  const _BoxTile({
    required this.box,
    required this.gotas,
    required this.busy,
    required this.onOpen,
  });

  final GotasBox box;
  final int gotas;
  final bool busy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final canPay = gotas >= box.cost && !busy;

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
                      ? '${box.prizes} premios posibles'
                      : 'Recompensa directa',
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
              !canPay && gotas < box.cost
                  ? 'Faltan ${box.cost - gotas}'
                  : 'Abrir',
            ),
          ),
        ],
      ),
    );
  }
}
