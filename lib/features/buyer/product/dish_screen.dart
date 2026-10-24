import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/cart.dart';
import '../../../data/models/catalog.dart';
import '../../../domain/catalog_rules.dart';
import '../../../domain/pricing.dart';
import '../../../shared/state/cart_controller.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';

/// Detalle y personalización. Con [editLineId] edita una línea del carrito
/// sin modificarla hasta guardar.
class DishScreen extends StatefulWidget {
  const DishScreen({super.key, required this.id, this.editLineId});
  final String id;
  final String? editLineId;

  @override
  State<DishScreen> createState() => _DishScreenState();
}

class _DishScreenState extends State<DishScreen> {
  DishSelection? _sel;
  int _qty = 1;
  final _note = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _init(Dish d) {
    if (_initialized) return;
    _initialized = true;
    final line = widget.editLineId == null
        ? null
        : context.read<CartController>().lineById(widget.editLineId!);
    if (line != null) {
      _sel = line.selection;
      _qty = line.qty;
      _note.text = line.note;
    } else {
      _sel = defaultSelection(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    final d = catalog.dishById(widget.id);
    if (d == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🍽️',
          title: 'Plato no encontrado',
          actionLabel: 'Explorar',
          onAction: () => context.go('/explorar'),
        ),
      );
    }
    _init(d);
    final sel = _sel!;
    final r = catalog.restaurantById(d.restaurantId)!;
    final editing = widget.editLineId != null;
    final unit = unitPrice(d, sel);
    final total = unit * _qty;
    final conflicts = allergyConflicts(d, session.prefs.allergies);
    final fav = session.data.favoriteDishes.contains(d.id);
    final media = MediaQuery.of(context);

    return Scaffold(
      body: MobileFrame(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  FoodImage.dish(
                    d,
                    size: 240 + media.padding.top,
                    radius: 0,
                    width: double.infinity,
                  ),
                  Positioned(
                    left: 12,
                    top: media.padding.top + 8,
                    child: RoundIconButton(
                      icon: Icons.arrow_back,
                      tooltip: 'Volver',
                      onTap: () =>
                          context.canPop() ? context.pop() : context.go('/'),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    top: media.padding.top + 8,
                    child: Row(
                      children: [
                        RoundIconButton(
                          icon: Icons.share_outlined,
                          tooltip: 'Compartir',
                          onTap: () =>
                              copyShareLink(context, 'plato/${d.id}', d.name),
                        ),
                        const SizedBox(width: 8),
                        RoundIconButton(
                          key: const Key('fav-dish'),
                          icon: fav ? Icons.favorite : Icons.favorite_border,
                          iconColor: fav ? AppColors.error : null,
                          tooltip: fav
                              ? 'Quitar de favoritos'
                              : 'Agregar a favoritos',
                          onTap: () => toggleFavoriteDish(context, d),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  Text(d.name, style: t.headlineSmall),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => context.push('/restaurante/${r.id}'),
                    child: Text(
                      '${r.name} · ⭐ ${d.rating.toStringAsFixed(1)} · ${d.prepMin} min de preparación',
                      style: t.bodySmall?.copyWith(
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    cop(d.price),
                    style: t.headlineSmall?.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(d.description, style: t.bodyMedium),
                  if (r.demo) ...[
                    const SizedBox(height: 8),
                    const DemoBadge('Precio ilustrativo, no oficial'),
                  ],
                  if (conflicts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    BiffyCard(
                      key: const Key('allergy-warning'),
                      color: AppColors.error.withValues(alpha: 0.12),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        '⚠️ Contiene ${conflicts.join(', ')}, que declaraste como alergia. Consulta al restaurante antes de pedir.',
                        style: const TextStyle(
                          color: AppColors.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  if (!d.orderable) ...[
                    const SizedBox(height: 12),
                    const Tag(
                      'Agotado por ahora',
                      color: AppColors.error,
                      textColor: Colors.white,
                    ),
                  ],
                  if (d.remainingPortions != null && d.orderable) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Quedan ${d.remainingPortions} porciones hoy',
                      style: t.bodySmall,
                    ),
                  ],
                  const SectionHeader('Ingredientes'),
                  if (d.ingredients.isEmpty)
                    Text(
                      'El restaurante no registró ingredientes.',
                      style: t.bodySmall,
                    )
                  else ...[
                    Text(
                      'Toca un ingrediente para quitarlo.',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final ing in d.ingredients)
                          FilterChip(
                            label: Text(
                              sel.removed.contains(ing) ? 'Sin $ing' : ing,
                            ),
                            selected: !sel.removed.contains(ing),
                            showCheckmark: true,
                            onSelected: (keep) => setState(() {
                              final s = {...sel.removed};
                              keep ? s.remove(ing) : s.add(ing);
                              _sel = sel.copyWith(removed: s);
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SectionHeader('Alérgenos y etiquetas'),
                  Text(
                    d.allergens.isEmpty
                        ? 'El restaurante no declaró alérgenos. Esto no garantiza ausencia de contaminación cruzada.'
                        : 'Contiene: ${d.allergens.join(', ')}. No garantizamos ausencia de contaminación cruzada.',
                    style: t.bodyMedium,
                  ),
                  if (d.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in d.tags) Tag(capitalize(tag)),
                      ],
                    ),
                  ],
                  if (d.nutrition != null && r.showsNutrition) ...[
                    const SectionHeader('Información nutricional'),
                    Text(
                      'Valores de referencia de la demostración, por porción.',
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        for (final (k, v) in [
                          ('Kcal', '${d.nutrition!.kcal}'),
                          ('Proteína', '${d.nutrition!.protein} g'),
                          ('Carbos', '${d.nutrition!.carbs} g'),
                          ('Grasa', '${d.nutrition!.fat} g'),
                        ])
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  v,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(k, style: t.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (d.sizes.length > 1) ...[
                    const SectionHeader('Tamaño'),
                    for (final o in d.sizes)
                      _OptionTile(
                        label: o.label,
                        price: o.price,
                        selected: sel.sizeId == o.id,
                        radio: true,
                        onTap: () =>
                            setState(() => _sel = sel.copyWith(sizeId: o.id)),
                      ),
                  ],
                  if (d.sides.isNotEmpty) ...[
                    const SectionHeader('Acompañante'),
                    _OptionTile(
                      label: 'Sin acompañante',
                      price: 0,
                      selected: sel.sideId == null,
                      radio: true,
                      onTap: () =>
                          setState(() => _sel = sel.copyWith(clearSide: true)),
                    ),
                    for (final o in d.sides)
                      _OptionTile(
                        label: o.label,
                        price: o.price,
                        selected: sel.sideId == o.id,
                        radio: true,
                        onTap: () =>
                            setState(() => _sel = sel.copyWith(sideId: o.id)),
                      ),
                  ],
                  if (d.extras.isNotEmpty) ...[
                    const SectionHeader('Extras'),
                    for (final o in d.extras)
                      _OptionTile(
                        key: Key('extra-${o.id}'),
                        label: o.label,
                        price: o.price,
                        selected: sel.extraIds.contains(o.id),
                        onTap: () => setState(() {
                          final s = {...sel.extraIds};
                          s.contains(o.id) ? s.remove(o.id) : s.add(o.id);
                          _sel = sel.copyWith(extraIds: s);
                        }),
                      ),
                  ],
                  const SectionHeader('Nota para el restaurante'),
                  TextField(
                    controller: _note,
                    maxLength: 120,
                    decoration: const InputDecoration(
                      hintText: 'Ej.: salsa aparte, bien tostado…',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text('Cantidad', style: t.titleMedium),
                      const Spacer(),
                      QtyStepper(
                        value: _qty,
                        onChanged: (v) => setState(() => _qty = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: MobileFrame(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(
                  key: const Key('add-to-cart'),
                  label: !d.orderable
                      ? 'Agotado'
                      : editing
                      ? 'Guardar cambios · ${cop(total)}'
                      : 'Agregar · ${cop(total)}',
                  onPressed: !d.orderable
                      ? null
                      : () async {
                          if (editing) {
                            context.read<CartController>().updateLine(
                              widget.editLineId!,
                              selection: sel,
                              qty: _qty,
                              note: _note.text.trim(),
                            );
                            showSnack(context, 'Cambios guardados');
                            context.pop();
                            return;
                          }
                          final ok = await addToCart(
                            context,
                            d,
                            selection: sel,
                            qty: _qty,
                            note: _note.text.trim(),
                          );
                          if (ok && context.mounted && context.canPop()) {
                            context.pop();
                          }
                        },
                ),
                if (editing)
                  TextButton(
                    onPressed: () => context.pop(),
                    child: const Text('Cancelar edición'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    super.key,
    required this.label,
    required this.price,
    required this.selected,
    required this.onTap,
    this.radio = false,
  });

  final String label;
  final int price;
  final bool selected;
  final bool radio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              radio
                  ? (selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off)
                  : (selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank),
              color: selected ? AppColors.success : context.palette.muted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              priceDelta(price),
              style: TextStyle(
                color: context.palette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
