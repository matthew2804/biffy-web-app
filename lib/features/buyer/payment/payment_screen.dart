import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/di/injection.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/entities/catalog.dart';
import '../cart/bloc/cart_cubit.dart';
import '../../orders/bloc/orders_bloc.dart';
import 'bloc/payment_bloc.dart';

/// Pantalla del pago: abre el checkout de Wompi y muestra el estado en vivo.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.code,
    required this.orderId,
    this.method,
  });

  /// Código del pedido (BF-…), el que usan el seguimiento y el comprador.
  final String code;

  /// Id real del pedido (uuid en Supabase; id del pedido en demo).
  final String orderId;

  /// Método elegido en el carrito (`nequi`, `card`, `pse`…).
  final String? method;

  /// Crea el estado de la pantalla.
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

/// Estado que crea el [PaymentBloc] y reacciona a Wompi.
class _PaymentScreenState extends State<PaymentScreen>
    with WidgetsBindingObserver {
  late final PaymentBloc _bloc;
  String? _openedUrl;
  bool _navigating = false;

  /// Método de pago elegido en el carrito.
  PaymentMethod get _method => PaymentMethod.values.firstWhere(
    (m) => m.name == widget.method,
    orElse: () => PaymentMethod.card,
  );

  /// Crea el bloc y arranca el pago.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = getIt<PaymentBloc>(param1: widget.orderId);
    final order = getIt<OrdersBloc>().byId(widget.code);
    _bloc.add(PaymentStarted(widget.orderId, _method, amount: order?.total));
  }

  /// Al volver de Wompi se consulta el estado real.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _bloc.add(const PaymentStatusChecked());
    }
  }

  /// Libera el bloc y el observador.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.close();
    super.dispose();
  }

  /// Abre el checkout de Wompi una sola vez por URL.
  Future<void> _openCheckout(String url) async {
    if (_openedUrl == url) return;
    _openedUrl = url;
    try {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      if (mounted) {
        showSnack(context, 'No pudimos abrir Wompi. Inténtalo de nuevo.', error: true);
      }
    }
  }

  /// Reacciona al estado: abre el checkout y navega si se aprobó.
  void _listen(BuildContext context, PaymentState state) {
    final url = state.checkoutUrl;
    if (url != null && url.isNotEmpty && state.step != PaymentStep.approved) {
      unawaited(_openCheckout(url));
    }
    if (state.step == PaymentStep.approved && !_navigating) {
      _navigating = true;
      getIt<CartCubit>().clear();
      context.go('/pedido/${widget.code}');
    }
  }

  /// Construye la pantalla del pago.
  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PaymentBloc, PaymentState>(
      bloc: _bloc,
      listener: _listen,
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Pago')),
        body: MobileFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              _StatusCard(state: state),
              const SizedBox(height: 12),
              BiffyCard(
                child: Column(
                  children: [
                    InfoRow('Pedido', widget.code),
                    InfoRow('Método', _method.label),
                    if (state.payment != null)
                      InfoRow('Total', cop(state.payment!.amount)),
                    if (state.payment?.reference.isNotEmpty ?? false)
                      InfoRow('Referencia', state.payment!.reference),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ..._actions(context, state),
              const SizedBox(height: 12),
              Text(
                'El pago se procesa en la página segura de Wompi. Biffy no guarda datos de tu tarjeta.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Botones según la etapa del pago.
  List<Widget> _actions(BuildContext context, PaymentState state) {
    final retry = state.canRetry
        ? () => _bloc.add(PaymentRetried(_method))
        : null;
    return switch (state.step) {
      PaymentStep.idle ||
      PaymentStep.processing => [
        const PrimaryButton(label: 'Procesando pago…', onPressed: null),
      ],
      PaymentStep.pending => [
        PrimaryButton(
          label: 'Abrir checkout de Wompi',
          onPressed: state.checkoutUrl == null
              ? null
              : () => _openCheckout(state.checkoutUrl!),
        ),
        const SizedBox(height: 8),
        SecondaryButton(
          label: 'Volver al carrito',
          onPressed: () => context.pop(),
        ),
      ],
      PaymentStep.rejected => [
        PrimaryButton(label: 'Reintentar pago', onPressed: retry),
        const SizedBox(height: 8),
        SecondaryButton(
          label: 'Volver al carrito',
          onPressed: () => context.pop(
            state.message ?? 'El pago fue rechazado.',
          ),
        ),
      ],
      PaymentStep.networkError => [
        PrimaryButton(label: 'Reintentar', onPressed: retry),
        const SizedBox(height: 8),
        SecondaryButton(
          label: 'Volver al carrito',
          onPressed: () => context.pop(
            state.message ?? 'No pudimos confirmar el pago.',
          ),
        ),
      ],
      PaymentStep.expired => [
        PrimaryButton(
          label: 'Volver al carrito',
          onPressed: () => context.pop(
            state.message ?? 'El pago venció y el pedido se canceló.',
          ),
        ),
      ],
      PaymentStep.approved => const [
        Text(
          'Redirigiendo a tu pedido…',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    };
  }
}

/// Tarjeta con el icono, el título y el mensaje del estado del pago.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final PaymentState state;

  /// Dibuja el estado actual.
  @override
  Widget build(BuildContext context) {
    final (color, icon, title) = switch (state.step) {
      PaymentStep.idle ||
      PaymentStep.processing => (
        AppColors.primary,
        Icons.hourglass_top,
        'Procesando pago',
      ),
      PaymentStep.pending => (
        AppColors.primary,
        Icons.open_in_new,
        'Completa el pago en Wompi',
      ),
      PaymentStep.approved => (
        AppColors.success,
        Icons.check_circle,
        'Pago aprobado',
      ),
      PaymentStep.rejected => (
        AppColors.error,
        Icons.cancel,
        'Pago rechazado',
      ),
      PaymentStep.expired => (
        AppColors.error,
        Icons.timer_off,
        'El pago venció',
      ),
      PaymentStep.networkError => (
        AppColors.error,
        Icons.wifi_off,
        'Sin conexión',
      ),
    };
    return BiffyCard(
      color: color.withValues(alpha: 0.08),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 4),
                  Text(state.message!),
                ],
                if (state.step == PaymentStep.pending) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Si la página no se abrió, usa el botón de abajo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
