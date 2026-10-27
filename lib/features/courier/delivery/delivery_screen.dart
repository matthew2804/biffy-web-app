import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/catalog.dart';
import '../../../data/mock/seed_users.dart';
import '../../../data/models/order.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

/// Entrega: requiere el código correcto y una foto de evidencia local.
class DeliveryScreen extends StatefulWidget {
  const DeliveryScreen({super.key, required this.id});
  final String id;

  @override
  State<DeliveryScreen> createState() => _DeliveryScreenState();
}

class _DeliveryScreenState extends State<DeliveryScreen> {
  final _code = TextEditingController();
  String? _evidence;
  Uint8List? _bytes;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final f = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 70,
      );
      if (f == null) return;
      final bytes = await f.readAsBytes();
      setState(() {
        _bytes = bytes;
        _evidence = 'Foto local: ${f.name.isEmpty ? 'evidencia.jpg' : f.name}';
      });
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'La cámara o galería no está disponible en este entorno. Usa la evidencia de demostración.',
          error: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderService>();
    final session = context.watch<SessionController>();
    final t = Theme.of(context).textTheme;
    final o = orders.byId(widget.id);
    if (o == null || o.courierId != session.user?.id) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🔎',
          title: 'Pedido no encontrado o no asignado a ti',
          actionLabel: 'Volver al inicio',
          onAction: () => context.go('/repartidor'),
        ),
      );
    }
    if (o.status != OrderStatus.onTheWay) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: o.status == OrderStatus.delivered ? '✅' : '📦',
          title: o.status == OrderStatus.delivered
              ? 'Pedido ${o.id} entregado'
              : 'Primero confirma la recogida',
          actionLabel: o.status == OrderStatus.delivered
              ? 'Volver al inicio'
              : 'Ir a la recogida',
          onAction: () => context.go(
            o.status == OrderStatus.delivered
                ? '/repartidor'
                : '/repartidor/recogida/${o.id}',
          ),
        ),
      );
    }
    final notes = [
      if (o.address.reference.isNotEmpty) 'Referencia: ${o.address.reference}',
      if (o.restaurantNote.isNotEmpty) o.restaurantNote,
    ];
    return Scaffold(
      appBar: AppBar(title: Text('Entregar ${o.id}')),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            Text(
              'Paso 2 de 2 · Entrega',
              style: t.titleSmall?.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 8),
            BiffyCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PersonAvatar(
                        name: o.buyerName,
                        asset: kDemoAvatars[o.buyerId],
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(o.buyerName, style: t.titleMedium)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${o.address.label} · ${o.address.full}'),
                  for (final n in notes) Text('📝 $n', style: t.bodySmall),
                  const Divider(height: 20),
                  for (final l in o.lines) Text('${l.qty}× ${l.name}'),
                  const SizedBox(height: 8),
                  InfoRow('Método de pago', o.payment.label),
                  if (o.payment == PaymentMethod.cash)
                    InfoRow(
                      'Cobrar en efectivo (simulado)',
                      cop(o.total),
                      bold: true,
                      valueColor: AppColors.error,
                    ),
                ],
              ),
            ),
            const SectionHeader('Código del cliente'),
            TextField(
              key: const Key('delivery-code-input'),
              controller: _code,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
                letterSpacing: 12,
                fontWeight: FontWeight.w800,
              ),
              decoration: InputDecoration(hintText: '••••', errorText: _error),
              onChanged: (_) => setState(() => _error = null),
            ),
            Text(
              'El cliente lo ve en su pantalla de seguimiento.',
              style: t.bodySmall,
            ),
            const SectionHeader('Foto de evidencia (obligatoria)'),
            BiffyCard(
              key: const Key('evidence-card'),
              border: Border.all(
                color: _evidence == null
                    ? context.palette.border
                    : AppColors.success,
                width: 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_bytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _bytes!,
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    )
                  else if (_evidence != null)
                    const Text('🖼️', style: TextStyle(fontSize: 48)),
                  Text(
                    _evidence ?? 'Aún no hay evidencia',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => _pick(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: const Text('Cámara'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => _pick(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Galería'),
                      ),
                      OutlinedButton.icon(
                        key: const Key('demo-evidence'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => setState(() {
                          _bytes = null;
                          _evidence = 'Evidencia de demostración (simulada)';
                        }),
                        icon: const Icon(Icons.science_outlined),
                        label: const Text('Usar evidencia demo'),
                      ),
                    ],
                  ),
                  Text(
                    'La foto queda solo en este teléfono; no se sube a ningún servidor.',
                    style: t.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              key: const Key('mark-delivered'),
              label: 'Marcar como entregado',
              onPressed: () => _complete(context, o),
            ),
            TextButton.icon(
              onPressed: () => context.push('/soporte'),
              icon: const Icon(Icons.support_agent, color: AppColors.error),
              label: const Text(
                'No encuentro al cliente · Pedir ayuda',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _complete(BuildContext context, Order o) {
    final session = context.read<SessionController>();
    final res = context.read<OrderService>().completeDelivery(
      o.id,
      session.user!.id,
      _code.text,
      _evidence,
    );
    switch (res) {
      case DeliveryResult.wrongCode:
        setState(() => _error = 'Código incorrecto');
        showSnack(context, 'Código del cliente incorrecto', error: true);
      case DeliveryResult.missingEvidence:
        showSnack(
          context,
          'Agrega una foto de evidencia para finalizar',
          error: true,
        );
      case DeliveryResult.invalidState:
        showSnack(context, 'El pedido no está en camino', error: true);
      case DeliveryResult.ok:
        showSnack(context, '¡Entregado! +${cop(o.courierEarning)} (simulado)');
        context.go('/repartidor');
    }
  }
}
