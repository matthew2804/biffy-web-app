import 'package:biffy/domain/usecases/orders/get_delivery_evidence.dart';
import 'package:biffy/features/buyer/tracking/delivery_evidence_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_order_repository.dart';

/// Crea el cubit sobre un repositorio falso ya configurado.
DeliveryEvidenceCubit _cubit(FakeOrderRepository repo) => DeliveryEvidenceCubit(
  getEvidence: GetDeliveryEvidence(repo),
  orderId: 'BF-1',
);

void main() {
  const loading = DeliveryEvidenceState();

  blocTest<DeliveryEvidenceCubit, DeliveryEvidenceState>(
    'con foto en el servidor muestra la URL firmada',
    build: () => _cubit(FakeOrderRepository()..evidence = 'https://x/firmada'),
    expect: () => [
      const DeliveryEvidenceState(
        status: EvidenceStatus.ready,
        url: 'https://x/firmada',
      ),
    ],
  );

  blocTest<DeliveryEvidenceCubit, DeliveryEvidenceState>(
    'sin foto queda vacío',
    build: () => _cubit(FakeOrderRepository()),
    expect: () => [const DeliveryEvidenceState(status: EvidenceStatus.empty)],
  );

  final flaky = FakeOrderRepository()..evidenceError = true;
  blocTest<DeliveryEvidenceCubit, DeliveryEvidenceState>(
    'sin red muestra error y el reintento recupera la foto',
    build: () => _cubit(flaky),
    act: (c) async {
      await Future<void>.delayed(Duration.zero);
      flaky
        ..evidenceError = false
        ..evidence = 'https://x/firmada';
      await c.load();
    },
    expect: () => [
      const DeliveryEvidenceState(status: EvidenceStatus.failed),
      loading,
      const DeliveryEvidenceState(
        status: EvidenceStatus.ready,
        url: 'https://x/firmada',
      ),
    ],
  );
}
