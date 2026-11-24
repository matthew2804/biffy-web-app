import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/orders/get_delivery_evidence.dart';

/// Etapa de la carga de la foto de evidencia.
enum EvidenceStatus { loading, ready, empty, failed }

/// Estado inmutable de la foto de evidencia: etapa y URL firmada.
class DeliveryEvidenceState {
  /// Crea el estado; por defecto, cargando.
  const DeliveryEvidenceState({this.status = EvidenceStatus.loading, this.url});

  final EvidenceStatus status;
  final String? url;

  /// Dos estados son iguales si coinciden etapa y URL.
  @override
  bool operator ==(Object other) =>
      other is DeliveryEvidenceState &&
      other.status == status &&
      other.url == url;

  /// Código hash acorde con la igualdad.
  @override
  int get hashCode => Object.hash(status, url);

  /// Texto legible para depurar y para las pruebas.
  @override
  String toString() => 'DeliveryEvidenceState($status, $url)';
}

/// Pide la URL firmada de la evidencia de un pedido y permite reintentar.
class DeliveryEvidenceCubit extends Cubit<DeliveryEvidenceState> {
  /// Crea el cubit para [orderId] y empieza a cargar.
  DeliveryEvidenceCubit({required this.getEvidence, required this.orderId})
    : super(const DeliveryEvidenceState()) {
    load();
  }

  /// Caso de uso que firma la URL de la foto.
  final GetDeliveryEvidence getEvidence;

  /// Pedido cuya evidencia se muestra.
  final String orderId;

  /// Carga (o recarga) la URL; sin foto queda en `empty` y sin red en `failed`.
  Future<void> load() async {
    emit(const DeliveryEvidenceState());
    try {
      final url = await getEvidence(orderId);
      if (isClosed) return;
      emit(
        url == null
            ? const DeliveryEvidenceState(status: EvidenceStatus.empty)
            : DeliveryEvidenceState(status: EvidenceStatus.ready, url: url),
      );
    } on Object {
      if (!isClosed) {
        emit(const DeliveryEvidenceState(status: EvidenceStatus.failed));
      }
    }
  }
}
