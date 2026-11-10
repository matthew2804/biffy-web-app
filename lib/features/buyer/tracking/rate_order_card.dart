import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/order.dart';
import '../../../domain/order_rules.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

/// Tarjeta para calificar un pedido entregado, o la calificación ya enviada.
class RateOrderCard extends StatelessWidget {
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
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RateSheet(order: order, initial: initial),
  );
}

class _RateSheet extends StatefulWidget {
  const _RateSheet({required this.order, required this.initial});
  final Order order;
  final int initial;

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late int _stars = widget.initial;
  final _comment = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// Envía la calificación y cierra la hoja si salió bien.
  Future<void> _send() async {
    final user = context.read<SessionController>().user;
    if (user == null) return;
    setState(() => _sending = true);
    final res = await context.read<OrderService>().rateOrder(
      widget.order.id,
      user.id,
      _stars,
      comment: _comment.text,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (res == RateResult.ok) {
      Navigator.pop(context);
      showSnack(context, '¡Gracias por calificar! ⭐');
    } else {
      showSnack(context, rateMessage(res), error: true);
    }
  }

  /// Hoja con estrellas, comentario opcional y botón de enviar.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
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
            Text(widget.order.restaurantName, style: t.bodyMedium),
            const SizedBox(height: 8),
            StarsRow(
              value: _stars,
              keyPrefix: 'rate-star',
              size: 40,
              onTap: (v) => setState(() => _stars = v),
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
              label: _sending ? 'Enviando…' : 'Enviar calificación',
              icon: Icons.star_rounded,
              onPressed: _stars == 0 || _sending ? null : _send,
            ),
          ],
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
