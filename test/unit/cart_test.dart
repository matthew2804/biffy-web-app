import 'package:biffy/data/models/cart.dart';
import 'package:biffy/shared/state/app_services.dart';
import 'package:biffy/shared/state/cart_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';

void main() {
  late AppServices s;
  late CartController cart;
  setUp(() {
    s = makeServices();
    cart = s.cart;
  });

  test('agregar y quitar productos', () {
    final d = s.catalog.dishById('qbano-pollo')!;
    expect(cart.add(d), AddResult.added);
    expect(cart.count, 1);
    cart.remove(cart.items.first.lineId);
    expect(cart.isEmpty, isTrue);
  });

  test('misma personalización se agrupa; distinta crea otra línea', () {
    final d = s.catalog.dishById('qbano-especial')!;
    cart.add(d);
    cart.add(d);
    expect(cart.items, hasLength(1));
    expect(cart.items.first.qty, 2);
    cart.add(
      d,
      selection: const DishSelection(sizeId: 'qe-30', extraIds: {'qe-queso'}),
    );
    expect(cart.items, hasLength(2));
  });

  test('modificar cantidades y eliminar con cantidad 0', () {
    final d = s.catalog.dishById('qbano-pollo')!;
    cart.add(d);
    final id = cart.items.first.lineId;
    cart.setQty(id, 4);
    expect(cart.count, 4);
    expect(cart.subtotal, 21900 * 4);
    cart.setQty(id, 0);
    expect(cart.isEmpty, isTrue);
  });

  test('no mezcla restaurantes', () {
    cart.add(s.catalog.dishById('qbano-pollo')!);
    expect(
      cart.add(s.catalog.dishById('capuchino')!),
      AddResult.differentRestaurant,
    );
    cart.replaceWith(s.catalog.dishById('capuchino')!);
    expect(cart.restaurantId, 'cafe-enjambre');
    expect(cart.items, hasLength(1));
  });

  test('editar una línea conserva el producto hasta guardar', () {
    final d = s.catalog.dishById('qbano-especial')!;
    cart.add(d);
    final line = cart.items.first;
    expect(cart.lineById(line.lineId)!.selection.extraIds, isEmpty);
    cart.updateLine(
      line.lineId,
      selection: const DishSelection(sizeId: 'qe-30', extraIds: {'qe-queso'}),
      qty: 2,
      note: 'x',
    );
    expect(cart.items.first.qty, 2);
    expect(cart.subtotal, (24900 + 3000) * 2);
  });

  test('producto agotado no se agrega', () {
    final d = s.catalog.dishById('capuchino')!..soldOut = true;
    expect(cart.add(d), AddResult.unavailable);
  });

  test('vaciar reinicia opciones', () {
    cart.add(s.catalog.dishById('qbano-pollo')!);
    cart.setTip(TipOption.ten);
    cart.clear();
    expect(cart.tip, TipOption.none);
    expect(cart.isEmpty, isTrue);
  });
}
