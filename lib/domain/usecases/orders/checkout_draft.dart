import 'dart:math' as math;

export '../../../core/utils/ids.dart' show isUuid;

import '../../entities/address.dart';
import '../../entities/cart.dart';
import '../../entities/catalog.dart';
import '../../entities/user.dart';

/// Datos necesarios para crear un pedido (desde el carrito o «Pedir ya»).
class CheckoutDraft {
  const CheckoutDraft({
    required this.buyer,
    required this.restaurant,
    required this.items,
    required this.address,
    required this.payment,
    this.scheduledFor,
    this.tip = TipOption.none,
    this.useGotas = false,
    this.coupon,
    this.restaurantNote = '',
  });

  final AppUser? buyer;
  final Restaurant? restaurant;
  final List<CartItem> items;
  final Address? address;
  final PaymentMethod payment;
  final DateTime? scheduledFor;
  final TipOption tip;
  final bool useGotas;
  final Coupon? coupon;
  final String restaurantNote;
}

/// Clave de idempotencia para crear un pedido: un reintento con la misma clave
/// devuelve el pedido ya creado en vez de duplicarlo.
String newClientKey() {
  final r = math.Random.secure();
  return List.generate(
    16,
    (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

