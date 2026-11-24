import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/clock.dart';
import '../../catalog_rules.dart';
import '../../entities/order.dart';
import '../../ports/order_ports.dart';
import '../../pricing.dart';
import '../../repositories/order_repository.dart';
import '../../scheduling.dart';
import 'checkout_draft.dart';

/// Totales del carrito para mostrar antes de confirmar.
class PreviewCheckout {
  PreviewCheckout(this._catalog, this._buyers);

  final OrderCatalogPort _catalog;
  final OrderBuyerPort _buyers;

  CartTotals call(CheckoutDraft d) {
    final lines = [
      for (final i in d.items)
        if (_catalog.dishById(i.dishId) case final dish?) PricedLine(dish, i),
    ];
    final point = d.address == null
        ? _buyers.currentPoint
        : pointById(d.address!.pointId);
    return computeTotals(
      lines: lines,
      restaurant: d.restaurant,
      point: point,
      verifiedUniversityId: d.buyer == null
          ? null
          : _buyers.verifiedUniversityId(d.buyer!.id),
      gotasBalance: d.buyer == null ? 0 : _buyers.gotasOf(d.buyer!.id),
      useGotas: d.useGotas,
      coupon: d.coupon,
      tip: d.tip,
    );
  }

  /// Líneas del pedido con el precio unitario de cada plato.
  List<OrderLine> lines(CheckoutDraft d) {
    final result = <OrderLine>[];
    for (final i in d.items) {
      final dish = _catalog.dishById(i.dishId);
      if (dish == null) continue;
      result.add(
        OrderLine(
          dishId: dish.id,
          name: dish.name,
          emoji: dish.emoji,
          qty: i.qty,
          unitPrice: unitPrice(dish, i.selection),
          selection: i.selection,
          detail: selectionDetail(dish, i.selection),
          note: i.note,
        ),
      );
    }
    return result;
  }
}

/// Errores de validación en español; lista vacía si el pedido es válido.
class ValidateCheckout {
  ValidateCheckout(this._repo, this._catalog, this._clock);

  final OrderRepository _repo;
  final OrderCatalogPort _catalog;
  final Clock _clock;

  List<String> call(CheckoutDraft d) {
    final errors = <String>[];
    final now = _clock.now();
    if (d.buyer == null) errors.add('Inicia sesión para confirmar el pedido.');
    final r = d.restaurant;
    if (r == null || d.items.isEmpty) {
      errors.add('Tu carrito está vacío.');
      return errors;
    }
    if (d.address == null) {
      errors.add('Selecciona una dirección de entrega.');
    } else if (!isReachable(r, pointById(d.address!.pointId))) {
      errors.add('${r.name} no entrega en la zona de esa dirección.');
    }
    for (final i in d.items) {
      final dish = _catalog.dishById(i.dishId);
      if (dish == null || !dish.orderable) {
        errors.add('${dish?.name ?? 'Un producto'} ya no está disponible.');
      } else if (dish.remainingPortions != null &&
          dish.remainingPortions! < i.qty) {
        errors.add(
          'Solo quedan ${dish.remainingPortions} porciones de ${dish.name}.',
        );
      }
    }
    if (d.scheduledFor == null) {
      if (!isOpenAt(r, now)) {
        errors.add('${r.name} está cerrado ahora. Programa tu pedido.');
      }
    } else if (!isValidSchedule(r, d.scheduledFor!, now)) {
      errors.add('La fecha y hora programadas ya no son válidas.');
    }
    if (d.coupon != null && d.coupon!.used) {
      errors.add('El cupón ya fue usado.');
    }
    if (_repo.isRemote) {
      // Direcciones y cupones se sincronizan con la cuenta en la HU de datos
      // personales: mientras tanto solo valen los que ya existen en el
      // servidor (identificados con uuid).
      final address = d.address;
      if (address != null && !isUuid(address.serverId)) {
        errors.add(
          'Esa dirección aún no está guardada en tu cuenta. '
          'Elige una de tus direcciones guardadas.',
        );
      }
      final coupon = d.coupon;
      if (coupon != null && !isUuid(coupon.id)) {
        errors.add(
          'Los cupones locales todavía no se pueden usar con pedidos reales. '
          'Quita el cupón para continuar.',
        );
      }
    }
    return errors;
  }
}
