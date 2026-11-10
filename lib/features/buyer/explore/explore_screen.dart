import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/catalog_cards.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../domain/catalog_rules.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';

/// Buscador de platos y restaurantes con filtros rápidos y avanzados.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({
    super.key,
    this.category,
    this.focus = false,
    this.restaurantsView = false,
  });
  final String? category;
  final bool focus;
  final bool restaurantsView;

  /// Crea el estado del buscador.
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

/// Estado con la búsqueda, el foco y los filtros aplicados.
class _ExploreScreenState extends State<ExploreScreen> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  DishFilters _filters = DishFilters.none;

  /// Aplica los parámetros de la ruta al abrir la pantalla.
  @override
  void initState() {
    super.initState();
    _applyParams();
  }

  /// Reaplica los parámetros cuando cambia la ruta.
  @override
  void didUpdateWidget(covariant ExploreScreen old) {
    super.didUpdateWidget(old);
    if (old.category != widget.category || old.focus != widget.focus) {
      _applyParams();
    }
  }

  /// Lee la categoría y el foco recibidos por parámetros.
  void _applyParams() {
    if (widget.category != null) {
      _filters = _filters.copyWith(categories: {widget.category!});
    }
    if (widget.focus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  /// Libera el buscador y su nodo de foco.
  @override
  void dispose() {
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Reemplaza los filtros activos.
  void _set(DishFilters f) => setState(() => _filters = f);

  /// Filtra los platos alcanzables con los filtros y preferencias actuales.
  List<Dish> _results(CatalogController catalog, SessionController session) =>
      filterDishes(
        catalog.reachableDishes,
        _filters,
        catalog.filterContext(
          allergies: session.prefs.allergies,
          universityId: session.universityId,
        ),
      );

  /// Construye el buscador, los filtros y los resultados.
  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogController>();
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    final results = _results(catalog, session);
    final browsing = _filters.isEmpty;
    final restaurantIds = results.map((d) => d.restaurantId).toSet();
    final q = normalize(_filters.query);
    final restaurants = catalog.topRatedRestaurants
        .where(
          (r) =>
              browsing ||
              restaurantIds.contains(r.id) ||
              (q.isNotEmpty && normalize(r.name).contains(q)),
        )
        .toList();

    final quick = <(String, bool, DishFilters Function(bool))>[
      (
        '🎓 Campus',
        _filters.campusOnly,
        (v) => _filters.copyWith(campusOnly: v),
      ),
      (
        '🥦 Nutrición',
        _filters.nutritionOnly,
        (v) => _filters.copyWith(nutritionOnly: v),
      ),
      ('⚡ < 15 min', _filters.fastOnly, (v) => _filters.copyWith(fastOnly: v)),
      (
        '💸 < ${cop(15000)}',
        _filters.cheapOnly,
        (v) => _filters.copyWith(cheapOnly: v),
      ),
      ('⭐ 4,7+', _filters.topRated, (v) => _filters.copyWith(topRated: v)),
      ('🟢 Abierto', _filters.openOnly, (v) => _filters.copyWith(openOnly: v)),
      (
        '🚫 Mis alérgenos',
        _filters.excludeAllergens,
        (v) => _filters.copyWith(excludeAllergens: v),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Explorar', style: t.headlineSmall),
                        ),
                        TextButton.icon(
                          onPressed: () => showDeliveryPointSheet(context),
                          icon: const Icon(
                            Icons.location_on,
                            color: AppColors.primary,
                          ),
                          label: Text(
                            session.point.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('explore-search'),
                            controller: _search,
                            focusNode: _focus,
                            textInputAction: TextInputAction.search,
                            onChanged: (v) => _set(_filters.copyWith(query: v)),
                            decoration: InputDecoration(
                              hintText: 'Busca platos o restaurantes',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Borrar búsqueda',
                                      icon: const Icon(Icons.close),
                                      onPressed: () {
                                        _search.clear();
                                        _set(_filters.copyWith(query: ''));
                                      },
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        RoundIconButton(
                          key: const Key('open-filters'),
                          icon: Icons.tune,
                          tooltip: 'Filtros',
                          color: _filters.activeCount > 0
                              ? AppColors.primary
                              : null,
                          iconColor: _filters.activeCount > 0
                              ? AppColors.text
                              : null,
                          badge: _filters.activeCount,
                          onTap: () => _openFilters(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final (label, on, make) in quick)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SelectPill(
                            label: label,
                            selected: on,
                            onTap: () {
                              if (label.contains('alérgenos') &&
                                  !on &&
                                  session.prefs.allergies.isEmpty) {
                                showSnack(
                                  context,
                                  'No has declarado alergias. Puedes hacerlo en Preferencias.',
                                );
                              }
                              _set(make(!on));
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final c in kCategories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: SelectPill(
                            key: Key('explore-cat-${c.id}'),
                            label: c.label,
                            emoji: c.emoji,
                            selected: _filters.categories.contains(c.id),
                            onTap: () {
                              final s = {..._filters.categories};
                              s.contains(c.id) ? s.remove(c.id) : s.add(c.id);
                              _set(_filters.copyWith(categories: s));
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (catalog.reachableRestaurants.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  emoji: '📍',
                  title: 'Sin cobertura en ${session.point.name}',
                  body: 'Ningún restaurante entrega en este punto ahora mismo.',
                  actionLabel: 'Cambiar punto de entrega',
                  onAction: () => showDeliveryPointSheet(context),
                ),
              )
            else if (browsing && !widget.restaurantsView) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SectionHeader('Populares'),
                ),
              ),
              SliverToBoxAdapter(
                child: HCarousel(
                  height: 236,
                  children: [
                    for (final d in catalog.popularDishes) DishCard(d),
                  ],
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SectionHeader('Restaurantes mejor valorados'),
                      for (final r in restaurants)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: RestaurantCard(r),
                        ),
                      SectionHeader('Todos los platos (${results.length})'),
                    ],
                  ),
                ),
              ),
              _dishList(results),
            ] else if (browsing && widget.restaurantsView) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SectionHeader('Restaurantes que entregan aquí'),
                      for (final r in restaurants)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: RestaurantCard(r),
                        ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${results.length} ${results.length == 1 ? 'resultado' : 'resultados'}',
                          key: const Key('results-count'),
                          style: t.titleMedium,
                        ),
                      ),
                      if (_filters.activeCount > 0)
                        TextButton(
                          onPressed: () => _set(_filters.cleared()),
                          child: const Text('Limpiar filtros'),
                        ),
                    ],
                  ),
                ),
              ),
              if (results.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    emoji: '🔍',
                    title: 'No encontramos coincidencias',
                    body: 'Prueba con otra búsqueda o quita algunos filtros.',
                    actionLabel: 'Limpiar filtros',
                    onAction: () {
                      _search.clear();
                      _set(DishFilters.none);
                    },
                  ),
                )
              else ...[
                if (restaurants.isNotEmpty)
                  SliverToBoxAdapter(
                    child: HCarousel(
                      height: kRestaurantCardHeight,
                      children: [
                        for (final r in restaurants)
                          RestaurantCard(r, width: 290),
                      ],
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                _dishList(results),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  /// Construye la lista de platos como sliver.
  Widget _dishList(List<Dish> dishes) => SliverPadding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    sliver: SliverList.builder(
      itemCount: dishes.length,
      itemBuilder: (_, i) => DishTile(dishes[i]),
    ),
  );

  /// Abre la hoja de filtros avanzados y aplica el resultado.
  Future<void> _openFilters(BuildContext context) async {
    final catalog = context.read<CatalogController>();
    final session = context.read<SessionController>();
    final result = await showModalBottomSheet<DishFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        initial: _filters,
        count: (f) => filterDishes(
          catalog.reachableDishes,
          f,
          catalog.filterContext(
            allergies: session.prefs.allergies,
            universityId: session.universityId,
          ),
        ).length,
      ),
    );
    if (result != null) _set(result);
  }
}

