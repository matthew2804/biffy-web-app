import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../data/models/address.dart';
import '../../../shared/state/cart_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

/// Dirección elegida para el carrito (o la predeterminada del usuario).
Address? cartAddress(SessionController session, CartController cart) =>
    session.addressById(cart.addressId) ?? session.data.defaultAddress;

/// Construye el borrador del checkout a partir del carrito actual.
CheckoutDraft draftFromCart(BuildContext context) {
  final session = context.read<SessionController>();
  final cart = context.read<CartController>();
  return CheckoutDraft(
    buyer: session.user,
    restaurant: cart.restaurant,
    items: cart.items,
    address: cartAddress(session, cart),
    payment: cart.payment ?? session.data.defaultPayment,
    scheduledFor: cart.scheduledFor,
    tip: cart.tip,
    useGotas: cart.useGotas && session.isLoggedIn,
    coupon: session.couponById(cart.couponId),
    restaurantNote: cart.restaurantNote,
  );
}
