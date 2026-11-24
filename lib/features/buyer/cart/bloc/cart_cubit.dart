import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../data/models/catalog.dart';
import '../../../../data/repositories/catalog_repository.dart';
import '../../../../domain/entities/cart.dart';
import '../../../../domain/pricing.dart';

/// Resultado de intentar agregar un plato al carrito.
enum AddResult { added, differentRestaurant, unavailable }

/// Estado inmutable del carrito y sus opciones de checkout.
class CartState {
  /// Crea el carrito vacío con las opciones por defecto.
  const CartState({
    this.items = const [],
    this.restaurant,
    this.pricedLines = const [],
    this.subtotal = 0,
    this.count = 0,
    this.note = '',
    this.tip = TipOption.none,
    this.useGotas = false,
    this.couponId,
    this.payment,
    this.scheduledFor,
    this.addressId,
    this.cashTendered,
  });

  /// Líneas del carrito (solo lectura).
  final List<CartItem> items;

  /// Restaurante del carrito, si ya tiene platos.
  final Restaurant? restaurant;

  /// Líneas con el plato y el precio ya calculado.
  final List<PricedLine> pricedLines;

  /// Suma de las líneas antes de propina y envío.
  final int subtotal;

  /// Total de unidades en el carrito.
  final int count;

  /// Nota para el restaurante.
  final String note;

  /// Propina elegida.
  final TipOption tip;

  /// `true` si se pagará con Gotas.
  final bool useGotas;

  /// Cupón elegido.
  final String? couponId;

  /// Medio de pago elegido.
  final PaymentMethod? payment;

  /// Fecha programada de entrega.
  final DateTime? scheduledFor;

  /// Dirección de entrega elegida.
  final String? addressId;

  /// Billete con el que pagará en efectivo (`null` = pago exacto).
  final int? cashTendered;

  /// `true` si no hay líneas.
  bool get isEmpty => items.isEmpty;

  /// Restaurante del carrito, si existe.
  String? get restaurantId => restaurant?.id;

  /// Busca una línea por id.
  CartItem? lineById(String id) {
    for (final i in items) {
      if (i.lineId == id) return i;
    }
    return null;
  }
}

/// Cubit del carrito compartido: agrega, edita y guarda opciones de checkout.
///
/// Es un Cubit porque todas sus operaciones son síncronas y la UI necesita el
/// resultado en el mismo toque; el estado sigue siendo inmutable.
class CartCubit extends Cubit<CartState> {
  /// Crea el carrito sobre el catálogo indicado.
  CartCubit(this._catalog) : super(const CartState());

  final CatalogRepository _catalog;
  int _seq = 0;
  static const _unset = Object();

  /// Líneas del carrito.
  List<CartItem> get items => state.items;

  /// `true` si no hay líneas.
  bool get isEmpty => state.isEmpty;

  /// Total de unidades.
  int get count => state.count;

  /// Restaurante del carrito.
  Restaurant? get restaurant => state.restaurant;

  /// Id del restaurante del carrito.
  String? get restaurantId => state.restaurantId;

  /// Líneas con precio calculado.
  List<PricedLine> get pricedLines => state.pricedLines;

  /// Subtotal antes de propina y envío.
  int get subtotal => state.subtotal;

  /// Nota para el restaurante.
  String get restaurantNote => state.note;

  /// Propina elegida.
  TipOption get tip => state.tip;

  /// `true` si se paga con Gotas.
  bool get useGotas => state.useGotas;

  /// Cupón elegido.
  String? get couponId => state.couponId;

  /// Medio de pago elegido.
  PaymentMethod? get payment => state.payment;

  /// Fecha programada.
  DateTime? get scheduledFor => state.scheduledFor;

  /// Dirección elegida.
  String? get addressId => state.addressId;

  /// Billete con el que paga en efectivo.
  int? get cashTendered => state.cashTendered;

  /// Genera un id único para una línea nueva.
  String newLineId() => 'line-${++_seq}';

  /// Busca una línea por id.
  CartItem? lineById(String id) => state.lineById(id);

  /// Agrega un plato o suma cantidad a una línea igual.
  AddResult add(
    Dish dish, {
    DishSelection? selection,
    int qty = 1,
    String note = '',
  }) {
    if (!dish.orderable) return AddResult.unavailable;
    final rid = restaurantId;
    if (rid != null && rid != dish.restaurantId) {
      return AddResult.differentRestaurant;
    }
    final sel = selection ?? defaultSelection(dish);
    final current = List<CartItem>.of(state.items);
    for (var i = 0; i < current.length; i++) {
      final line = current[i];
      if (line.dishId == dish.id &&
          line.selection == sel &&
          line.note == note) {
        current[i] = _copy(line, qty: line.qty + qty);
        _commit(current);
        return AddResult.added;
      }
    }
    current.add(
      CartItem(
        lineId: newLineId(),
        dishId: dish.id,
        qty: qty,
        selection: sel,
        note: note,
      ),
    );
    _commit(current);
    return AddResult.added;
  }

