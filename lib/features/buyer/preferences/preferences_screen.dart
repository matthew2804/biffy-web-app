import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../shared/state/session_controller.dart';

/// Encuesta opcional de 3 pasos: gustos, estilo de vida/alergias, presupuesto.
class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  int _step = 0;
  late Preferences _p = context.read<SessionController>().prefs;

  Set<String> _toggle(Set<String> s, String v) =>
      s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionController>();
    final t = Theme.of(context).textTheme;
    final titles = [
      'Tus gustos',
      'Estilo de vida y alergias',
      'Presupuesto y universidad',
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Paso ${_step + 1} de 3 · ${titles[_step]}')),
      // Botones fijos abajo: siempre visibles aunque la lista sea larga.
      bottomNavigationBar: MobileFrame(
        child: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: SecondaryButton(
                    label: 'Atrás',
                    onPressed: () => setState(() => _step--),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  key: const Key('prefs-next'),
                  label: _step < 2 ? 'Siguiente' : 'Guardar preferencias',
                  onPressed: () {
                    if (_step < 2) {
                      setState(() => _step++);
                      return;
                    }
                    final awarded = session.savePreferences(_p);
                    showSnack(
                      context,
                      awarded > 0
                          ? '¡Preferencias guardadas! +$awarded Gotas 💧'
                          : session.isLoggedIn
                          ? 'Preferencias actualizadas'
                          : 'Preferencias guardadas. Inicia sesión para ganar $kSurveyGotas Gotas.',
                    );
                    context.canPop() ? context.pop() : context.go('/');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 3,
              color: AppColors.primary,
              backgroundColor: context.palette.border,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 16),
            if (_step == 0) ...[
              Text('¿Qué te gusta comer?', style: t.titleLarge),
              Text('Selección múltiple. Es opcional.', style: t.bodySmall),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.25,
                children: [
                  for (final c in kCategories)
                    _TasteTile(
                      key: Key('like-${c.id}'),
                      category: c,
                      selected: _p.likes.contains(c.id),
                      onTap: () => setState(
                        () => _p = _p.copyWith(likes: _toggle(_p.likes, c.id)),
                      ),
                    ),
                ],
              ),
            ],
            if (_step == 1) ...[
              Text('Estilo de vida', style: t.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in kLifestyleOptions)
                    SelectPill(
                      label: capitalize(s),
                      emoji: kOptionEmoji[s],
                      selected: _p.lifestyle.contains(s),
                      onTap: () => setState(
                        () => _p = _p.copyWith(
                          lifestyle: _toggle(_p.lifestyle, s),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text('Alergias', style: t.titleLarge),
              Text(
                'Te advertiremos y podrás excluir estos alérgenos.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in kAllergyOptions)
                    SelectPill(
                      key: Key('allergy-$a'),
                      label: capitalize(a),
                      emoji: kOptionEmoji[a],
                      selected: _p.allergies.contains(a),
                      onTap: () => setState(
                        () => _p = _p.copyWith(
                          allergies: _toggle(_p.allergies, a),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (_step == 2) ...[
              Text(
                'Presupuesto por comida: ${cop(_p.budget)}',
                style: t.titleLarge,
              ),
              Slider(
                key: const Key('budget-slider'),
                min: 5000,
                max: 50000,
                divisions: 45,
                value: _p.budget.clamp(5000, 50000).toDouble(),
                label: cop(_p.budget),
                onChanged: (v) => setState(
                  () => _p = _p.copyWith(budget: (v / 1000).round() * 1000),
                ),
              ),
              const SizedBox(height: 12),
              Text('Universidad (opcional)', style: t.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SelectPill(
                    label: 'Ninguna',
                    selected: _p.universityId == null,
                    onTap: () =>
                        setState(() => _p = _p.copyWith(clearUniversity: true)),
                  ),
                  for (final u in kUniversities)
                    SelectPill(
                      label: u.name,
                      selected: _p.universityId == u.id,
                      onTap: () =>
                          setState(() => _p = _p.copyWith(universityId: u.id)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Para descuentos de campus, verifica tu correo universitario (simulado) en la sección Campus.',
                style: t.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tarjeta con foto para elegir una categoría que te gusta; borde amarillo si está elegida.
class _TasteTile extends StatelessWidget {
  const _TasteTile({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final FoodCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: category.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.15)
                : p.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppColors.primary : p.border,
              width: 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (_, box) => FoodImage(
                    emoji: category.emoji,
                    asset: category.imageAsset,
                    size: box.maxHeight,
                    width: box.maxWidth,
                    radius: 12,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
