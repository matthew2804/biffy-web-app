import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/catalog.dart';
import '../../../data/models/rewards.dart';
import '../../../domain/repositories/merchant_boxes_repository.dart';
import '../../../domain/usecases/merchant_boxes_usecases.dart';

/// Etapa de la carga de cajas.
enum BoxesStatus { loading, ready, error }

/// Estado de la pantalla de cajas del restaurante.
class MerchantBoxesState {
  const MerchantBoxesState({
    this.status = BoxesStatus.loading,
    this.data = const MerchantBoxes(boxes: [], items: []),
    this.busy = false,
    this.message,
    this.messageIsError = false,
    this.messageCount = 0,
  });

  final BoxesStatus status;
  final MerchantBoxes data;

  /// `true` mientras se guarda un cambio (evita doble toque).
  final bool busy;

  /// Último aviso para el usuario; [messageCount] sube con cada uno.
  final String? message;
  final bool messageIsError;
  final int messageCount;

  MerchantBoxesState copyWith({
    BoxesStatus? status,
    MerchantBoxes? data,
    bool? busy,
  }) => MerchantBoxesState(
    status: status ?? this.status,
    data: data ?? this.data,
    busy: busy ?? this.busy,
    message: message,
    messageIsError: messageIsError,
    messageCount: messageCount,
  );

  MerchantBoxesState withMessage(String text, {bool error = false}) =>
      MerchantBoxesState(
        status: status,
        data: data,
        busy: busy,
        message: text,
        messageIsError: error,
        messageCount: messageCount + 1,
      );
}

/// Cubit de las cajas del restaurante: cargar, meter y sacar platos, y
/// validar el código del premio que trae el cliente.
///
/// Flujo: pantalla → [MerchantBoxesCubit] → casos de uso →
/// [MerchantBoxesRepository] (Supabase).
class MerchantBoxesCubit extends Cubit<MerchantBoxesState> {
  MerchantBoxesCubit(MerchantBoxesRepository repo)
    : _repo = repo,
      _load = LoadMerchantBoxes(repo),
      _add = AddDishToBox(repo),
      _claim = ClaimBoxPrize(repo),
      super(const MerchantBoxesState());

  final MerchantBoxesRepository _repo;
  final LoadMerchantBoxes _load;
  final AddDishToBox _add;
  final ClaimBoxPrize _claim;

  /// Carga las cajas y los platos del negocio.
  Future<void> load() async {
    emit(state.copyWith(status: BoxesStatus.loading));
    try {
      final data = await _load();
      if (!isClosed) {
        emit(state.copyWith(status: BoxesStatus.ready, data: data));
      }
    } on Object {
      if (!isClosed) emit(state.copyWith(status: BoxesStatus.error));
    }
  }

  /// Mete [dish] en [box] y recarga.
  Future<void> addDish(GotasBox box, Dish dish) =>
      _change(() => _add(box, dish), '${dish.name} entró a ${box.name}');

  /// Saca [item] de su caja y recarga.
  Future<void> removeDish(BoxItemView item) => _change(
    () => _repo.removeItem(item.id),
    '${item.dishName} salió de la caja',
  );

  /// Valida el código del premio y avisa el resultado.
  Future<bool> claim(String code) async {
    final res = await _claim(code);
    if (isClosed) return res.ok;
    emit(
      res.ok
          ? state.withMessage('Premio entregado: ${res.prize}')
          : state.withMessage(res.error ?? 'No se pudo validar', error: true),
    );
    return res.ok;
  }

  Future<void> _change(Future<void> Function() action, String done) async {
    if (state.busy) return;
    emit(state.copyWith(busy: true));
    try {
      await action();
      final data = await _load();
      if (isClosed) return;
      emit(
        state
            .copyWith(busy: false, status: BoxesStatus.ready, data: data)
            .withMessage(done),
      );
    } on Object {
      if (isClosed) return;
      emit(
        state
            .copyWith(busy: false)
            .withMessage('No pudimos guardar el cambio.', error: true),
      );
    }
  }
}
