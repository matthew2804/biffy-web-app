import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/catalog_constants.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/user.dart';
import '../../../shared/state/session_controller.dart';

/// Placa colombiana de moto: 3 letras, 2 números y 1 letra (p. ej. ABC12D).
bool isValidMotoPlate(String v) =>
    RegExp(r'^[A-Z]{3}\d{2}[A-Z]$').hasMatch(v.trim().toUpperCase());

/// Registro inicial obligatorio antes de recibir ofertas. Los documentos son
/// campos locales: no se suben ni se verifican legalmente.
class CourierRegistrationScreen extends StatefulWidget {
  const CourierRegistrationScreen({super.key});

  @override
  State<CourierRegistrationScreen> createState() =>
      _CourierRegistrationScreenState();
}

class _CourierRegistrationScreenState extends State<CourierRegistrationScreen> {
  final _form = GlobalKey<FormState>();
  late final SessionController _s = context.read<SessionController>();
  late final CourierProfile? _p = _s.data.courierProfile;
  late final _name = TextEditingController(text: _p?.fullName ?? _s.user?.name);
  late final _doc = TextEditingController(text: _p?.docNumber);
  late final _phone = TextEditingController(text: _p?.phone ?? _s.user?.phone);
  late final _email = TextEditingController(
    text: _p?.contactEmail ?? _s.user?.email,
  );
  late final _plate = TextEditingController(text: _p?.plate);
  late String _docType = _p?.docType ?? 'CC';
  late Vehicle _vehicle = _p?.vehicle ?? Vehicle.bicycle;
  late String? _uni = _p?.universityId ?? _s.verifiedUniversityId;

  @override
  void initState() {
    super.initState();
    _p;
    _uni;
  }

  @override
  void dispose() {
    for (final c in [_name, _doc, _phone, _email, _plate]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _p == null ? 'Registro de repartidor' : 'Editar datos de repartidor',
        ),
      ),
      body: MobileFrame(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text(
                'Completa tus datos para recibir ofertas. Datos locales de demostración: no se suben documentos ni se verifica identidad.',
                style: t.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('c-name'),
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo *',
                ),
                validator: _req,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _docType,
                      decoration: const InputDecoration(labelText: 'Tipo'),
                      items: [
                        for (final d in ['CC', 'CE', 'TI', 'PAS'])
                          DropdownMenuItem(value: d, child: Text(d)),
                      ],
                      onChanged: (v) => setState(() => _docType = v ?? 'CC'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: const Key('c-doc'),
                      controller: _doc,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Número de documento *',
                      ),
                      validator: (v) =>
                          (v == null ||
                              v.replaceAll(RegExp(r'\D'), '').length < 6)
                          ? 'Mínimo 6 dígitos'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('c-phone'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono *'),
                validator: (v) =>
                    (v == null || v.replaceAll(RegExp(r'\D'), '').length < 7)
                    ? 'Teléfono no válido'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo de contacto *',
                ),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Correo no válido' : null,
              ),
              const SizedBox(height: 16),
              Text('Medio de transporte *', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in Vehicle.values)
                    SelectPill(
                      key: Key('vehicle-${v.name}'),
                      label: v.label,
                      emoji: v.emoji,
                      selected: _vehicle == v,
                      onTap: () => setState(() => _vehicle = v),
                    ),
                ],
              ),
              Text(
                'Cubre hasta ${_vehicle.maxKm} km por pedido (simulado).',
                style: t.bodySmall,
              ),
              if (_vehicle == Vehicle.moto) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('c-plate'),
                  controller: _plate,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Placa de la moto *',
                    hintText: 'ABC12D',
                  ),
                  validator: (v) => (v == null || !isValidMotoPlate(v))
                      ? 'Placa no válida (formato ABC12D)'
                      : null,
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                isExpanded: true,
                initialValue: _uni,
                decoration: const InputDecoration(
                  labelText: 'Universidad (para el modo Campus)',
                  helperText:
                      'El modo Campus además requiere verificación simulada.',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Ninguna'),
                  ),
                  for (final u in kUniversities)
                    DropdownMenuItem<String?>(value: u.id, child: Text(u.name)),
                ],
                onChanged: (v) => setState(() => _uni = v),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                key: const Key('c-save'),
                label: 'Guardar y empezar',
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  _s.saveCourierProfile(
                    CourierProfile(
                      fullName: _name.text.trim(),
                      docType: _docType,
                      docNumber: _doc.text.trim(),
                      phone: _phone.text.trim(),
                      vehicle: _vehicle,
                      plate: _vehicle == Vehicle.moto
                          ? _plate.text.trim().toUpperCase()
                          : null,
                      universityId: _uni,
                      contactEmail: _email.text.trim(),
                    ),
                  );
                  showSnack(context, 'Datos de repartidor guardados');
                  context.go('/repartidor');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
