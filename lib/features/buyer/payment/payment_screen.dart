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
import '../../../domain/payment_errors.dart';
import '../../../domain/repositories/payment_repository.dart';
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
  late final bool _isDemo;
  bool _demoReady = false;
  String? _pseBank;
  String? _openedUrl;
  bool _navigating = false;

  /// Bancos de ejemplo para la simulación local de PSE.
  static const List<String> _pseBanks = [
    'Bancolombia',
    'Banco de Bogotá',
    'Davivienda',
    'BBVA Colombia',
    'Banco Popular',
    'Banco de Occidente',
    'Banco Caja Social',
    'Scotiabank Colpatria',
    'Banco Agrario',
    'Nu Colombia',
  ];

  /// Método de pago elegido en el carrito.
  PaymentMethod get _method => PaymentMethod.values.firstWhere(
    (m) => m.name == widget.method,
    orElse: () => PaymentMethod.card,
  );

  /// Crea el bloc; en modo demo espera a que el comprador simule el pago.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isDemo = !getIt<PaymentRepository>().isRemote;
    _demoReady = _isDemo;
    _bloc = getIt<PaymentBloc>(param1: widget.orderId);
    if (!_isDemo) {
      final order = getIt<OrdersBloc>().byId(widget.code);
      _bloc.add(PaymentStarted(widget.orderId, _method, amount: order?.total));
    }
  }

  /// Al volver de Wompi se consulta el estado real.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isDemo && state == AppLifecycleState.resumed) {
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
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } on Object {
      if (mounted) {
        showSnack(
          context,
          'No pudimos abrir Wompi. Inténtalo de nuevo.',
          error: true,
        );
      }
    }
  }

  /// Inicia el pago simulado solo después de la acción del comprador.
  void _startDemo() {
    if (_method == PaymentMethod.pse && _pseBank == null) return;
    setState(() => _demoReady = false);
    final order = getIt<OrdersBloc>().byId(widget.code);
    _bloc.add(PaymentStarted(widget.orderId, _method, amount: order?.total));
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
              PaymentModeBadge(demo: _isDemo),
              const SizedBox(height: 8),
              if (_isDemo && _demoReady)
                _DemoPaymentCard(
                  method: _method,
                  pseBank: _pseBank,
                  banks: _pseBanks,
                  amount:
                      state.payment?.amount ??
                      getIt<OrdersBloc>().byId(widget.code)?.total,
                  onBankChanged: (bank) => setState(() => _pseBank = bank),
                  onPay: _startDemo,
                  onCancel: () => context.pop(),
                )
              else
                _StatusCard(state: state, demo: _isDemo),
              const SizedBox(height: 12),
              BiffyCard(
                child: Column(
                  children: [
                    InfoRow('Pedido', widget.code),
                    InfoRow('Método elegido', _method.label),
                    if (state.payment?.providerMethod case final method?
                        when method.trim().isNotEmpty)
                      InfoRow('Pagado con', providerMethodLabel(method)),
                    if (state.payment != null)
                      InfoRow('Total', cop(state.payment!.amount)),
                    if (state.payment?.reference.isNotEmpty ?? false)
                      InfoRow('Referencia', state.payment!.reference),
                  ],
                ),
              ),
              if (!(_isDemo && _demoReady)) ...[
                const SizedBox(height: 16),
                ..._actions(context, state),
              ],
              const SizedBox(height: 12),
              Text(
                _isDemo
                    ? 'Esto es una simulación local: no se cobra dinero ni se abre Wompi.'
                    : 'El pago se procesa en la página segura de Wompi. Biffy no guarda datos de tu tarjeta.',
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
      PaymentStep.idle || PaymentStep.processing => [
        const PrimaryButton(label: 'Procesando pago…', onPressed: null),
      ],
      PaymentStep.pending => [
        PrimaryButton(
          label: _isDemo ? 'Simulando pago…' : 'Abrir checkout de Wompi',
          onPressed: _isDemo || state.checkoutUrl == null
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
          onPressed: () =>
              context.pop(state.message ?? 'El pago fue rechazado.'),
        ),
      ],
      PaymentStep.networkError => [
        PrimaryButton(label: 'Reintentar', onPressed: retry),
        const SizedBox(height: 8),
        SecondaryButton(
          label: 'Volver al carrito',
          onPressed: () =>
              context.pop(state.message ?? 'No pudimos confirmar el pago.'),
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
  const _StatusCard({required this.state, required this.demo});

  final PaymentState state;
  final bool demo;

  /// Dibuja el estado actual.
  @override
  Widget build(BuildContext context) {
    final (color, icon, title) = switch (state.step) {
      PaymentStep.idle || PaymentStep.processing => (
        AppColors.primary,
        Icons.hourglass_top,
        'Procesando pago',
      ),
      PaymentStep.pending => (
        AppColors.primary,
        demo ? Icons.hourglass_top : Icons.open_in_new,
        demo ? 'Confirmando pago simulado' : 'Completa el pago en Wompi',
      ),
      PaymentStep.approved => (
        AppColors.success,
        Icons.check_circle,
        'Pago aprobado',
      ),
      PaymentStep.rejected => (AppColors.error, Icons.cancel, 'Pago rechazado'),
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
                    demo
                        ? 'La simulación se aprueba en unos segundos.'
                        : 'Si la página no se abrió, usa el botón de abajo.',
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

/// Tarjeta que simula el checkout de Wompi cuando la app corre sin Supabase.
class _DemoPaymentCard extends StatelessWidget {
  const _DemoPaymentCard({
    required this.method,
    required this.pseBank,
    required this.banks,
    required this.amount,
    required this.onBankChanged,
    required this.onPay,
    required this.onCancel,
  });

  final PaymentMethod method;
  final String? pseBank;
  final List<String> banks;
  final int? amount;
  final ValueChanged<String?> onBankChanged;
  final VoidCallback onPay;
  final VoidCallback onCancel;

  /// Dibuja la simulación con el método elegido y, para PSE, el banco.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final needsBank = method == PaymentMethod.pse && pseBank == null;
    return BiffyCard(
      key: const Key('demo-payment'),
      color: AppColors.secondary.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.science_outlined, color: AppColors.text),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Simulación de Wompi',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'No se cobra dinero real. En producción aquí se abre la página '
            'segura de Wompi con el método que elijas.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          InfoRow('Método', method.label),
          if (method == PaymentMethod.pse) ...[
            const SizedBox(height: 8),
            Text(
              'Banco para PSE',
              style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.muted.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  key: const Key('demo-pse-bank'),
                  value: pseBank,
                  isExpanded: true,
                  hint: const Text('Elige tu banco'),
                  items: [
                    for (final bank in banks)
                      DropdownMenuItem(value: bank, child: Text(bank)),
                  ],
                  onChanged: onBankChanged,
                ),
              ),
            ),
            if (needsBank) ...[
              const SizedBox(height: 4),
              Text(
                'Elige el banco para continuar.',
                style: t.bodySmall?.copyWith(color: AppColors.error),
              ),
            ],
          ] else ...[
            const SizedBox(height: 4),
            Text(_hint, style: t.bodySmall),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            key: const Key('demo-pay'),
            label: amount == null
                ? 'Simular pago'
                : 'Simular pago · ${cop(amount!)}',
            onPressed: needsBank ? null : onPay,
          ),
          const SizedBox(height: 8),
          SecondaryButton(
            key: const Key('demo-cancel'),
            label: 'Volver al carrito',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }

  /// Explica qué datos pediría Wompi para el método elegido.
  String get _hint => switch (method) {
    PaymentMethod.card => 'En Wompi ingresarías los datos de tu tarjeta.',
    PaymentMethod.nequi => 'En Wompi confirmarías el pago desde tu app Nequi.',
    PaymentMethod.daviplata =>
      'En Wompi confirmarías el pago desde tu app Daviplata.',
    PaymentMethod.pse => 'En Wompi elegirías el banco para el débito PSE.',
    PaymentMethod.cash => 'El efectivo se cobra al recibir el pedido.',
  };
}
