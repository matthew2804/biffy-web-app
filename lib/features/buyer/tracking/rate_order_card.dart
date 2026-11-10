import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../domain/order_rules.dart';
import '../../../domain/usecases/rate_order.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import 'rate_order_cubit.dart';

/// Tarjeta para calificar un pedido entregado, o la calificación ya enviada.
class RateOrderCard extends StatelessWidget {
  /// Recibe el pedido entregado.
  const RateOrderCard({super.key, required this.order});
  final Order order;

  /// Muestra las estrellas para calificar o la reseña guardada.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rating = order.rating;

    if (rating != null) {
      return BiffyCard(
        key: const Key('rate-done'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tu calificación', style: t.titleMedium),
            const SizedBox(height: 6),
            StarsRow(value: rating),
            if (order.review.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('«${order.review}»', style: t.bodyMedium),
            ],
          ],
        ),
      );
    }

    return BiffyCard(
      key: const Key('rate-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('¿Qué tal estuvo?', style: t.titleMedium),
          const SizedBox(height: 2),
          Text(
            'Califica a ${order.restaurantName}. Tu opinión ayuda a otros estudiantes.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          StarsRow(
            value: 0,
            keyPrefix: 'rate-card-star',
            onTap: (stars) => showRateOrderSheet(context, order, stars),
          ),
        ],
      ),
    );
  }
}

/// Fila de cinco estrellas; con [onTap] cada estrella es un botón.
class StarsRow extends StatelessWidget {
  /// Recibe cuántas estrellas pintar y, si se puede tocar, qué hacer.
  const StarsRow({
    super.key,
    required this.value,
    this.onTap,
    this.keyPrefix = 'star',
    this.size = 32,
  });

  final int value;
  final ValueChanged<int>? onTap;
  final String keyPrefix;
  final double size;

  /// Dibuja las estrellas llenas hasta [value].
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          onTap == null
              ? Icon(
                  i <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: AppColors.primary,
                  size: size,
                )
              : IconButton(
                  key: Key('$keyPrefix-$i'),
                  tooltip: '$i de 5',
                  iconSize: size,
                  onPressed: () => onTap!(i),
                  icon: Icon(
                    i <= value
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: AppColors.primary,
                  ),
                ),
      ],
    );
  }
}

/// Abre la hoja para calificar con [initial] estrellas preseleccionadas.
Future<void> showRateOrderSheet(
  BuildContext context,
  Order order,
  int initial,
) {
  final user = context.read<SessionController>().user;
  if (user == null) return Future.value();
  final rateOrder = context.read<RateOrder>();
  final orders = context.read<OrderService>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => BlocProvider(
      create: (_) => RateOrderCubit(
        rateOrder: rateOrder,
        orders: orders,
        order: order,
        userId: user.id,
        initialStars: initial,
      ),
      child: const _RateSheet(),
    ),
  );
}

/// Hoja inferior para elegir estrellas y escribir un comentario.
class _RateSheet extends StatefulWidget {
  const _RateSheet();

  /// Crea el estado de la hoja.
  @override
  State<_RateSheet> createState() => _RateSheetState();
}

/// Estado de la hoja: guarda el texto del comentario.
class _RateSheetState extends State<_RateSheet> {
  final _comment = TextEditingController();

  /// Libera el controlador del comentario.
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Hoja con estrellas, comentario opcional y botón de enviar. Solo pinta el
  /// estado del [RateOrderCubit] y le avisa lo que toca el usuario.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cubit = context.read<RateOrderCubit>();
    return BlocConsumer<RateOrderCubit, RateOrderState>(
      listenWhen: (a, b) => a.status != b.status,
      listener: (context, state) {
        if (state.status == RateStatus.done) {
          Navigator.pop(context);
          showSnack(context, '¡Gracias por calificar! ⭐');
        } else if (state.status == RateStatus.failed) {
          showSnack(context, rateMessage(state.error!), error: true);
        }
      },
      builder: (context, state) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Califica tu pedido', style: t.titleLarge),
              const SizedBox(height: 4),
              Text(cubit.order.restaurantName, style: t.bodyMedium),
              const SizedBox(height: 8),
              StarsRow(
                value: state.stars,
                keyPrefix: 'rate-star',
                size: 40,
                onTap: cubit.selectStars,
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('rate-comment'),
                controller: _comment,
                maxLength: kMaxReviewComment,
                maxLines: 3,
                minLines: 1,
                decoration: const InputDecoration(
                  hintText: 'Cuéntanos más (opcional)',
                ),
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                key: const Key('rate-submit'),
                label: state.status == RateStatus.sending
                    ? 'Enviando…'
                    : 'Enviar calificación',
                icon: Icons.star_rounded,
                onPressed: state.canSubmit
                    ? () => cubit.submit(_comment.text)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mensaje para el comprador según el resultado de calificar.
String rateMessage(RateResult r) => switch (r) {
  RateResult.ok => '¡Gracias por calificar!',
  RateResult.alreadyRated => 'Ya calificaste este pedido.',
  RateResult.invalidState => 'Solo puedes calificar pedidos entregados.',
  RateResult.forbidden => 'Este pedido no es tuyo.',
  RateResult.notFound => 'No encontramos el pedido.',
  RateResult.invalidRating => 'Elige de 1 a 5 estrellas.',
  RateResult.commentTooLong =>
    'El comentario es muy largo (máximo $kMaxReviewComment caracteres).',
  RateResult.offline => 'Sin conexión. Intenta de nuevo en un momento.',
};
