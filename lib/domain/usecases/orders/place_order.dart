import 'dart:async';

import '../../../core/constants/catalog_constants.dart';
import '../../catalog_rules.dart';
import '../../entities/order.dart';
import '../../order_rules.dart';
import '../../ports/order_ports.dart';
import '../../repositories/order_repository.dart';
import 'checkout.dart';
import 'checkout_draft.dart';

/// Confirma un pedido: valida, calcula, lo crea en el repositorio y aplica los
/// efectos locales (Gotas, cupón, ventas, avisos).
///
/// Con servidor, `place_order` recalcula todo y rechaza si el comprador vio un
/// total distinto; en ese caso no se crea nada y [OrderResult.code] explica por
/// qué.
class PlaceOrder {
  PlaceOrder(
    this._repo,
    this._catalog,
    this._wallet,
    this._notifier,
    this._preview,
    this._validate,
  );

  final OrderRepository _repo;
  final OrderCatalogPort _catalog;
  final OrderWalletPort _wallet;
  final OrderNotifier _notifier;
  final PreviewCheckout _preview;
  final ValidateCheckout _validate;

  /// [clientKey] hace el reintento seguro tras un corte de red.
  Future<OrderResult> call(CheckoutDraft d, {String? clientKey}) async {
    final errors = _validate(d);
    if (errors.isNotEmpty) return OrderResult.validation(errors.first);

    final buyer = d.buyer!;
    final r = d.restaurant!;
    final address = d.address!;
    final point = pointById(address.pointId);
    final km = distanceTo(r, point);
    final lines = _preview.lines(d);
    final totals = _preview(d);

    final result = await _repo.place(
      PlaceOrderRequest(
        buyer: buyer,
        restaurant: r,
        address: address,
        payment: d.payment,
        lines: lines,
        totals: totals,
        pointId: point.id,
        distanceKm: double.parse(km.toStringAsFixed(2)),
        etaMin: etaMinutes(r, point, prepMin: _maxPrep(lines, r.prepMin)),
        courierPay: courierPayFor(km),
        clientKey: clientKey ?? newClientKey(),
        scheduledFor: d.scheduledFor,
        restaurantNote: d.restaurantNote.trim(),
        couponId: d.coupon?.id,
      ),
    );
    final order = result.order;
    if (!result.ok || order == null) return result;

    _applyEffects(order, d, totals.gotasUsed);
    return result;
  }

  void _applyEffects(Order order, CheckoutDraft d, int gotasUsed) {
    final buyer = d.buyer!;
    if (_repo.isRemote) {
      // El servidor ya descontó las Gotas y marcó el cupón: solo se relee.
      unawaited(_wallet.syncBalance());
    } else if (gotasUsed > 0) {
      _wallet.spendGotas(buyer.id, gotasUsed, 'Usadas en ${order.id}');
    }
    if (d.coupon != null) _wallet.setCouponUsed(buyer.id, d.coupon!.id, true);
    for (final l in order.lines) {
      _catalog.recordSale(l.dishId, l.qty);
    }
    _notifier.placed(order, businessId: d.restaurant!.businessId);
  }

  int _maxPrep(List<OrderLine> lines, int fallback) {
    var m = 0;
    for (final l in lines) {
      final dish = _catalog.dishById(l.dishId);
      if (dish != null && dish.prepMin > m) m = dish.prepMin;
    }
    return m == 0 ? fallback : m;
  }
}
