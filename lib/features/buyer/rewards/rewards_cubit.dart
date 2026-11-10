import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/rewards.dart';
import '../../../domain/repositories/rewards_repository.dart';
import '../../../domain/rewards_rules.dart';
import '../../../domain/usecases/rewards_usecases.dart';

/// Etapa de la carga de recompensas.
enum RewardsStatus { loading, ready, error }

/// Estado de la pantalla de Gotas (modo Supabase).
class RewardsState {
  /// Crea el estado; por defecto está cargando y sin datos.
  const RewardsState({
    this.status = RewardsStatus.loading,
    this.boxes = const [],
    this.history = const [],
    this.ledger = const [],
    this.busy = false,
    this.lastBox,
    this.lastOutcome,
    this.redeemCount = 0,
  });

  final RewardsStatus status;
  final List<GotasBox> boxes;
  final List<RewardRedemption> history;
  final List<GotasMovement> ledger;

  /// `true` mientras un canje está en curso (evita doble toque).
  final bool busy;

  /// Último canje terminado y su resultado (para mostrar el premio).
  final GotasBox? lastBox;
  final RedeemOutcome? lastOutcome;

  /// Sube con cada canje terminado; la pantalla reacciona a ese cambio.
  final int redeemCount;

  /// Premios de plato pendientes de reclamar en el restaurante.
  List<RewardRedemption> get pendingPrizes =>
      history.where((r) => r.isPendingPrize).toList();

  /// Copia el estado cambiando solo lo indicado.
  RewardsState copyWith({
    RewardsStatus? status,
    List<GotasBox>? boxes,
    List<RewardRedemption>? history,
    List<GotasMovement>? ledger,
    bool? busy,
    GotasBox? lastBox,
    RedeemOutcome? lastOutcome,
    int? redeemCount,
  }) => RewardsState(
    status: status ?? this.status,
    boxes: boxes ?? this.boxes,
    history: history ?? this.history,
    ledger: ledger ?? this.ledger,
    busy: busy ?? this.busy,
    lastBox: lastBox ?? this.lastBox,
    lastOutcome: lastOutcome ?? this.lastOutcome,
    redeemCount: redeemCount ?? this.redeemCount,
  );
}

/// Cubit de Gotas: carga cajas, historial y movimientos, y canjea.
///
/// Flujo: pantalla → [RewardsCubit] → [LoadRewards] / [RedeemReward] →
/// [RewardsRepository] (Supabase, RPC `redeem_reward`).
class RewardsCubit extends Cubit<RewardsState> {
  /// Recibe el repositorio y cómo refrescar el saldo de la sesión.
  RewardsCubit(
    RewardsRepository repo, {
    required Future<void> Function() refreshBalance,
    DateTime Function()? now,
  }) : _load = LoadRewards(repo),
       _redeem = RedeemReward(repo),
       _refreshBalance = refreshBalance, // ignore: prefer_initializing_formals
       _now = now ?? DateTime.now,
       super(const RewardsState());

  final LoadRewards _load;
  final RedeemReward _redeem;
  final Future<void> Function() _refreshBalance;
  final DateTime Function() _now;

  /// Carga (o recarga) todo desde la base.
  Future<void> load() async {
    emit(state.copyWith(status: RewardsStatus.loading));
    try {
      final snap = await _load();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: RewardsStatus.ready,
          boxes: snap.boxes,
          history: snap.history,
          ledger: snap.ledger,
        ),
      );
    } on Object {
      if (!isClosed) emit(state.copyWith(status: RewardsStatus.error));
    }
  }

  /// Cuándo se puede volver a abrir [box] (`null` = disponible ya).
  DateTime? availableAt(GotasBox box) => nextAvailableAt(
    box,
    lastRedeemedByReward(state.history)[box.code],
    _now(),
  );

  /// Canjea [box]; el saldo real se vuelve a leer de la base al terminar.
  Future<void> redeem(GotasBox box) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    final out = await _redeem(box);
    await _refreshBalance();
    if (isClosed) return;
    var next = state.copyWith(
      busy: false,
      lastBox: box,
      lastOutcome: out,
      redeemCount: state.redeemCount + 1,
    );
    try {
      final snap = await _load();
      next = next.copyWith(
        status: RewardsStatus.ready,
        boxes: snap.boxes,
        history: snap.history,
        ledger: snap.ledger,
      );
    } on Object {
      // Si falla la recarga se conserva lo último que se mostró.
    }
    if (!isClosed) emit(next);
  }
}
