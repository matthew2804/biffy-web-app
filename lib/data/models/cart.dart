/// Personalización de un plato y líneas del carrito.
library;

class DishSelection {
  const DishSelection({
    this.sizeId,
    this.sideId,
    this.extraIds = const {},
    this.removed = const {},
  });

  final String? sizeId;
  final String? sideId;
  final Set<String> extraIds;

  /// Ingredientes que el comprador pidió quitar.
  final Set<String> removed;

  DishSelection copyWith({
    String? sizeId,
    String? sideId,
    bool clearSide = false,
    Set<String>? extraIds,
    Set<String>? removed,
  }) {
    return DishSelection(
      sizeId: sizeId ?? this.sizeId,
      sideId: clearSide ? null : (sideId ?? this.sideId),
      extraIds: extraIds ?? this.extraIds,
      removed: removed ?? this.removed,
    );
  }

  /// Clave estable para agrupar líneas iguales.
  String get signature {
    final e = extraIds.toList()..sort();
    final r = removed.toList()..sort();
    return '${sizeId ?? ''}|${sideId ?? ''}|${e.join(',')}|${r.join(',')}';
  }

  @override
  bool operator ==(Object other) =>
      other is DishSelection && other.signature == signature;

  @override
  int get hashCode => signature.hashCode;
}

class CartItem {
  CartItem({
    required this.lineId,
    required this.dishId,
    required this.qty,
    this.selection = const DishSelection(),
    this.note = '',
  });

  final String lineId;
  final String dishId;
  int qty;
  DishSelection selection;
  String note;

  CartItem copy() => CartItem(
    lineId: lineId,
    dishId: dishId,
    qty: qty,
    selection: selection,
    note: note,
  );
}

/// Propina como porcentaje del subtotal.
enum TipOption {
  none(0, 'Sin propina'),
  five(5, '5%'),
  ten(10, '10%'),
  fifteen(15, '15%');

  const TipOption(this.percent, this.label);
  final int percent;
  final String label;
}
