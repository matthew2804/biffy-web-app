import 'package:flutter/foundation.dart';

import '../../data/models/cart.dart';
import '../../data/models/catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/pricing.dart';

enum AddResult { added, differentRestaurant, unavailable }

/// Carrito de un solo restaurante; persiste durante la navegación interna.
class CartController extends ChangeNotifier {
  CartController(this._catalog);

  final CatalogRepository _catalog;
  final List<CartItem> _items = [];
  int _seq = 0;

  String restaurantNote = '';
  TipOption tip = TipOption.none;
  bool useGotas = false;
  String? couponId;
  PaymentMethod? payment;
  DateTime? scheduledFor;
  String? addressId;

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get count => _items.fold(0, (s, i) => s + i.qty);

  String? get restaurantId {
    if (_items.isEmpty) return null;
    return _catalog.dishById(_items.first.dishId)?.restaurantId;
  }

  Restaurant? get restaurant {
    final id = restaurantId;
    return id == null ? null : _catalog.restaurantById(id);
  }

  String newLineId() => 'line-${++_seq}';

  List<PricedLine> get pricedLines => [
    for (final i in _items)
      if (_catalog.dishById(i.dishId) case final d?) PricedLine(d, i),
  ];

  int get subtotal => pricedLines.fold(0, (s, l) => s + l.total);

  CartItem? lineById(String id) {
    for (final i in _items) {
      if (i.lineId == id) return i;
    }
    return null;
  }

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
    for (final i in _items) {
      if (i.dishId == dish.id && i.selection == sel && i.note == note) {
        i.qty += qty;
        notifyListeners();
        return AddResult.added;
      }
    }
    _items.add(
      CartItem(
        lineId: newLineId(),
        dishId: dish.id,
        qty: qty,
        selection: sel,
        note: note,
      ),
    );
    notifyListeners();
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
    clear(notify: false);
    _items.addAll(items);
    notifyListeners();
  }

  /// Guarda la edición de una línea. Hasta llamar a este método, la línea
  /// original permanece intacta.
  void updateLine(
    String lineId, {
    required DishSelection selection,
    required int qty,
    required String note,
  }) {
    final line = lineById(lineId);
    if (line == null) return;
    line
      ..selection = selection
      ..qty = qty
      ..note = note;
    notifyListeners();
  }

  void setQty(String lineId, int qty) {
    if (qty <= 0) {
      remove(lineId);
      return;
    }
    lineById(lineId)?.qty = qty;
    notifyListeners();
  }

  void remove(String lineId) {
    _items.removeWhere((i) => i.lineId == lineId);
    if (_items.isEmpty) _resetOptions();
    notifyListeners();
  }

  void _resetOptions() {
    restaurantNote = '';
    tip = TipOption.none;
    useGotas = false;
    couponId = null;
    scheduledFor = null;
  }

  void clear({bool notify = true}) {
    _items.clear();
    _resetOptions();
    if (notify) notifyListeners();
  }

  void setNote(String note) {
    restaurantNote = note;
    notifyListeners();
  }

  void setTip(TipOption t) {
    tip = t;
    notifyListeners();
  }

  void setUseGotas(bool v) {
    useGotas = v;
    notifyListeners();
  }

  void setCoupon(String? id) {
    couponId = id;
    notifyListeners();
  }

  void setPayment(PaymentMethod m) {
    payment = m;
    notifyListeners();
  }

  void setSchedule(DateTime? when) {
    scheduledFor = when;
    notifyListeners();
  }

  void setAddress(String? id) {
    addressId = id;
    notifyListeners();
  }
}
