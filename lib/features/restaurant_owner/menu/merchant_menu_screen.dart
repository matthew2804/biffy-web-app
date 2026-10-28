import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';

/// Menú del negocio con búsqueda, filtros y acciones por producto.
class MerchantMenuScreen extends StatefulWidget {
  const MerchantMenuScreen({super.key});

  @override
  State<MerchantMenuScreen> createState() => _MerchantMenuScreenState();
}

/// Estado que filtra el menú por texto y categoría.
class _MerchantMenuScreenState extends State<MerchantMenuScreen> {
  String _q = '';
  String? _cat;

  /// Lista los productos filtrados con interruptores de disponibilidad.
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final t = Theme.of(context).textTheme;
    final branches = catalog.branchesOf(session.businessId!);
    final all = catalog.productsOf(session.businessId!);
    final cats = {for (final d in all) d.category}.toList();
    final list = all
        .where((d) => _cat == null || d.category == _cat)
        .where(
          (d) =>
              _q.isEmpty ||
              normalize(
                '${d.name} ${d.ingredients.join(' ')}',
              ).contains(normalize(_q)),
        )
        .toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-product'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.text,
        onPressed: () => context.push('/negocio/producto/nuevo'),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo producto'),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text('Mi menú', style: t.headlineSmall),
            const SizedBox(height: 8),
            TextField(
              key: const Key('menu-search'),
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                hintText: 'Buscar producto o ingrediente',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SelectPill(
                  label: 'Todas',
                  selected: _cat == null,
                  onTap: () => setState(() => _cat = null),
                ),
                for (final c in cats)
                  SelectPill(
                    label: categoryById(c).label,
                    emoji: categoryById(c).emoji,
                    selected: _cat == c,
                    onTap: () => setState(() => _cat = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              EmptyState(
                emoji: '🍽️',
                title: all.isEmpty
                    ? 'Aún no tienes productos'
                    : 'Sin coincidencias',
                actionLabel: 'Crear producto',
                onAction: () => context.push('/negocio/producto/nuevo'),
              )
            else
              for (final d in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BiffyCard(
                    key: Key('product-${d.id}'),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FoodImage.dish(d, size: 64),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    cop(d.price),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    d.ingredients.join(', '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.bodySmall,
                                  ),
                                  if (branches.length > 1)
                                    Text(
                                      catalog
                                              .restaurantById(d.restaurantId)
                                              ?.branchName ??
                                          '',
                                      style: t.bodySmall,
                                    ),
                                  Wrap(
                                    spacing: 6,
                                    children: [
                                      Tag(
                                        d.active ? 'Publicado' : 'Oculto',
                                        color: d.active
                                            ? AppColors.success.withValues(
                                                alpha: 0.15,
                                              )
                                            : null,
                                      ),
                                      if (d.soldOut)
                                        const Tag(
                                          'Agotado',
                                          color: AppColors.error,
                                          textColor: Colors.white,
                                        ),
                                      if (d.portionLimit != null)
                                        Tag('${d.remainingPortions} porciones'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Disponible'),
                                Switch(
                                  value: d.active,
                                  onChanged: (v) {
                                    d.active = v;
                                    catalog.saveDish(d);
                                  },
                                ),
                              ],
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Agotado'),
                                Switch(
                                  key: Key('soldout-${d.id}'),
                                  value: d.soldOut,
                                  onChanged: (v) => catalog.setSoldOut(d, v),
                                ),
                              ],
                            ),
                            IconButton(
                              tooltip: 'Editar ${d.name}',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () =>
                                  context.push('/negocio/producto/${d.id}'),
                            ),
                            IconButton(
                              key: Key('delete-${d.id}'),
                              tooltip: 'Eliminar ${d.name}',
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.error,
                              ),
                              onPressed: () async {
                                final ok = await showConfirm(
                                  context,
                                  title: '¿Eliminar ${d.name}?',
                                  message:
                                      'Dejará de aparecer en el catálogo de compradores.',
                                  confirm: 'Eliminar',
                                  destructive: true,
                                );
                                if (ok) {
                                  catalog.deleteDish(d.id);
                                  if (context.mounted) {
                                    showSnack(context, 'Producto eliminado');
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
