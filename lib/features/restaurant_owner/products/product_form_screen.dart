import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/session_controller.dart';

/// Fila editable de un tamaño o extra del producto.
class _OptionRow {
  _OptionRow([String label = '', int price = 0, this.id])
    : label = TextEditingController(text: label),
      price = TextEditingController(text: price == 0 ? '' : '$price');
  final TextEditingController label;
  final TextEditingController price;
  final String? id;
}

/// Crear o editar un producto; al guardar se publica en el catálogo del comprador.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, required this.id});
  final String id;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

/// Estado del formulario que crea o edita un producto del menú.
class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  late final CatalogController _catalog = context.read<CatalogController>();
  late final String _biz = context.read<SessionController>().businessId!;
  late final Dish? _orig = widget.id == 'nuevo'
      ? null
      : _catalog.dishById(widget.id);
  late final _name = TextEditingController(text: _orig?.name);
  late final _desc = TextEditingController(text: _orig?.description);
  late final _section = TextEditingController(text: _orig?.section);
  late final _ingredients = TextEditingController(
    text: _orig?.ingredients.join(', '),
  );
  late final _price = TextEditingController(
    text: _orig == null ? '' : '${_orig.price}',
  );
  late final _prep = TextEditingController(text: '${_orig?.prepMin ?? 15}');
  late final _limit = TextEditingController(
    text: _orig?.portionLimit?.toString() ?? '',
  );
  late final _kcal = TextEditingController(
    text: _orig?.nutrition?.kcal.toString() ?? '',
  );
  late final _protein = TextEditingController(
    text: _orig?.nutrition?.protein.toString() ?? '',
  );
  late final _carbs = TextEditingController(
    text: _orig?.nutrition?.carbs.toString() ?? '',
  );
  late final _fat = TextEditingController(
    text: _orig?.nutrition?.fat.toString() ?? '',
  );

  /// Foto elegida en esta sesión (aún no subida).
  Uint8List? _photoBytes;

  /// URL o asset actual de la foto.
  late String? _photoUrl = _orig?.imageAsset;

  /// Evita doble envío mientras se guarda el producto.
  bool _saving = false;
  late String _category =
      _orig?.category ?? _catalog.businessById(_biz)?.cuisine ?? 'sandwich';
  late String _branch =
      _orig?.restaurantId ?? _catalog.branchesOf(_biz).first.id;
  late Set<String> _allergens = {...?_orig?.allergens};
  late Set<String> _tags = {...?_orig?.tags};
  late bool _active = _orig?.active ?? true;
  late bool _soldOut = _orig?.soldOut ?? false;
  late final List<_OptionRow> _sizes = [
    for (final o in _orig?.sizes ?? const <DishOption>[])
      _OptionRow(o.label, o.price, o.id),
  ];
  late final List<_OptionRow> _extras = [
    for (final o in _orig?.extras ?? const <DishOption>[])
      _OptionRow(o.label, o.price, o.id),
  ];

  /// Fuerza la carga del producto original y del negocio.
  @override
  void initState() {
    super.initState();
    _orig;
    _biz;
  }

  /// Libera todos los controladores del formulario.
  @override
  void dispose() {
    for (final c in [
      _name,
      _desc,
      _section,
      _ingredients,
      _price,
      _prep,
      _limit,
      _kcal,
      _protein,
      _carbs,
      _fat,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Valida que el campo obligatorio no esté vacío.
  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  /// Convierte las filas editadas en opciones del plato.
  List<DishOption> _options(List<_OptionRow> rows, String prefix) => [
    for (final (i, r) in rows.indexed)
      if (r.label.text.trim().isNotEmpty)
        DishOption(
          r.id ?? '$prefix-${DateTime.now().microsecondsSinceEpoch}-$i',
          r.label.text.trim(),
          int.tryParse(r.price.text) ?? 0,
        ),
  ];

  /// Abre la galería y guarda la foto elegida en memoria.
  Future<void> _pickPhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 75,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() => _photoBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'No pudimos abrir la galería.', error: true);
    }
  }

  /// Valida, arma el plato y lo publica en el catálogo compartido.
  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);

    // Si hay foto nueva, se sube antes de guardar el plato.
    var image = _photoUrl;
    if (_photoBytes != null) {
      final url = await _catalog.uploadDishPhoto(
        businessId: _biz,
        bytes: _photoBytes!,
      );
      if (url == null) {
        if (!mounted) return;
        showSnack(context, 'No pudimos subir la foto.', error: true);
        setState(() => _saving = false);
        return;
      }
      image = url;
    }

    final hasNutrition = [
      _kcal,
      _protein,
      _carbs,
      _fat,
    ].every((c) => c.text.trim().isNotEmpty);
    final id = _orig?.id ?? _catalog.newDishId();
    final dish = Dish(
      id: id,
      restaurantId: _branch,
      name: _name.text.trim(),
      description: _desc.text.trim(),
      price: int.parse(_price.text),
      emoji: categoryById(_category).emoji,
      category: _category,
      section: _section.text.trim().isEmpty
          ? categoryById(_category).label
          : _section.text.trim(),
      prepMin: int.parse(_prep.text),
      rating: _orig?.rating ?? 4.5,
      ingredients: _ingredients.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
      allergens: _allergens.toList(),
      tags: _tags.toList(),
      nutrition: hasNutrition
          ? Nutrition(
              kcal: int.parse(_kcal.text),
              protein: int.parse(_protein.text),
              carbs: int.parse(_carbs.text),
              fat: int.parse(_fat.text),
            )
          : null,
      sizes: _options(_sizes, '$id-s'),
      sides: _orig?.sides ?? const [],
      extras: _options(_extras, '$id-x'),
      popular: _orig?.popular ?? false,
      featured: _orig?.featured ?? false,
      active: _active,
      soldOut: _soldOut,
      portionLimit: int.tryParse(_limit.text),
      soldToday: _orig?.soldToday ?? 0,
      imageAsset: image,
    );
    try {
      await _catalog.saveDish(dish);
    } on Object {
      if (!mounted) return;
      showSnack(
        context,
        'No pudimos guardar el producto. Revisa tu conexión.',
        error: true,
      );
      setState(() => _saving = false);
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showSnack(
      context,
      _orig == null ? 'Producto creado y publicado' : 'Producto actualizado',
    );
    context.canPop() ? context.pop() : context.go('/negocio/menu');
  }

  /// Editor de tamaños o extras con botón para agregar filas.
  Widget _optionsEditor(String title, List<_OptionRow> rows, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          action: 'Agregar',
          onAction: () => setState(() => rows.add(_OptionRow())),
        ),
        if (rows.isEmpty)
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: r.label,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: r.price,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'-?\d*')),
                    ],
                    decoration: const InputDecoration(labelText: r'+ Precio $'),
                  ),
                ),
                IconButton(
                  tooltip: 'Quitar opción',
                  icon: const Icon(Icons.close, color: AppColors.error),
                  onPressed: () => setState(() => rows.remove(r)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Construye el formulario completo con categorías, alérgenos y nutrición.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (widget.id != 'nuevo' && _orig == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🍽️',
          title: 'Producto no encontrado',
          actionLabel: 'Volver al menú',
          onAction: () => context.go('/negocio/menu'),
        ),
      );
    }
    final branches = _catalog.branchesOf(_biz);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Scaffold(
      appBar: AppBar(
        title: Text(_orig == null ? 'Nuevo producto' : 'Editar producto'),
      ),
      body: MobileFrame(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              TextFormField(
                key: const Key('p-name'),
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre *'),
                validator: _req,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Categoría *'),
                items: [
                  for (final c in kCategories)
                    DropdownMenuItem(
                      value: c.id,
                      child: Text('${c.emoji} ${c.label}'),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              if (branches.length > 1) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _branch,
                  decoration: const InputDecoration(labelText: 'Sede'),
                  items: [
                    for (final b in branches)
                      DropdownMenuItem(value: b.id, child: Text(b.branchName)),
                  ],
                  onChanged: (v) => setState(() => _branch = v ?? _branch),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _section,
                decoration: const InputDecoration(
                  labelText: 'Sección del menú',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('p-desc'),
                controller: _desc,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción *'),
                validator: _req,
              ),
              const SizedBox(height: 12),
              Text(
                'Foto del plato',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: _photoBytes != null
                          ? Image.memory(_photoBytes!, fit: BoxFit.cover)
                          : _photoUrl != null
                          ? catalogImage(
                              _photoUrl!,
                              width: 72,
                              height: 72,
                              fallback: Text(
                                categoryById(_category).emoji,
                                style: const TextStyle(fontSize: 28),
                              ),
                            )
                          : Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Text(
                                categoryById(_category).emoji,
                                style: const TextStyle(fontSize: 28),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('p-photo'),
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: Text(
                        _photoBytes == null && _photoUrl == null
                            ? 'Agregar foto'
                            : 'Cambiar foto',
                      ),
                    ),
                  ),
                  if (_photoBytes != null || _photoUrl != null)
                    IconButton(
                      tooltip: 'Quitar foto',
                      onPressed: () => setState(() {
                        _photoBytes = null;
                        _photoUrl = null;
                      }),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ingredients,
                decoration: const InputDecoration(
                  labelText: 'Ingredientes (separados por coma)',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const Key('p-price'),
                      controller: _price,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: const InputDecoration(
                        labelText: r'Precio COP *',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1000) return 'Mínimo \$1.000';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _prep,
                      keyboardType: TextInputType.number,
                      inputFormatters: digits,
                      decoration: const InputDecoration(
                        labelText: 'Preparación (min) *',
                      ),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1 || n > 120) return '1 a 120 min';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SectionHeader('Alérgenos'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in kAllergyOptions)
                    SelectPill(
                      label: capitalize(a),
                      selected: _allergens.contains(a),
                      onTap: () => setState(
                        () => _allergens = _allergens.contains(a)
                            ? ({..._allergens}..remove(a))
                            : {..._allergens, a},
                      ),
                    ),
                ],
              ),
              const SectionHeader('Estilo de vida'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in kLifestyleOptions)
                    SelectPill(
                      label: capitalize(s),
                      selected: _tags.contains(s),
                      onTap: () => setState(
                        () => _tags = _tags.contains(s)
                            ? ({..._tags}..remove(s))
                            : {..._tags, s},
                      ),
                    ),
                ],
              ),
              _optionsEditor(
                'Tamaños',
                _sizes,
                'Opcional. El primero es el predeterminado; usa precio negativo para tamaños menores.',
              ),
              _optionsEditor(
                'Extras',
                _extras,
                'Opcional. Ej.: Extra queso · 3000',
              ),
              const SectionHeader('Disponibilidad'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Publicado en el menú'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Agotado'),
                value: _soldOut,
                onChanged: (v) => setState(() => _soldOut = v),
              ),
              TextFormField(
                controller: _limit,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: const InputDecoration(
                  labelText: 'Límite de porciones por día (opcional)',
                ),
              ),
              const SectionHeader('Información nutricional (opcional)'),
              Text(
                'Completa los cuatro campos o déjalos vacíos.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final (c, l) in [
                    (_kcal, 'Kcal'),
                    (_protein, 'Prot. g'),
                    (_carbs, 'Carb. g'),
                    (_fat, 'Grasa g'),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: TextFormField(
                          controller: c,
                          keyboardType: TextInputType.number,
                          inputFormatters: digits,
                          decoration: InputDecoration(labelText: l),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                key: const Key('p-save'),
                label: 'Guardar producto',
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
