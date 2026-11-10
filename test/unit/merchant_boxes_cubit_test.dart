import 'package:biffy/data/models/rewards.dart';
import 'package:biffy/domain/repositories/merchant_boxes_repository.dart';
import 'package:biffy/features/restaurant_owner/boxes/merchant_boxes_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

const _box25 = GotasBox(
  code: 'box_25',
  name: 'Caja sorpresa',
  type: 'mystery_box',
  cost: 25,
  prizes: 5,
  merchantManaged: true,
);
const _shipping = GotasBox(
  code: 'free_shipping',
  name: 'Envío gratis',
  type: 'free_shipping',
  cost: 5,
  prizes: 0,
);

/// Repositorio falso de cajas con los platos en memoria.
class _FakeBoxes implements MerchantBoxesRepository {
  final items = <BoxItemView>[];
  final claimed = <String>[];
  bool failWrites = false;

  @override
  Future<List<GotasBox>> boxes() async => const [_shipping, _box25];

  @override
  Future<List<BoxItemView>> merchantItems() async => List.of(items);

  @override
  Future<void> addItem({
    required String rewardCode,
    required String branchId,
    required String dishId,
  }) async {
    if (failWrites) throw StateError('sin red');
    items.add(
      BoxItemView(
        id: 'i${items.length}',
        rewardCode: rewardCode,
        dishId: dishId,
        branchId: branchId,
        dishName: dishId,
        branchName: branchId,
      ),
    );
  }

  @override
  Future<void> removeItem(String id) async =>
      items.removeWhere((i) => i.id == id);

  @override
  Future<ClaimResult> useRedemption(String code) async {
    claimed.add(code);
    return code == 'ABC123'
        ? (ok: true, prize: 'Qbano de pollo', error: null)
        : (ok: false, prize: null, error: 'Código no encontrado.');
  }
}

void main() {
  late _FakeBoxes repo;
  late MerchantBoxesCubit cubit;
  final dish = makeServices().catalog.dishById('qbano-pollo')!;

  setUp(() {
    repo = _FakeBoxes();
    cubit = MerchantBoxesCubit(repo);
  });
  tearDown(() => cubit.close());

  test('solo muestra las cajas que aceptan platos de restaurantes', () async {
    await cubit.load();
    expect(cubit.state.status, BoxesStatus.ready);
    expect(cubit.state.data.boxes.map((b) => b.code), ['box_25']);
  });

  test('meter y sacar un plato recarga la caja y avisa', () async {
    await cubit.load();
    await cubit.addDish(_box25, dish);
    expect(cubit.state.data.itemsOf(_box25).single.dishId, dish.id);
    expect(cubit.state.message, '${dish.name} entró a Caja sorpresa');
    expect(cubit.state.busy, isFalse);

    await cubit.removeDish(cubit.state.data.itemsOf(_box25).single);
    expect(cubit.state.data.itemsOf(_box25), isEmpty);
    expect(cubit.state.messageCount, 2);
  });

  test('si falla guardar avisa el error y no se queda ocupado', () async {
    await cubit.load();
    repo.failWrites = true;
    await cubit.addDish(_box25, dish);
    expect(cubit.state.messageIsError, isTrue);
    expect(cubit.state.busy, isFalse);
  });

  test(
    'validar premio: vacío no llama a la base; código en mayúsculas',
    () async {
      expect(await cubit.claim('   '), isFalse);
      expect(repo.claimed, isEmpty);
      expect(await cubit.claim(' abc123 '), isTrue);
      expect(repo.claimed, ['ABC123']);
      expect(cubit.state.message, 'Premio entregado: Qbano de pollo');
      expect(await cubit.claim('zzz'), isFalse);
      expect(cubit.state.messageIsError, isTrue);
    },
  );
}
