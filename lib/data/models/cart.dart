/// Personalización de un plato y líneas del carrito.
library;

/// Personalización elegida para un plato (tamaño, acompañante, extras).
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

  /// Copia la selección aplicando los cambios indicados.
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

  /// Dos selecciones son iguales si tienen la misma firma.
  @override
  bool operator ==(Object other) =>
      other is DishSelection && other.signature == signature;

  /// Hash coherente con la firma de la selección.
  @override
  int get hashCode => signature.hashCode;
}

/// Línea del carrito: plato, cantidad, personalización y nota.
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

  /// Copia la línea conservando todos sus datos.
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
