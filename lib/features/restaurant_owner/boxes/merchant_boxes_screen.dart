import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/rewards.dart';
import '../../../domain/repositories/merchant_boxes_repository.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';
import 'merchant_boxes_cubit.dart';

/// Permite al restaurante meter y sacar sus platos de las cajas de Gotas.
///
/// Solo funciona con Supabase: la demo local no tiene cajas configurables.
/// La lógica vive en [MerchantBoxesCubit]; esta pantalla solo la pinta.
class MerchantBoxesScreen extends StatelessWidget {
  const MerchantBoxesScreen({super.key});

  /// En demo avisa que requiere Supabase; con la base crea el cubit.
  @override
  Widget build(BuildContext context) {
    final repo = context.read<MerchantBoxesRepository?>();
    if (repo == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cajas con Gotas')),
        body: const MobileFrame(
          child: EmptyState(
            emoji: '📦',
            title: 'Solo con Supabase',
            body: 'Las cajas configurables se activan al conectar la base.',
          ),
        ),
      );
    }
    return BlocProvider(
      create: (_) => MerchantBoxesCubit(repo)..load(),
      child: const _MerchantBoxesView(),
    );
  }
}

/// Contenido de la pantalla cuando hay Supabase.
class _MerchantBoxesView extends StatefulWidget {
  const _MerchantBoxesView();

  /// Crea el estado de la pantalla.
  @override
  State<_MerchantBoxesView> createState() => _MerchantBoxesViewState();
}

/// Estado: guarda el campo del código de premio.
class _MerchantBoxesViewState extends State<_MerchantBoxesView> {
  /// Código que el comprador dicta en la sede.
  final _codeController = TextEditingController();

  /// Libera el controlador del código.
  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Pide al cubit validar el código y limpia el campo si salió bien.
  Future<void> _validate(BuildContext context) async {
    final ok = await context.read<MerchantBoxesCubit>().claim(
      _codeController.text,
    );
    if (ok) _codeController.clear();
  }

  /// Abre el selector de platos del menú propio para una caja.
  Future<void> _addDish(BuildContext context, GotasBox box) async {
    final catalog = context.read<CatalogController>();
    final businessId = context.read<SessionController>().businessId;
    final cubit = context.read<MerchantBoxesCubit>();
    if (businessId == null) return;

    // Platos activos del negocio (todas sus sedes).
    final dishes = catalog
        .productsOf(businessId)
        .where((d) => d.active)
        .toList();
    if (dishes.isEmpty) {
      showSnack(context, 'Primero crea un producto en tu menú.', error: true);
      return;
    }

    final picked = await showModalBottomSheet<Dish>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Elige un plato para la caja',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            for (final dish in dishes)
              ListTile(
                leading: Text(dish.emoji, style: const TextStyle(fontSize: 24)),
                title: Text(dish.name),
                subtitle: Text(cop(dish.price)),
                onTap: () => Navigator.of(sheetContext).pop(dish),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await cubit.addDish(box, picked);
  }

  /// Pinta el estado del cubit y muestra sus avisos.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cubit = context.read<MerchantBoxesCubit>();

    return Scaffold(
      appBar: AppBar(title: const Text('Cajas con Gotas')),
      body: MobileFrame(
        child: BlocConsumer<MerchantBoxesCubit, MerchantBoxesState>(
          listenWhen: (a, b) => a.messageCount != b.messageCount,
          listener: (context, state) =>
              showSnack(context, state.message!, error: state.messageIsError),
          builder: (context, state) {
            if (state.status == BoxesStatus.loading &&
                state.data.boxes.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.status == BoxesStatus.error) {
              return ErrorView(
                title: 'No pudimos cargar las cajas',
                onRetry: cubit.load,
              );
            }
            final data = state.data;
            if (data.boxes.isEmpty) {
              return const EmptyState(
                emoji: '📦',
                title: 'Sin cajas configurables',
                body: 'Aún no hay cajas activas para tu negocio.',
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                BiffyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Validar premio',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Escribe el código que muestra el cliente.',
                        style: t.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('claim-code-input'),
                              controller: _codeController,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                hintText: 'ABC123',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            key: const Key('claim-code-validate'),
                            onPressed: () => _validate(context),
                            child: const Text('Validar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Elige qué platos puede entregar tu negocio en cada caja.',
                  style: t.bodyMedium,
                ),
                const SizedBox(height: 12),
                for (final box in data.boxes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BoxCard(
                      box: box,
                      items: data.itemsOf(box),
                      busy: state.busy,
                      onAdd: () => _addDish(context, box),
                      onRemove: cubit.removeDish,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Tarjeta de una caja con sus platos y acciones.
class _BoxCard extends StatelessWidget {
  const _BoxCard({
    required this.box,
    required this.items,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });

  final GotasBox box;
  final List<BoxItemView> items;
  final bool busy;
  final VoidCallback onAdd;
  final void Function(BoxItemView item) onRemove;

  /// Dibuja la caja con sus platos y botones.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return BiffyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(box.emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      box.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${box.cost} Gotas · ${box.limitLabel}',
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: busy ? null : onAdd,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Plato'),
              ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Sin platos: la caja entrega premios de plataforma.',
                style: t.bodySmall,
              ),
            )
          else
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Text('🍽️'),
                title: Text(item.dishName),
                subtitle: Text(item.branchName),
                trailing: IconButton(
                  tooltip: 'Quitar de la caja',
                  onPressed: busy ? null : () => onRemove(item),
                  icon: const Icon(Icons.close, color: AppColors.error),
                ),
              ),
        ],
      ),
    );
  }
}
