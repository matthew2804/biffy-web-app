import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/address.dart';
import '../../../shared/state/session_controller.dart';

class AddressesScreen extends StatelessWidget {
  const AddressesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final list = session.data.addresses;
    final def = session.data.defaultAddress?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Direcciones')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-address'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.text,
        onPressed: () => context.push('/direcciones/nueva'),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: MobileFrame(
        child: list.isEmpty
            ? EmptyState(
                emoji: '🏠',
                title: 'No tienes direcciones guardadas',
                actionLabel: 'Agregar dirección',
                onAction: () => context.push('/direcciones/nueva'),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                children: [
                  Text(
                    'Datos locales de demostración. No usamos GPS.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  for (final a in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: BiffyCard(
                        border: a.id == def
                            ? Border.all(color: AppColors.primary, width: 2)
                            : null,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    a.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (a.id == def)
                                  const Tag(
                                    'Principal',
                                    color: AppColors.primary,
                                    textColor: AppColors.text,
                                  ),
                              ],
                            ),
                            Text(a.full),
                            if (a.reference.isNotEmpty)
                              Text(
                                'Ref.: ${a.reference}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            Text(
                              'Zona: ${pointById(a.pointId).name}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Row(
                              children: [
                                if (a.id != def)
                                  Flexible(
                                    child: TextButton(
                                      onPressed: () {
                                        session.setDefaultAddress(a.id);
                                        session.setPoint(a.pointId);
                                        showSnack(
                                          context,
                                          '${a.label} es tu dirección principal',
                                        );
                                      },
                                      child: const Text('Hacer principal'),
                                    ),
                                  ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'Editar ${a.label}',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () =>
                                      context.push('/direcciones/${a.id}'),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar ${a.label}',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.error,
                                  ),
                                  onPressed: () async {
                                    final ok = await showConfirm(
                                      context,
                                      title: '¿Eliminar dirección?',
                                      message:
                                          '«${a.label}» se eliminará de tus direcciones.',
                                      confirm: 'Eliminar',
                                      destructive: true,
                                    );
                                    if (ok) session.deleteAddress(a.id);
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

class AddressFormScreen extends StatefulWidget {
  const AddressFormScreen({super.key, this.id});
  final String? id;

  @override
  State<AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends State<AddressFormScreen> {
  final _form = GlobalKey<FormState>();
  late final SessionController _session = context.read<SessionController>();
  late final Address? _orig = _session.addressById(widget.id);
  late final _label = TextEditingController(text: _orig?.label);
  late final _line = TextEditingController(text: _orig?.line);
  late final _details = TextEditingController(text: _orig?.details);
  late final _hood = TextEditingController(text: _orig?.neighborhood);
  late final _ref = TextEditingController(text: _orig?.reference);
  late String _pointId = _orig?.pointId ?? _session.pointId;
  late bool _default = _orig == null
      ? _session.data.addresses.isEmpty
      : _session.data.defaultAddressId == _orig.id;

  @override
  void initState() {
    super.initState();
    _orig; // Lee la sesión mientras el contexto está activo.
  }

  @override
  void dispose() {
    for (final c in [_label, _line, _details, _hood, _ref]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    if (widget.id != null && _orig == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          emoji: '🏠',
          title: 'Dirección no encontrada',
          actionLabel: 'Volver',
          onAction: () => context.pop(),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_orig == null ? 'Nueva dirección' : 'Editar dirección'),
      ),
      body: MobileFrame(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                key: const Key('addr-label'),
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Nombre del lugar *',
                  hintText: 'Casa, Biblioteca…',
                ),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('addr-line'),
                controller: _line,
                decoration: const InputDecoration(labelText: 'Dirección *'),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _details,
                decoration: const InputDecoration(
                  labelText: 'Detalles (apto, piso, salón)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('addr-hood'),
                controller: _hood,
                decoration: const InputDecoration(labelText: 'Barrio *'),
                validator: _req,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ref,
                decoration: const InputDecoration(labelText: 'Referencia'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _pointId,
                decoration: const InputDecoration(
                  labelText: 'Zona de cobertura (demo) *',
                ),
                items: [
                  for (final p in kDeliveryPoints)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _pointId = v ?? _pointId),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Usar como dirección principal'),
                value: _default,
                onChanged: (v) => setState(() => _default = v),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                key: const Key('addr-save'),
                label: 'Guardar dirección',
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  final a = Address(
                    id: _orig?.id ?? '',
                    label: _label.text.trim(),
                    line: _line.text.trim(),
                    details: _details.text.trim(),
                    neighborhood: _hood.text.trim(),
                    reference: _ref.text.trim(),
                    pointId: _pointId,
                  );
                  _session.saveAddress(a, makeDefault: _default);
                  if (_default) _session.setPoint(_pointId);
                  showSnack(context, 'Dirección guardada');
                  context.pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
