import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../domain/repositories/merchant_boxes_repository.dart';
import '../../domain/repositories/rewards_repository.dart';
import '../models/rewards.dart';

export '../models/rewards.dart';

/// Acceso a recompensas y canjes en Supabase.
///
/// Toda la escritura pasa por el RPC `redeem_reward`: la app nunca descuenta
/// Gotas por su cuenta en modo remoto.
class SupabaseRewardsRepository
    implements RewardsRepository, MerchantBoxesRepository {
  /// Usa el cliente de Supabase indicado o el global.
  SupabaseRewardsRepository({sb.SupabaseClient? client})
    : _client = client ?? sb.Supabase.instance.client;

  final sb.SupabaseClient _client;

  /// Catálogo de recompensas activas con su número de premios.
  @override
  Future<List<GotasBox>> boxes() async {
    // Los premios se piden en paralelo con las recompensas.
    final prizesF = _client.from('gotas_reward_prizes').select('reward_id');

    List<Map<String, dynamic>> rewards;
    try {
      rewards = await _client
          .from('gotas_rewards')
          .select(
            'id, code, name, reward_type, gotas_cost, tier, draw_frequency, '
            'cooldown_hours, merchant_managed, sort',
          )
          .eq('is_active', true)
          .order('sort');
    } on Object {
      // Proyecto sin la migración 0012: se lee el esquema anterior.
      rewards = await _client
          .from('gotas_rewards')
          .select(
            'id, code, name, reward_type, gotas_cost, tier, draw_frequency',
          )
          .eq('is_active', true)
          .order('gotas_cost');
    }

    final prizes = await prizesF;

    final countByReward = <String, int>{};
    for (final row in prizes) {
      final id = row['reward_id'] as String?;
      if (id == null) continue;
      countByReward[id] = (countByReward[id] ?? 0) + 1;
    }

    return rewards
        .map(
          (row) => GotasBox(
            code: row['code'] as String,
            name: (row['name'] as String?) ?? '',
            type: (row['reward_type'] as String?) ?? 'discount',
            cost: ((row['gotas_cost'] as num?) ?? 0).toInt(),
            tier: (row['tier'] as num?)?.toInt(),
            prizes: countByReward[row['id']] ?? 0,
            drawFrequency: row['draw_frequency'] as String?,
            cooldownHours: ((row['cooldown_hours'] as num?) ?? 0).toInt(),
            merchantManaged: (row['merchant_managed'] as bool?) ?? false,
            sort: ((row['sort'] as num?) ?? 0).toInt(),
          ),
        )
        .toList();
  }

  /// Canjea una recompensa. Devuelve el premio y el saldo nuevo.
  @override
  Future<RedeemOutcome> redeem(String code) async {
    try {
      final res = await _client.rpc(
        'redeem_reward',
        params: {
          'p_payload': {'code': code},
        },
      );
      final map = res is Map ? res : const {};
      final result = map['result'];
      if (result != 'ok') {
        return RedeemOutcome(
          ok: false,
          balance: ((map['balance'] as num?) ?? 0).toInt(),
          error: _message(result as String?),
          cooldownHours: ((map['cooldown_hours'] as num?) ?? 0).toInt(),
        );
      }
      final prize = map['prize'];
      return RedeemOutcome(
        ok: true,
        balance: ((map['balance'] as num?) ?? 0).toInt(),
        prizeLabel: prize is Map ? prize['label'] as String? : null,
        prizeType: prize is Map ? prize['type'] as String? : null,
        prizeAmount: prize is Map
            ? ((prize['amount'] as num?) ?? 0).toInt()
            : 0,
        claimCode: prize is Map ? prize['claim_code'] as String? : null,
      );
    } on Object {
      return const RedeemOutcome(ok: false, balance: 0, error: 'Sin conexión');
    }
  }

  /// Últimos canjes del usuario (RLS solo devuelve los propios).
  @override
  Future<List<RewardRedemption>> history() async {
    final rows = await _client
        .from('reward_redemptions')
        .select(
          'id, gotas_spent, prize_label, prize_type, status, claim_code, '
          'created_at, reward:gotas_rewards(code), branch:branches(name)',
        )
        .order('created_at', ascending: false)
        .limit(30);

    return rows
        .map(
          (row) => RewardRedemption(
            id: (row['id'] as String?) ?? '',
            spent: ((row['gotas_spent'] as num?) ?? 0).toInt(),
            at:
                DateTime.tryParse((row['created_at'] as String?) ?? '') ??
                DateTime.now(),
            prizeLabel: row['prize_label'] as String?,
            prizeType: row['prize_type'] as String?,
            status: (row['status'] as String?) ?? 'granted',
            claimCode: row['claim_code'] as String?,
            branchName: (row['branch'] is Map
                ? (row['branch'] as Map)['name'] as String?
                : null),
            rewardCode:
                (row['reward'] is Map
                    ? (row['reward'] as Map)['code'] as String?
                    : null) ??
                '',
          ),
        )
        .toList();
  }

  /// Últimos movimientos del libro de Gotas (RLS solo devuelve los propios).
  @override
  Future<List<GotasMovement>> ledger() async {
    final rows = await _client
        .from('gotas_ledger')
        .select('amount, reason, created_at')
        .order('created_at', ascending: false)
        .limit(30);

    return rows
        .map(
          (row) => GotasMovement(
            amount: ((row['amount'] as num?) ?? 0).toInt(),
            reason: (row['reason'] as String?) ?? '',
            at:
                DateTime.tryParse((row['created_at'] as String?) ?? '') ??
                DateTime.now(),
          ),
        )
        .toList();
  }

  /// Valida el código de un premio en la sede (solo el negocio dueño).
  @override
  Future<({bool ok, String? prize, String? error})> useRedemption(
    String code,
  ) async {
    try {
      final res = await _client.rpc(
        'use_reward_redemption',
        params: {'p_code': code.trim().toUpperCase()},
      );
      final map = res is Map ? res : const {};
      if (map['result'] == 'ok') {
        return (ok: true, prize: map['prize'] as String?, error: null);
      }
      final message = switch (map['result']) {
        'not_found' => 'Código no encontrado.',
        'already_used' => 'Ese premio ya fue reclamado.',
        'expired' => 'El premio venció.',
        'forbidden' => 'Ese premio no es de tu negocio.',
        _ => 'No se pudo validar el código.',
      };
      return (ok: false, prize: null, error: message);
    } on Object {
      return (ok: false, prize: null, error: 'Sin conexión');
    }
  }

  // ---------------------------------------------------- Lado comerciante

  /// Platos que el negocio tiene metidos en cajas (RLS limita a sus sedes).
  @override
  Future<List<BoxItemView>> merchantItems() async {
    final rows = await _client
        .from('box_items')
        .select(
          'id, reward_id, dish_id, branch_id, '
          'dish:dishes(name), branch:branches(name), reward:gotas_rewards(code)',
        );

    return rows
        .map(
          (row) => BoxItemView(
            id: row['id'] as String,
            rewardCode:
                (row['reward'] is Map
                    ? (row['reward'] as Map)['code'] as String?
                    : null) ??
                '',
            dishId: row['dish_id'] as String,
            branchId: row['branch_id'] as String,
            dishName:
                (row['dish'] is Map
                    ? (row['dish'] as Map)['name'] as String?
                    : null) ??
                'Plato',
            branchName:
                (row['branch'] is Map
                    ? (row['branch'] as Map)['name'] as String?
                    : null) ??
                'Sede',
          ),
        )
        .toList();
  }

  /// Mete un plato del negocio en una caja (idempotente).
  @override
  Future<void> addItem({
    required String rewardCode,
    required String branchId,
    required String dishId,
  }) async {
    final reward = await _client
        .from('gotas_rewards')
        .select('id')
        .eq('code', rewardCode)
        .maybeSingle();
    final rewardId = reward?['id'] as String?;
    if (rewardId == null) return;

    await _client.from('box_items').upsert({
      'reward_id': rewardId,
      'branch_id': branchId,
      'dish_id': dishId,
      'is_active': true,
    }, onConflict: 'reward_id,branch_id,dish_id');
  }

  /// Saca un plato de la caja.
  @override
  Future<void> removeItem(String id) async {
    await _client.from('box_items').delete().eq('id', id);
  }

  /// Traduce los códigos del RPC a mensajes para el usuario.
  static String _message(String? code) => switch (code) {
    'insufficient_gotas' => 'No te alcanzan las Gotas.',
    'reward_not_found' => 'Esa recompensa ya no está disponible.',
    'not_authenticated' => 'Inicia sesión para canjear.',
    'cooldown' => 'Ya abriste esta caja. Vuelve cuando se recargue.',
    'daily_limit' => 'Alcanzaste el límite de hoy para esta caja.',
    _ => 'No pudimos completar el canje.',
  };
}
