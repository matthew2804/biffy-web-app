import 'dart:async';
import 'dart:typed_data';

import '../../entities/order.dart';
import '../../entities/user.dart';
import '../../order_rules.dart';
import '../../ports/order_ports.dart';
import '../../repositories/order_repository.dart';

/// Base de los casos de uso de transición: comparten repositorio y puertos.
abstract class _OrderCommand {
  _OrderCommand(this.repo, this.catalog, this.wallet, this.notifier);

  final OrderRepository repo;
  final OrderCatalogPort catalog;
  final OrderWalletPort wallet;
  final OrderNotifier notifier;

  String? businessOf(Order o) => catalog.restaurantById(o.restaurantId)?.businessId;

  /// Con servidor las Gotas y el cupón los devuelve la base de datos; en demo
  /// se devuelven aquí.
  void refund(Order o) {
    if (repo.isRemote) {
      unawaited(wallet.syncBalance());
      return;
    }
    if (o.gotasUsed > 0) {
      wallet.creditGotas(o.buyerId, o.gotasUsed, 'Reembolso de ${o.id}');
    }
    if (o.couponId != null) {
      wallet.setCouponUsed(o.buyerId, o.couponId!, false);
    }
  }
}

// ---------------------------------------------------------------- Comprador

/// El comprador cancela antes de que el restaurante acepte.
class CancelOrder extends _OrderCommand {
  CancelOrder(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(String orderId) async {
    final res = await repo.cancelByBuyer(orderId);
    final o = repo.byId(orderId);
    if (res.ok && o != null) {
      refund(o);
      notifier.buyerCancelled(o, businessId: businessOf(o));
    }
    return res;
  }
}

// -------------------------------------------------------------- Restaurante

class AcceptOrder extends _OrderCommand {
  AcceptOrder(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(String orderId) async {
    final res = await repo.accept(orderId);
    final o = repo.byId(orderId);
    if (res.ok && o != null) notifier.accepted(o);
    return res;
  }
}

class RejectOrder extends _OrderCommand {
  RejectOrder(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(String orderId, String reason) async {
    if (reason.trim().isEmpty) {
      return OrderResult.validation('Indica el motivo del rechazo.');
    }
    final res = await repo.reject(orderId, reason.trim());
    final o = repo.byId(orderId);
    if (res.ok && o != null) {
      refund(o);
      notifier.rejected(o);
    }
    return res;
  }
}

class MarkOrderReady extends _OrderCommand {
  MarkOrderReady(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(String orderId) async {
    final res = await repo.markReady(orderId);
    final o = repo.byId(orderId);
    if (res.ok && o != null) notifier.ready(o);
    return res;
  }
}

// --------------------------------------------------------------- Repartidor

/// Asignación atómica: si otro repartidor ya lo tomó, falla con
/// `already_assigned`.
class AcceptOffer extends _OrderCommand {
  AcceptOffer(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(
    String orderId,
    AppUser courier, {
    Vehicle? vehicle,
  }) async {
    final res = await repo.acceptOffer(orderId, courier, vehicle: vehicle);
    final o = repo.byId(orderId);
    if (res.ok && o != null) {
      notifier.assigned(o, courier, businessId: businessOf(o));
    }
    return res;
  }
}

class DeclineOffer extends _OrderCommand {
  DeclineOffer(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(String orderId, String courierId) =>
      repo.declineOffer(orderId, courierId);
}

/// Requiere los tres checks de recogida.
class ConfirmPickup extends _OrderCommand {
  ConfirmPickup(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(
    String orderId,
    String courierId, {
    required bool codeValidated,
    required bool bagSealed,
    required bool productsVerified,
  }) async {
    if (!(codeValidated && bagSealed && productsVerified)) {
      return OrderResult.validation(
        'Marca los tres puntos para confirmar la recogida',
      );
    }
    final res = await repo.confirmPickup(orderId, courierId);
    final o = repo.byId(orderId);
    if (res.ok && o != null) notifier.pickedUp(o);
    return res;
  }
}

/// Entrega con código del cliente y foto de evidencia.
///
/// Con servidor, el código lo valida `courier_deliver` (el repartidor nunca lo
/// ve) y la foto debe existir en Storage; las Gotas las acredita la base de
/// datos.
class CompleteDelivery extends _OrderCommand {
  CompleteDelivery(super.repo, super.catalog, super.wallet, super.notifier);

  Future<OrderResult> call(
    String orderId,
    String courierId,
    String code,
    String? evidence, {
    Uint8List? evidenceBytes,
  }) async {
    final before = repo.byId(orderId);
    if (before == null ||
        before.courierId != courierId ||
        before.status != OrderStatus.onTheWay) {
      return const OrderResult('invalid_state');
    }
    if (repo.isRemote) {
      final hasPhoto =
          (evidenceBytes != null && evidenceBytes.isNotEmpty) ||
          validateEvidence(evidence);
      if (!hasPhoto) return const OrderResult('missing_evidence');
    }

    final res = await repo.deliver(
      orderId,
      courierId,
      code,
      evidence,
      evidenceBytes,
    );
    final o = repo.byId(orderId);
    if (res.ok && o != null) {
      if (!repo.isRemote) {
        wallet.creditGotas(
          o.buyerId,
          o.subtotal ~/ 1000,
          'Pedido ${o.id} entregado',
        );
      }
      notifier.delivered(o, businessId: businessOf(o));
    }
    return res;
  }
}
