import 'package:flutter/material.dart';

import '../../../core/widgets/ui.dart';

const _faq = [
  (
    '¿Biffy cobra dinero real?',
    'No. Este sprint es una demostración: los pedidos y pagos son simulados y no se realizan cobros.',
  ),
  (
    '¿Cómo funciona el código de entrega?',
    'Al confirmar tu pedido ves un código de 4 dígitos. Dáselo al repartidor solo cuando recibas la comida.',
  ),
  (
    '¿Puedo cancelar un pedido?',
    'Sí, mientras el restaurante no lo haya aceptado. Después ya está en preparación.',
  ),
  (
    '¿Qué son las Gotas Biffy?',
    'Puntos de demostración. Los ganas al iniciar sesión, completar preferencias y recibir pedidos.',
  ),
  (
    '¿Por qué no veo un restaurante?',
    'Solo mostramos restaurantes que entregan en tu punto (radio de cobertura y repartidores cerca).',
  ),
];

/// Respuestas locales de demostración según el tema elegido.
String supportReply(String topic) => switch (topic) {
  'Pedido' =>
    'Revisa el estado en «Mis pedidos». Si sigue pendiente, puedes cancelarlo sin costo.',
  'Pagos' =>
    'En la demo no se procesan pagos, así que no hay cobros que revisar.',
  'Cuenta' => 'Puedes editar tus datos en Perfil › Información personal.',
  _ =>
    'Gracias por escribirnos. Revisaremos tu comentario en el próximo sprint.',
};

/// Pantalla de ayuda con preguntas frecuentes y mensajes simulados.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  /// Crea el estado del formulario de soporte.
  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

/// Estado con el hilo de mensajes y el tema elegido.
class _SupportScreenState extends State<SupportScreen> {
  final _form = GlobalKey<FormState>();
  final _msg = TextEditingController();
  String _topic = 'Pedido';
  final List<(String, String)> _thread = [];

  /// Libera el controlador del mensaje.
  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  /// Construye las FAQ, el formulario y el hilo de respuestas.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ayuda y soporte')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text('Preguntas frecuentes', style: t.titleLarge),
            const SizedBox(height: 8),
            BiffyCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final (q, a) in _faq)
                    ExpansionTile(
                      title: Text(
                        q,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [Text(a)],
                    ),
                ],
              ),
            ),
            const SectionHeader('Escríbenos'),
            Text(
              'Asistente local de demostración: las respuestas son automáticas y el mensaje no sale del teléfono. '
              'Las llamadas y el chat en vivo llegarán en otro sprint.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            Form(
              key: _form,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _topic,
                    decoration: const InputDecoration(labelText: 'Tema'),
                    items: [
                      for (final x in ['Pedido', 'Pagos', 'Cuenta', 'Otro'])
                        DropdownMenuItem(value: x, child: Text(x)),
                    ],
                    onChanged: (v) => setState(() => _topic = v ?? 'Pedido'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('support-message'),
                    controller: _msg,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Mensaje'),
                    validator: (v) => (v == null || v.trim().length < 10)
                        ? 'Cuéntanos un poco más (mín. 10 caracteres)'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    key: const Key('support-send'),
                    label: 'Enviar',
                    onPressed: () {
                      if (!_form.currentState!.validate()) return;
                      setState(() {
                        _thread.add(('Tú', _msg.text.trim()));
                        _thread.add((
                          'Biffy (respuesta automática demo)',
                          supportReply(_topic),
                        ));
                      });
                      _msg.clear();
                    },
                  ),
                ],
              ),
            ),
            for (final (who, text) in _thread)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: BiffyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        who,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(text),
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
