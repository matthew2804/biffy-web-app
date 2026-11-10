/// Recompensa canjeable con Gotas tal como viene de la base.
class GotasBox {
  /// Crea la caja con su código, costo y premios.
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
  /// Crea el resultado del canje.
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
  /// Crea el registro de un canje.
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
  /// Crea un movimiento del libro de Gotas.
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

/// Un plato dentro de una caja, visto por el comerciante.
class BoxItemView {
  /// Crea la vista de un plato dentro de una caja.
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
