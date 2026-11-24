import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/di/injection.dart';
import '../../../core/widgets/ui.dart';
import '../../../domain/entities/order.dart';
import 'delivery_evidence_cubit.dart';

/// Tarjeta con la foto de evidencia que dejó el repartidor al entregar.
class DeliveryEvidenceCard extends StatelessWidget {
  /// Recibe el pedido entregado.
  const DeliveryEvidenceCard({super.key, required this.order});
  final Order order;

  /// Crea el cubit del pedido con GetIt y pinta su estado.
  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => getIt<DeliveryEvidenceCubit>(param1: order.id),
    child: _EvidenceBody(order: order),
  );
}

/// Contenido de la tarjeta según el estado: carga, foto, sin foto o error.
class _EvidenceBody extends StatelessWidget {
  /// Recibe el pedido para el texto de la demo.
  const _EvidenceBody({required this.order});
  final Order order;

  /// Pinta la etapa actual de la evidencia.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final state = context.watch<DeliveryEvidenceCubit>().state;

    final Widget body = switch (state.status) {
      EvidenceStatus.loading => const Padding(
        key: Key('evidence-loading'),
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      EvidenceStatus.ready => ClipRRect(
        key: const Key('evidence-photo'),
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          state.url!,
          height: 220,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
          errorBuilder: (_, _, _) => ErrorView(
            title: 'No pudimos mostrar la foto',
            body: 'El enlace venció o no hay conexión.',
            onRetry: context.read<DeliveryEvidenceCubit>().load,
          ),
        ),
      ),
      EvidenceStatus.empty => Text(
        key: const Key('evidence-empty'),
        (order.evidence ?? '').isEmpty
            ? 'El repartidor no adjuntó foto en esta entrega.'
            : 'Registro de la entrega: ${order.evidence}',
        style: t.bodyMedium,
      ),
      EvidenceStatus.failed => ErrorView(
        key: const Key('evidence-error'),
        title: 'No pudimos cargar la foto',
        onRetry: context.read<DeliveryEvidenceCubit>().load,
      ),
    };

    return BiffyCard(
      key: const Key('evidence-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Evidencia de entrega', style: t.titleMedium),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}
