import 'package:flutter/foundation.dart';

import '../../data/models/cart.dart';
import '../../data/models/catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../domain/pricing.dart';

/// Resultado de intentar agregar un plato al carrito.
enum AddResult { added, differentRestaurant, unavailable }

/// Carrito de un solo restaurante; persiste durante la navegación interna.
class CartController extends ChangeNotifier {
  /// Crea el carrito sobre el catálogo indicado.
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

  /// Líneas del carrito (solo lectura).
  List<CartItem> get items => List.unmodifiable(_items);
  /// `true` si no hay líneas.
  bool get isEmpty => _items.isEmpty;
  /// Total de unidades en el carrito.
  int get count => _items.fold(0, (s, i) => s + i.qty);

  /// Restaurante del carrito, si ya tiene platos.
  String? get restaurantId {
    if (_items.isEmpty) return null;
    return _catalog.dishById(_items.first.dishId)?.restaurantId;
  }

  /// Restaurante del carrito con sus datos.
  Restaurant? get restaurant {
    final id = restaurantId;
    return id == null ? null : _catalog.restaurantById(id);
  }

  /// Genera un id único para una línea nueva.
  String newLineId() => 'line-${++_seq}';

  /// Líneas con su plato y precio calculado.
  List<PricedLine> get pricedLines => [
    for (final i in _items)
      if (_catalog.dishById(i.dishId) case final d?) PricedLine(d, i),
  ];

  /// Suma de las líneas antes de propina y envío.
  int get subtotal => pricedLines.fold(0, (s, l) => s + l.total);

  /// Busca una línea por id.
  CartItem? lineById(String id) {
    for (final i in _items) {
      if (i.lineId == id) return i;
    }
    return null;
  }

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

  /// Cambia la cantidad; en cero elimina la línea.
  void setQty(String lineId, int qty) {
    if (qty <= 0) {
      remove(lineId);
      return;
    }
    lineById(lineId)?.qty = qty;
    notifyListeners();
  }

  /// Quita una línea del carrito.
  void remove(String lineId) {
    _items.removeWhere((i) => i.lineId == lineId);
    if (_items.isEmpty) _resetOptions();
    notifyListeners();
  }

  /// Limpia propina, Gotas, cupón y programación.
  void _resetOptions() {
    restaurantNote = '';
    tip = TipOption.none;
    useGotas = false;
    couponId = null;
    scheduledFor = null;
  }

  /// Vacía el carrito y reinicia sus opciones.
  void clear({bool notify = true}) {
    _items.clear();
    _resetOptions();
    if (notify) notifyListeners();
  }

  /// Guarda la nota para el restaurante.
  void setNote(String note) {
    restaurantNote = note;
    notifyListeners();
  }

  /// Cambia la propina elegida.
  void setTip(TipOption t) {
    tip = t;
    notifyListeners();
  }

  /// Activa o desactiva el pago con Gotas.
  void setUseGotas(bool v) {
    useGotas = v;
    notifyListeners();
  }

  /// Aplica o quita un cupón.
  void setCoupon(String? id) {
    couponId = id;
    notifyListeners();
  }

  /// Elige el medio de pago del pedido.
  void setPayment(PaymentMethod m) {
    payment = m;
    notifyListeners();
  }

  /// Programa la entrega para una fecha.
  void setSchedule(DateTime? when) {
    scheduledFor = when;
    notifyListeners();
  }

  /// Elige la dirección de entrega.
  void setAddress(String? id) {
    addressId = id;
    notifyListeners();
  }
}
