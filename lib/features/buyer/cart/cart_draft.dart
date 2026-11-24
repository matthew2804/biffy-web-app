import '../../../data/models/address.dart';
import '../../../domain/usecases/orders/checkout_draft.dart';
import '../../../shared/state/session_controller.dart';
import 'bloc/cart_cubit.dart';

/// Dirección elegida para el carrito (o la predeterminada del usuario).
Address? cartAddress(SessionController session, CartCubit cart) =>
    session.addressById(cart.addressId) ?? session.data.defaultAddress;

/// Construye el borrador del checkout a partir del carrito actual.
CheckoutDraft draftFromCart(SessionController session, CartCubit cart) =>
    CheckoutDraft(
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
      cashTendered: cart.cashTendered,
    );
