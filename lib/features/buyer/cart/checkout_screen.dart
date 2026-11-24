import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/confetti.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/cash_payment.dart';
import '../../../domain/catalog_rules.dart';
import '../../../domain/entities/catalog.dart';
import '../../../domain/pricing.dart';
import '../../../features/orders/bloc/orders_bloc.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';
import 'bloc/cart_cubit.dart';
import 'bloc/checkout_cubit.dart';
import 'cart_screen.dart';
import '../payment/payment_method_sheet.dart';
import '../../../app/di/injection.dart';
import '../../../shared/state/controller_scope.dart';

/// Resumen final y confirmación del pedido de demostración (sin pagos).
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  /// Crea el estado del resumen de checkout.
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

/// Estado que delega el envío del pedido a [CheckoutCubit].
class _CheckoutScreenState extends State<CheckoutScreen> {
  late final CheckoutCubit _checkout;

  /// Pedido ya creado esperando pago (id real y código visible).
  String? _pendingOrderId;
  String? _pendingCode;

  /// Motivo del último rechazo, para mostrarlo en el carrito.
  String? _paymentError;

  /// Crea el cubit con los pedidos, la sesión y el carrito compartidos.
  @override
  void initState() {
    super.initState();
    _checkout = getIt<CheckoutCubit>();
  }

  /// Libera el cubit al salir del checkout.
  @override
  void dispose() {
    _checkout.close();
    super.dispose();
  }

