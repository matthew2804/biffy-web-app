import 'package:biffy/data/models/rewards.dart';
import 'package:biffy/domain/repositories/rewards_repository.dart';
import 'package:biffy/domain/rewards_rules.dart';
import 'package:biffy/features/buyer/rewards/rewards_cubit.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 10, 12);

const _box25 = GotasBox(
  code: 'box_25',
  name: 'Caja sorpresa',
  type: 'mystery_box',
  cost: 25,
  prizes: 5,
  cooldownHours: 12,
);
const _box5 = GotasBox(
  code: 'box_5',
  name: 'Caja básica',
  type: 'mystery_box',
  cost: 5,
  prizes: 3,
);

/// Repositorio falso en memoria que registra los canjes.
class FakeRewards implements RewardsRepository {
  FakeRewards({this.fail = false});
  bool fail;
  final redeemed = <String>[];
  final List<RewardRedemption> _history = [];

  @override
  Future<List<GotasBox>> boxes() async {
    if (fail) throw StateError('sin red');
    return const [_box5, _box25];
  }

  @override
  Future<List<RewardRedemption>> history() async => List.of(_history);

  @override
  Future<List<GotasMovement>> ledger() async => [
    GotasMovement(amount: 450, reason: 'Bienvenida', at: _now),
  ];

  @override
  Future<RedeemOutcome> redeem(String code) async {
    redeemed.add(code);
    _history.insert(0, RewardRedemption(spent: 25, at: _now, rewardCode: code));
    return const RedeemOutcome(
      ok: true,
      balance: 425,
      prizeLabel: r'$2.000 de descuento',
      prizeType: 'discount',
    );
  }
}

void main() {
  group('Reglas de recarga', () {
    test('una caja con enfriamiento vuelve a estar disponible a las 12 h', () {
      final used = _now.subtract(const Duration(hours: 3));
      expect(
        nextAvailableAt(_box25, used, _now),
        used.add(const Duration(hours: 12)),
      );
      expect(
        nextAvailableAt(_box25, _now.subtract(const Duration(hours: 13)), _now),
        isNull,
      );
      expect(nextAvailableAt(_box5, used, _now), isNull);
      expect(nextAvailableAt(_box25, null, _now), isNull);
    });

    test('toma el canje más reciente de cada caja', () {
      final last = lastRedeemedByReward([
        RewardRedemption(
          spent: 25,
          at: DateTime(2026, 11, 9),
          rewardCode: 'box_25',
        ),
        RewardRedemption(
          spent: 25,
          at: DateTime(2026, 11, 10),
          rewardCode: 'box_25',
        ),
        RewardRedemption(
          spent: 5,
          at: DateTime(2026, 11, 8),
          rewardCode: 'box_5',
        ),
      ]);
      expect(last['box_25'], DateTime(2026, 11, 10));
      expect(last['box_5'], DateTime(2026, 11, 8));
    });
  });

  group('RewardsCubit', () {
    blocTest<RewardsCubit, RewardsState>(
      'carga cajas, historial y movimientos',
      build: () => RewardsCubit(FakeRewards(), refreshBalance: () async {}),
      act: (c) => c.load(),
      verify: (c) {
        expect(c.state.status, RewardsStatus.ready);
        expect(c.state.boxes.map((b) => b.code), ['box_5', 'box_25']);
        expect(c.state.ledger.single.amount, 450);
      },
    );

    blocTest<RewardsCubit, RewardsState>(
      'si la base falla queda en error',
      build: () =>
          RewardsCubit(FakeRewards(fail: true), refreshBalance: () async {}),
      act: (c) => c.load(),
      verify: (c) => expect(c.state.status, RewardsStatus.error),
    );

    test(
      'canjear refresca el saldo, guarda el premio y bloquea la caja',
      () async {
        final repo = FakeRewards();
        var refreshed = 0;
        final c = RewardsCubit(
          repo,
          refreshBalance: () async => refreshed++,
          now: () => _now,
        );
        await c.load();
        expect(c.availableAt(_box25), isNull);

        final pending = c.redeem(_box25);
        expect(c.state.busy, isTrue);
        await c.redeem(_box25);
        await pending;

        expect(repo.redeemed, ['box_25']);
        expect(refreshed, 1);
        expect(c.state.busy, isFalse);
        expect(c.state.redeemCount, 1);
        expect(c.state.lastOutcome!.prizeLabel, r'$2.000 de descuento');
        expect(c.availableAt(_box25), _now.add(const Duration(hours: 12)));
        await c.close();
      },
    );
  });
}
