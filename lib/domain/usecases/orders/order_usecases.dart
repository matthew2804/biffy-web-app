import '../../../core/utils/clock.dart';
import '../../ports/order_ports.dart';
import '../../repositories/order_repository.dart';
import 'checkout.dart';
import 'order_commands.dart';
import 'order_queries.dart';
import 'place_order.dart';

export 'checkout.dart';
export 'checkout_draft.dart';
export 'order_commands.dart';
export 'order_queries.dart';
export 'place_order.dart';

/// Todos los casos de uso del ciclo del pedido, ya cableados.
///
/// Es el único punto donde se ensamblan; el `OrdersBloc` recibe este paquete.
class OrderUseCases {
  OrderUseCases({
    required this.repo,
    required OrderCatalogPort catalog,
    required OrderBuyerPort buyers,
    required OrderWalletPort wallet,
    required OrderNotifier notifier,
    required Clock clock,
  }) : _wallet = wallet,
       preview = PreviewCheckout(catalog, buyers),
       validate = ValidateCheckout(repo, catalog, clock),
       queries = OrderQueries(repo, catalog),
       cancelOrder = CancelOrder(repo, catalog, wallet, notifier),
       acceptOrder = AcceptOrder(repo, catalog, wallet, notifier),
       rejectOrder = RejectOrder(repo, catalog, wallet, notifier),
       markOrderReady = MarkOrderReady(repo, catalog, wallet, notifier),
       acceptOffer = AcceptOffer(repo, catalog, wallet, notifier),
       declineOffer = DeclineOffer(repo, catalog, wallet, notifier),
       confirmPickup = ConfirmPickup(repo, catalog, wallet, notifier),
       completeDelivery = CompleteDelivery(repo, catalog, wallet, notifier) {
    placeOrder = PlaceOrder(repo, catalog, wallet, notifier, preview, validate);
  }

  final OrderRepository repo;
  final OrderWalletPort _wallet;

  final PreviewCheckout preview;
  final ValidateCheckout validate;
  final OrderQueries queries;
  late final PlaceOrder placeOrder;
  final CancelOrder cancelOrder;
  final AcceptOrder acceptOrder;
  final RejectOrder rejectOrder;
  final MarkOrderReady markOrderReady;
  final AcceptOffer acceptOffer;
  final DeclineOffer declineOffer;
  final ConfirmPickup confirmPickup;
  final CompleteDelivery completeDelivery;

  /// Relee el saldo de Gotas del servidor (no hace nada en modo demo).
  Future<void> syncWallet() => _wallet.syncBalance();
}