  /// Construye el resumen, los errores y el botón de confirmar.
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartCubit>();
    context.watchController<SessionController>();
    final catalog = context.watchController<CatalogController>();
    final orders = context.read<OrdersBloc>();
    final t = Theme.of(context).textTheme;
    final draft = _checkout.draft;
    final r = draft.restaurant;
    if (r == null || draft.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: EmptyState(
          emoji: '🛒',
          title: 'No hay productos para confirmar',
          actionLabel: 'Explorar comida',
          onAction: () => context.go('/explorar'),
        ),
      );
    }
    final totals = _checkout.totals;
    final errors = _checkout.errors;
    final point = draft.address == null
        ? null
        : pointById(draft.address!.pointId);
    final method = draft.payment;
    final isCash = method == PaymentMethod.cash;
    final cashTendered = cart.cashTendered ?? (isCash ? totals.total : null);
    final cashChange = isCash && cashTendered != null
        ? changeFor(totals.total, cashTendered)
        : 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar pedido')),
      body: BlocBuilder<CheckoutCubit, CheckoutState>(
        bloc: _checkout,
        builder: (context, state) => MobileFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              if (isCash)
                const Tag('💵 Pago contra entrega')
              else
                PaymentModeBadge(demo: !orders.isRemote),
              const SizedBox(height: 8),
              Text(
                isCash
                    ? 'Pago contra entrega'
                    : orders.isRemote
                    ? 'Pago seguro con Wompi'
                    : 'Pago simulado (demo)',
                style: t.labelLarge?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 12),
              BiffyCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: t.titleMedium),
                    const SizedBox(height: 8),
                    for (final i in draft.items)
                      if (catalog.dishById(i.dishId) case final d?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i.qty}×  ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (selectionDetail(
                                      d,
                                      i.selection,
                                    ).isNotEmpty)
                                      Text(
                                        selectionDetail(d, i.selection),
                                        style: t.bodySmall,
                                      ),
                                    if (i.note.isNotEmpty)
                                      Text('📝 ${i.note}', style: t.bodySmall),
                                  ],
                                ),
                              ),
                              Text(cop(lineTotal(d, i.selection, i.qty))),
                            ],
                          ),
                        ),
                    if (draft.restaurantNote.isNotEmpty)
                      Text('Nota: ${draft.restaurantNote}', style: t.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              BiffyCard(
                child: Column(
                  children: [
                    InfoRow(
                      'Entrega',
                      draft.address == null
                          ? 'Sin dirección'
                          : '${draft.address!.label} · ${draft.address!.line}',
                    ),
                    InfoRow(
                      'Fecha y hora',
                      draft.scheduledFor == null
                          ? 'Ahora'
                          : dateTimeLabel(draft.scheduledFor!),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Método de pago',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              method.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                          TextButton(
                            key: const Key('change-payment'),
                            onPressed: _pickMethod,
                            child: const Text('Cambiar'),
                          ),
                        ],
                      ),
                    ),
                    if (method.isOnline)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'El método final se confirma en Wompi.',
                          style: t.bodySmall,
                        ),
                      ),
                    if (point != null)
                      InfoRow(
                        'Tiempo estimado',
                        draft.scheduledFor == null
                            ? '~${etaMinutes(r, point)} min'
                            : 'A la hora programada',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TotalsCard(totals: totals),
              if (isCash) ...[
                const SizedBox(height: 12),
                BiffyCard(
                  key: const Key('cash-bills'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '¿Con qué billete pagas?',
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final bill in cashOptions(totals.total))
                            ChoiceChip(
                              label: Text(
                                bill == totals.total
                                    ? 'Pago exacto (${cop(bill)})'
                                    : cop(bill),
                              ),
                              selected: cashTendered == bill,
                              onSelected: (_) => cart.setCashTendered(bill),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cashChange > 0
                            ? 'Pagas con ${cop(cashTendered!)} · Vueltas ${cop(cashChange)}'
                            : 'Pagas el valor exacto.',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (_paymentError != null) ...[
                const SizedBox(height: 12),
                BiffyCard(
                  key: const Key('payment-error'),
                  color: AppColors.error.withValues(alpha: 0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'El pago no se completó',
                        style: TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(_paymentError!),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _place,
                            child: const Text('Reintentar pago'),
                          ),
                          TextButton(
                            onPressed: _cancelPending,
                            child: const Text('Cancelar pedido'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                BiffyCard(
                  key: const Key('checkout-errors'),
                  color: AppColors.error.withValues(alpha: 0.1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in errors)
                        Text(
                          '• $e',
                          style: const TextStyle(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Volver al carrito'),
                      ),
                    ],
                  ),
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ],
              const SizedBox(height: 16),
              PrimaryButton(
                key: const Key('confirm-order'),
                label: state.placing
                    ? 'Creando pedido…'
                    : _pendingOrderId != null
                    ? 'Reintentar pago · ${cop(totals.total)}'
                    : isCash
                    ? 'Confirmar pedido · ${cop(totals.total)}'
                    : 'Pagar con ${method.label} · ${cop(totals.total)}',
                onPressed:
                    errors.isNotEmpty ||
                        state.placing ||
                        (isCash &&
                            (cashTendered == null ||
                                cashTendered < totals.total))
                    ? null
                    : _place,
              ),
              const SizedBox(height: 8),
              Text(
                isCash
                    ? 'El repartidor te cobrará al entregar el pedido.'
                    : orders.isRemote
                    ? 'Te llevaremos a la página segura de Wompi para pagar.'
                    : 'En la demo el pago se simula en la siguiente pantalla.',
                textAlign: TextAlign.center,
                style: t.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Abre la hoja para cambiar el método antes de confirmar.
  Future<void> _pickMethod() async {
    final cart = context.read<CartCubit>();
    final picked = await showPaymentMethodSheet(
      context,
      selected: _checkout.draft.payment,
    );
    if (picked != null) cart.setPayment(picked);
  }

  /// Crea el pedido y, si es online, abre el pago en Wompi.
  Future<void> _place() async {
    final method = _checkout.draft.payment;
    final totals = _checkout.totals;
    final cart = context.read<CartCubit>();

    if (method == PaymentMethod.cash) {
      if (cart.cashTendered == null) cart.setCashTendered(totals.total);
      if ((cart.cashTendered ?? 0) < totals.total) return;
    }

    // Si el pedido ya existe, se reintenta su pago en vez de duplicarlo.
    if (_pendingOrderId != null) {
      await _openPayment(
        _pendingOrderId!,
        _pendingCode ?? _pendingOrderId!,
        method,
      );
      return;
    }

    final outcome = await _checkout.submit(
      clearCart: method == PaymentMethod.cash,
    );
    if (!mounted || outcome == null) return;
    if (!outcome.result.ok) {
      showSnack(context, outcome.result.message, error: true);
      return;
    }
    final code = outcome.orderId;
    if (code == null) return;

    if (method == PaymentMethod.cash) {
      showSnack(
        context,
        _checkout.state.message ??
            (code.isEmpty ? 'Pedido creado' : 'Pedido $code creado'),
      );
      celebrate(context);
      context.go('/pedido/$code');
      return;
    }

    // El id real (uuid) es el que entiende la pasarela; el código es la ruta.
    final order = context.read<OrdersBloc>().byId(code);
    final paymentId = order?.dbId ?? order?.id ?? code;
    setState(() {
      _pendingOrderId = paymentId;
      _pendingCode = code;
      _paymentError = null;
    });
    await _openPayment(paymentId, code, method);
  }

  /// Abre la pantalla de pago y recoge el mensaje de rechazo.
  Future<void> _openPayment(
    String paymentId,
    String code,
    PaymentMethod method,
  ) async {
    final message = await context.push<String>(
      '/pago/$code?order=$paymentId&method=${method.name}',
    );
    if (!mounted || message == null) return;
    setState(() => _paymentError = message);
  }

  /// Cancela el pedido pendiente y devuelve el carrito editable.
  Future<void> _cancelPending() async {
    final code = _pendingCode;
    if (code == null) return;
    await context.read<OrdersBloc>().request(OrderCancelled(code));
    if (!mounted) return;
    setState(() {
      _pendingOrderId = null;
      _pendingCode = null;
      _paymentError = null;
    });
  }
}
