import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Recompensa canjeable con Gotas tal como viene de la base.
class GotasBox {
  const GotasBox({
    required this.code,
    required this.name,
    required this.type,
    required this.cost,
    required this.prizes,
    this.tier,
    this.drawFrequency,
    this.cooldownHours = 0,
    this.merchantManaged = false,
    this.sort = 0,
  });

  /// Código estable usado por el RPC (`box_25`, `free_shipping`, ...).
  final String code;

  /// Nombre visible para el comprador.
  final String name;

  /// `mystery_box`, `monthly_raffle`, `free_shipping` o `discount`.
  final String type;

  /// Costo en Gotas.
  final int cost;

  /// Nivel de la caja (1, 2, 3...). Null si no aplica.
  final int? tier;

  /// Cuántos premios distintos puede entregar (0 = recompensa directa).
  final int prizes;

  /// `monthly` para el sorteo mensual; null en el resto.
  final String? drawFrequency;

  /// Horas de espera entre canjes. 0 = ilimitada.
  final int cooldownHours;

  /// `true` si los restaurantes pueden meter sus platos en esta caja.
  final bool merchantManaged;

  /// Orden de presentación en la lista.
  final int sort;

  /// `true` si al canjearla se sortea un premio.
  bool get isRandom => type == 'mystery_box' || type == 'monthly_raffle';

  /// Texto corto con el límite de canjes.
  String get limitLabel =>
      cooldownHours == 0 ? 'Ilimitada' : 'Cada $cooldownHours h';

  /// Emoji que representa la recompensa en la interfaz.
  String get emoji => switch (type) {
    'mystery_box' => '📦',
    'monthly_raffle' => '🎟️',
    'free_shipping' => '🚚',
    _ => '🎁',
  };
}

/// Resultado de canjear una recompensa.
class RedeemOutcome {
  const RedeemOutcome({
    required this.ok,
    required this.balance,
    this.prizeLabel,
    this.prizeType,
    this.prizeAmount = 0,
    this.error,
    this.cooldownHours = 0,
    this.claimCode,
  });

  /// `true` si el canje se completó en la base.
  final bool ok;

  /// Saldo que queda después del canje.
  final int balance;

  /// Texto del premio sorteado (null en recompensas directas).
  final String? prizeLabel;

  /// Tipo del premio: `discount`, `free_shipping`, `product`, `raffle_ticket`.
  final String? prizeType;

  /// Valor del premio en pesos (0 si no aplica).
  final int prizeAmount;

  /// Código de error devuelto por el RPC, ya traducido.
  final String? error;

  /// Horas de espera cuando el canje se bloquea por enfriamiento.
  final int cooldownHours;

  /// Código para reclamar un plato en la sede.
  final String? claimCode;
}

/// Un canje del historial.
class RewardRedemption {
  const RewardRedemption({
    required this.spent,
    required this.at,
    this.prizeLabel,
    this.id = '',
    this.rewardCode = '',
    this.prizeType,
    this.status = 'granted',
    this.claimCode,
    this.branchName,
  });

  /// Gotas descontadas.
  final int spent;

  /// Cuándo se canjeó.
  final DateTime at;

  /// Premio obtenido, si la recompensa era aleatoria.
  final String? prizeLabel;

  /// Id del canje (para operaciones del comercio).
  final String id;

  /// Código de la caja canjeada (`box_5`, ...).
  final String rewardCode;

  /// `discount`, `free_shipping`, `product` o `raffle_ticket`.
  final String? prizeType;

  /// `granted`, `used`, `expired` o `cancelled`.
  final String status;

  /// Código que el comprador muestra en la sede (solo platos).
  final String? claimCode;

  /// Sede donde se reclama el plato.
  final String? branchName;

  /// `true` si es un plato pendiente de reclamar.
  bool get isPendingPrize =>
      prizeType == 'product' && status == 'granted' && claimCode != null;
}

/// Un movimiento del libro de Gotas.
class GotasMovement {
  const GotasMovement({
    required this.amount,
    required this.reason,
    required this.at,
  });

  /// Gotas sumadas (positivo) o restadas (negativo).
  final int amount;

  /// Motivo del movimiento.
  final String reason;

  /// Cuándo ocurrió.
  final DateTime at;
}

/// Acceso a recompensas y canjes en Supabase.
///
/// Toda la escritura pasa por el RPC `redeem_reward`: la app nunca descuenta
/// Gotas por su cuenta en modo remoto.
class SupabaseRewardsRepository {
  /// Usa el cliente de Supabase indicado o el global.
  SupabaseRewardsRepository({sb.SupabaseClient? client})
    : _client = client ?? sb.Supabase.instance.client;

  final sb.SupabaseClient _client;

  /// Catálogo de recompensas activas con su número de premios.
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
          .select('id, code, name, reward_type, gotas_cost, tier, draw_frequency')
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
            branchName:
                (row['branch'] is Map
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

    await _client.from('box_items').upsert(
      {
        'reward_id': rewardId,
        'branch_id': branchId,
        'dish_id': dishId,
        'is_active': true,
      },
      onConflict: 'reward_id,branch_id,dish_id',
    );
  }

  /// Saca un plato de la caja.
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

/// Un plato dentro de una caja, visto por el comerciante.
class BoxItemView {
  const BoxItemView({
    required this.id,
    required this.rewardCode,
    required this.dishId,
    required this.branchId,
    required this.dishName,
    required this.branchName,
  });

  /// Id de la fila en `box_items`.
  final String id;

  /// Código de la caja (`box_5`, `box_25`, ...).
  final String rewardCode;

  /// Plato incluido.
  final String dishId;

  /// Sede a la que pertenece.
  final String branchId;

  /// Nombre del plato.
  final String dishName;

  /// Nombre de la sede.
  final String branchName;
}
