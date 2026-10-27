import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../domain/assistant.dart';
import '../../../domain/recommendation.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';
import 'recommendation_input.dart';

class _Msg {
  const _Msg(this.text, this.fromUser, [this.dishes = const []]);
  final String text;
  final bool fromUser;
  final List<Dish> dishes;
}

const _suggestions = [
  'Algo barato por menos de 15 mil',
  'Pizza vegetariana',
  '¿Qué contiene el Bowl Proteico?',
  'Algo saludable',
  '¿Qué me recomiendas para mi descanso de 20 minutos?',
];

class AiScreen extends StatefulWidget {
  const AiScreen({super.key});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  RecommendationMode _mode = RecommendationMode.tastes;
  int _seed = 1;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Msg> _messages = [
    const _Msg(
      'Hola, soy Biffy AI 🐝. Respondo con los datos locales de la demo (sin IA conectada). Pregúntame por presupuesto, ingredientes o tiempo.',
      false,
    ),
  ];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _ask(String q) {
    if (q.trim().isEmpty) return;
    final reply = answer(q, buildRecommendationInput(context));
    setState(() {
      _messages.add(_Msg(q.trim(), true));
      _messages.add(_Msg(reply.text, false, reply.dishes));
    });
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<SessionController>();
    context.watch<CatalogController>();
    context.watch<OrderService>();
    final t = Theme.of(context).textTheme;
    final input = buildRecommendationInput(context, seed: _seed);
    final recs = recommend(input, mode: _mode);
    final noProfile = input.prefs.isEmpty && input.historyDishIds.isEmpty;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  Row(
                    children: [
                      const BeeLogo(size: 40),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Biffy AI', style: t.headlineSmall)),
                    ],
                  ),
                  Text(
                    'Recomendaciones locales basadas en reglas: alergias, gustos, historial, presupuesto, tiempo y campus.',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final m in RecommendationMode.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SelectPill(
                              key: Key('mode-${m.name}'),
                              label: m.label,
                              emoji: m.emoji,
                              selected: _mode == m,
                              onTap: () => setState(() => _mode = m),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (noProfile && _mode == RecommendationMode.tastes)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Sin preferencias ni historial te mostramos lo más popular de tu zona.',
                        style: t.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (recs.isEmpty)
                    EmptyState(
                      emoji: _mode == RecommendationMode.favorites
                          ? '❤️'
                          : '🤷',
                      title: _mode == RecommendationMode.favorites
                          ? 'Aún no tienes favoritos disponibles en tu zona'
                          : 'No hay opciones compatibles en tu zona',
                      actionLabel: 'Explorar',
                      onAction: () => context.go('/explorar'),
                    )
                  else
                    for (final r in recs) _RecCard(rec: r),
                  if (_mode == RecommendationMode.surprise)
                    TextButton.icon(
                      onPressed: () => setState(() => _seed++),
                      icon: const Icon(Icons.casino_outlined),
                      label: const Text('Otra sorpresa'),
                    ),
                  const SectionHeader('Pregúntale a Biffy'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final s in _suggestions)
                        ActionChip(label: Text(s), onPressed: () => _ask(s)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final m in _messages) _Bubble(msg: m),
                ],
              ),
            ),
            Container(
              color: context.palette.surface,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('ai-input'),
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: 'Escribe tu antojo…',
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('ai-send'),
                    tooltip: 'Enviar',
                    icon: const Icon(Icons.send, color: AppColors.secondary),
                    onPressed: () => _ask(_input.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecCard extends StatelessWidget {
  const _RecCard({required this.rec});
  final Recommendation rec;

  @override
  Widget build(BuildContext context) {
    final catalog = context.read<CatalogController>();
    final r = catalog.restaurantById(rec.dish.restaurantId);
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BiffyCard(
        key: Key('rec-${rec.dish.id}'),
        onTap: () => context.push('/plato/${rec.dish.id}'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FoodImage.dish(rec.dish, size: 72),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rec.dish.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '${r?.name ?? ''} · ${cop(rec.dish.price)}',
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  for (final reason in rec.reasons)
                    Text('• $reason', style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Tag(
                    'Coincidencia estimada ${rec.match}% · prototipo',
                    color: AppColors.success.withValues(alpha: 0.15),
                    textColor: AppColors.success,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg});
  final _Msg msg;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Align(
      alignment: msg.fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: msg.fromUser ? AppColors.primary : p.surface,
          borderRadius: BorderRadius.circular(16),
          border: msg.fromUser ? null : Border.all(color: p.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              msg.text,
              style: TextStyle(color: msg.fromUser ? AppColors.text : p.text),
            ),
            for (final d in msg.dishes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ActionChip(
                  avatar: FoodImage.dish(d, size: 24, radius: 12),
                  label: Text('${d.name} · ${cop(d.price)}'),
                  onPressed: () => context.push('/plato/${d.id}'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
