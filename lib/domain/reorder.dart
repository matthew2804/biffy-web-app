import '../core/utils/format.dart';
import '../data/models/cart.dart';
import '../data/models/catalog.dart';
import '../data/models/order.dart';
import 'pricing.dart';

/// Resultado de comprobar si un pedido anterior puede repetirse.
class ReorderCheck {
  const ReorderCheck({
    required this.items,
    required this.warnings,
    required this.restaurant,
  });

  final List<CartItem> items;
  final List<String> warnings;
  final Restaurant? restaurant;

  /// Indica si el pedido anterior se puede repetir tal cual.
  bool get canReorder => items.isNotEmpty && restaurant != null;
}

/// Verifica disponibilidad, precios actuales y personalizaciones vigentes.
ReorderCheck checkReorder(
  Order order, {
  required Dish? Function(String) dishOf,
  required Restaurant? restaurant,
  required bool reachable,
  required String Function() newLineId,
}) {
  final warnings = <String>[];
  if (restaurant == null) {
    return const ReorderCheck(
      items: [],
      warnings: ['El restaurante ya no está disponible.'],
      restaurant: null,
    );
  }
  if (!reachable) {
    warnings.add(
      '${restaurant.name} no entrega en tu punto actual. Cambia la ubicación para pedir.',
    );
  }
  final items = <CartItem>[];
  for (final line in order.lines) {
    final dish = dishOf(line.dishId);
    if (dish == null || !dish.active) {
      warnings.add('${line.name} ya no está en el menú.');
      continue;
    }
    if (!dish.orderable) {
      warnings.add('${line.name} está agotado.');
      continue;
    }
    var selection = line.selection;
    if (!selectionStillValid(dish, selection)) {
      selection = defaultSelection(dish);
      warnings.add(
        'Algunas opciones de ${dish.name} cambiaron; revisa la personalización.',
      );
    }
    final now = unitPrice(dish, selection);
    if (now != line.unitPrice) {
      warnings.add(
        '${dish.name} cambió de precio (antes ${cop(line.unitPrice)}, ahora ${cop(now)}).',
      );
    }
    items.add(
      CartItem(
        lineId: newLineId(),
        dishId: dish.id,
        qty: line.qty,
        selection: selection,
        note: line.note,
      ),
    );
  }
  return ReorderCheck(
    items: reachable ? items : const [],
    warnings: warnings,
    restaurant: restaurant,
  );
}