  /// Vacía el carrito y agrega el plato de otro restaurante.
  void replaceWith(
    Dish dish, {
    DishSelection? selection,
    int qty = 1,
    String note = '',
  }) {
    clear();
    add(dish, selection: selection, qty: qty, note: note);
  }

  /// Sustituye todo el carrito (repetir pedido).
  void loadItems(List<CartItem> items) {
    _commit(
      List<CartItem>.of(items),
      note: '',
      tip: TipOption.none,
      useGotas: false,
      couponId: null,
      scheduledFor: null,
      cashTendered: null,
    );
  }

  /// Guarda la edición de una línea.
  void updateLine(
    String lineId, {
    required DishSelection selection,
    required int qty,
    required String note,
  }) {
    final current = List<CartItem>.of(state.items);
    for (var i = 0; i < current.length; i++) {
      if (current[i].lineId == lineId) {
        current[i] = _copy(
          current[i],
          selection: selection,
          qty: qty,
          note: note,
        );
        _commit(current);
        return;
      }
    }
  }

  /// Cambia la cantidad; en cero elimina la línea.
  void setQty(String lineId, int qty) {
    if (qty <= 0) {
      remove(lineId);
      return;
    }
    final current = List<CartItem>.of(state.items);
    for (var i = 0; i < current.length; i++) {
      if (current[i].lineId == lineId) {
        current[i] = _copy(current[i], qty: qty);
        _commit(current);
        return;
      }
    }
  }

  /// Quita una línea del carrito.
  void remove(String lineId) {
    final current = List<CartItem>.of(state.items)
      ..removeWhere((i) => i.lineId == lineId);
    if (current.isEmpty) {
      _commit(
        current,
        note: '',
        tip: TipOption.none,
        useGotas: false,
        couponId: null,
        scheduledFor: null,
        cashTendered: null,
      );
      return;
    }
    _commit(current);
  }

  /// Vacía el carrito y reinicia nota, propina, Gotas, cupón, horario y billete.
  void clear() => _commit(
    const [],
    note: '',
    tip: TipOption.none,
    useGotas: false,
    couponId: null,
    scheduledFor: null,
    cashTendered: null,
  );

  /// Guarda la nota para el restaurante.
  void setNote(String note) => _commit(state.items, note: note);

  /// Cambia la propina elegida.
  void setTip(TipOption t) => _commit(state.items, tip: t);

  /// Activa o desactiva el pago con Gotas.
  void setUseGotas(bool v) => _commit(state.items, useGotas: v);

  /// Aplica o quita un cupón.
  void setCoupon(String? id) => _commit(state.items, couponId: id);

  /// Elige el medio de pago del pedido.
  void setPayment(PaymentMethod m) => _commit(state.items, payment: m);

  /// Programa la entrega para una fecha.
  void setSchedule(DateTime? when) => _commit(state.items, scheduledFor: when);

  /// Elige la dirección de entrega.
  void setAddress(String? id) => _commit(state.items, addressId: id);

  /// Guarda el billete con el que se paga en efectivo.
  void setCashTendered(int? value) =>
      _commit(state.items, cashTendered: value);

  /// Copia una línea cambiando solo lo indicado.
  CartItem _copy(
    CartItem item, {
    int? qty,
    DishSelection? selection,
    String? note,
  }) => CartItem(
    lineId: item.lineId,
    dishId: item.dishId,
    qty: qty ?? item.qty,
    selection: selection ?? item.selection,
    note: note ?? item.note,
  );

  /// Recalcula el estado y lo publica.
  void _commit(
    List<CartItem> items, {
    String? note,
    TipOption? tip,
    bool? useGotas,
    Object? couponId = _unset,
    PaymentMethod? payment,
    Object? scheduledFor = _unset,
    Object? addressId = _unset,
    Object? cashTendered = _unset,
  }) {
    final fixed = List<CartItem>.unmodifiable(items);
    Restaurant? restaurant;
    if (fixed.isNotEmpty) {
      final dish = _catalog.dishById(fixed.first.dishId);
      restaurant = dish == null
          ? null
          : _catalog.restaurantById(dish.restaurantId);
    }
    final priced = <PricedLine>[
      for (final i in fixed)
        if (_catalog.dishById(i.dishId) case final d?) PricedLine(d, i),
    ];
    emit(
      CartState(
        items: fixed,
        restaurant: restaurant,
        pricedLines: List.unmodifiable(priced),
        subtotal: priced.fold(0, (s, l) => s + l.total),
        count: fixed.fold(0, (s, i) => s + i.qty),
        note: note ?? state.note,
        tip: tip ?? state.tip,
        useGotas: useGotas ?? state.useGotas,
        couponId: identical(couponId, _unset)
            ? state.couponId
            : couponId as String?,
        payment: payment ?? state.payment,
        scheduledFor: identical(scheduledFor, _unset)
            ? state.scheduledFor
            : scheduledFor as DateTime?,
        addressId: identical(addressId, _unset)
            ? state.addressId
            : addressId as String?,
        cashTendered: identical(cashTendered, _unset)
            ? state.cashTendered
            : cashTendered as int?,
      ),
    );
  }
}