/// Hoja inferior con todos los filtros del catálogo.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial, required this.count});
  final DishFilters initial;
  final int Function(DishFilters) count;

  /// Crea el estado de la hoja de filtros.
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

/// Estado con la copia editable de los filtros.
class _FilterSheetState extends State<_FilterSheet> {
  late DishFilters f = widget.initial;

  /// Construye los controles de filtros y el botón de aplicar.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final price = f.maxPrice ?? DishFilters.maxPriceMax;
    final n = widget.count(f);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Filtros', style: t.titleLarge)),
                      TextButton(
                        key: const Key('filters-clear'),
                        onPressed: () => setState(() => f = f.cleared()),
                        child: const Text('Limpiar todo'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Precio máximo: ${f.maxPrice == null ? 'sin límite' : cop(price)}',
                    style: t.titleSmall,
                  ),
                  Slider(
                    key: const Key('price-slider'),
                    min: DishFilters.maxPriceMin.toDouble(),
                    max: DishFilters.maxPriceMax.toDouble(),
                    divisions:
                        (DishFilters.maxPriceMax - DishFilters.maxPriceMin) ~/
                        1000,
                    value: price.toDouble(),
                    label: cop(price),
                    onChanged: (v) =>
                        setState(() => f = f.copyWith(maxPrice: v.round())),
                  ),
                  if (f.maxPrice != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => f = f.copyWith(clearMaxPrice: true)),
                        child: const Text('Quitar límite de precio'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text('Estilo de vida', style: t.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in kLifestyleOptions)
                        SelectPill(
                          label: capitalize(s),
                          emoji: kOptionEmoji[s],
                          selected: f.lifestyle.contains(s),
                          onTap: () => setState(() {
                            final set = {...f.lifestyle};
                            set.contains(s) ? set.remove(s) : set.add(s);
                            f = f.copyWith(lifestyle: set);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Categorías', style: t.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in kCategories)
                        SelectPill(
                          label: c.label,
                          emoji: c.emoji,
                          selected: f.categories.contains(c.id),
                          onTap: () => setState(() {
                            final set = {...f.categories};
                            set.contains(c.id)
                                ? set.remove(c.id)
                                : set.add(c.id);
                            f = f.copyWith(categories: set);
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Solo restaurantes abiertos'),
                    value: f.openOnly,
                    onChanged: (v) =>
                        setState(() => f = f.copyWith(openOnly: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Excluir mis alérgenos'),
                    value: f.excludeAllergens,
                    onChanged: (v) =>
                        setState(() => f = f.copyWith(excludeAllergens: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Valoración 4,7 o más'),
                    value: f.topRated,
                    onChanged: (v) =>
                        setState(() => f = f.copyWith(topRated: v)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: PrimaryButton(
                key: const Key('filters-apply'),
                label: 'Ver $n ${n == 1 ? 'resultado' : 'resultados'}',
                onPressed: () => Navigator.pop(context, f),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
