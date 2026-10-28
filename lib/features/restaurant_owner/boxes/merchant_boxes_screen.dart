import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/supabase_rewards_repository.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';

/// Permite al restaurante meter y sacar sus platos de las cajas de Gotas.
///
/// Solo funciona con Supabase: la demo local no tiene cajas configurables.
class MerchantBoxesScreen extends StatefulWidget {
  const MerchantBoxesScreen({super.key});

  @override
  State<MerchantBoxesScreen> createState() => _MerchantBoxesScreenState();
}

/// Estado de la pantalla: carga cajas e ítems del negocio.
class _MerchantBoxesScreenState extends State<MerchantBoxesScreen> {
  final _repo = SupabaseRewardsRepository();

  /// Cajas configurables y platos que ya están dentro.
  Future<({List<GotasBox> boxes, List<BoxItemView> items})>? _future;

  /// Evita doble toque mientras se guarda un cambio.
  bool _busy = false;

  /// Código que el comprador dicta en la sede.
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Valida un código de premio y lo marca como reclamado.
  Future<void> _validate() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    final res = await _repo.useRedemption(code);
    if (!mounted) return;
    if (res.ok) {
      _codeController.clear();
      showSnack(context, 'Premio entregado: ${res.prize}');
    } else {
      showSnack(context, res.error ?? 'No se pudo validar', error: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  /// Lee cajas activas y los platos que el negocio tiene metidos.
  Future<({List<GotasBox> boxes, List<BoxItemView> items})> _load() async {
    final boxes = await _repo.boxes();
    final items = await _repo.merchantItems();
    return (
      boxes: boxes.where((b) => b.merchantManaged).toList(),
      items: items,
    );
  }

  /// Vuelve a cargar tras un cambio.
  void _reload() => setState(() => _future = _load());

  /// Abre el selector de platos del menú propio para una caja.
  Future<void> _addDish(GotasBox box) async {
    final catalog = context.read<CatalogController>();
    final businessId = context.read<SessionController>().businessId;
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
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    await _repo.addItem(
      rewardCode: box.code,
      branchId: picked.restaurantId,
      dishId: picked.id,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    showSnack(context, '${picked.name} entró a ${box.name}');
  }

  /// Saca un plato de una caja.
  Future<void> _remove(BoxItemView item) async {
    setState(() => _busy = true);
    await _repo.removeItem(item.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
    showSnack(context, '${item.dishName} salió de la caja');
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cajas con Gotas')),
      body: MobileFrame(
        child: !session.auth.isRemote
            ? const EmptyState(
                emoji: '📦',
                title: 'Solo con Supabase',
                body: 'Las cajas configurables se activan al conectar la base.',
              )
            : FutureBuilder<({List<GotasBox> boxes, List<BoxItemView> items})>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    return const EmptyState(
                      emoji: '⚠️',
                      title: 'No pudimos cargar las cajas',
                      body: 'Revisa tu conexión e inténtalo de nuevo.',
                    );
                  }
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
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: const InputDecoration(
                                      hintText: 'ABC123',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  key: const Key('claim-code-validate'),
                                  onPressed: _validate,
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
                            items: data.items
                                .where((i) => i.rewardCode == box.code)
                                .toList(),
                            busy: _busy,
                            onAdd: () => _addDish(box),
                            onRemove: _remove,
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
