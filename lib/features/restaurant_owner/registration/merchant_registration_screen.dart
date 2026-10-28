import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/ui.dart';
import '../../../data/models/business.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/notification_center.dart';
import '../../../shared/state/session_controller.dart';

const _docs = {
  'rut': 'RUT',
  'camara': 'Cámara de comercio',
  'cedula': 'Cédula del representante',
  'sanitario': 'Concepto sanitario',
};

/// Registro del negocio por pasos. Los documentos solo se marcan localmente:
/// no se verifican ni se transmiten.
class MerchantRegistrationScreen extends StatefulWidget {
  const MerchantRegistrationScreen({super.key});

  @override
  State<MerchantRegistrationScreen> createState() =>
      _MerchantRegistrationScreenState();
}

/// Estado del registro por pasos con todos los datos del negocio.
class _MerchantRegistrationScreenState
    extends State<MerchantRegistrationScreen> {
  static int _seq = 0;
  final _forms = List.generate(6, (_) => GlobalKey<FormState>());
  int _step = 0;
  late final SessionController _session = context.read<SessionController>();

  final _owner = TextEditingController();
  final _ownerDoc = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _brand = TextEditingController();
  final _legal = TextEditingController();
  final _desc = TextEditingController();
  final _branchName = TextEditingController(text: 'Sede principal');
  final _address = TextEditingController();
  final _nit = TextEditingController();
  final _account = TextEditingController();
  String _cuisine = 'sandwich';
  String _pointId = 'icesi-plazoleta';
  int _open = 8;
  int _close = 20;
  final Set<int> _closed = {7};
  double _radius = 2;
  double _discount = 0.1;
  final Map<String, String> _attached = {};
  String _bank = 'Bancolombia';
  String _accountType = 'Ahorros';

  /// Precarga el correo, teléfono y nombre del usuario logueado.
  @override
  void initState() {
    super.initState();
    final u = _session.user;
    if (u != null) {
      _owner.text = u.name;
      _email.text = u.email;
      _phone.text = u.phone;
    }
  }

  /// Libera todos los controladores del registro.
  @override
  void dispose() {
    for (final c in [
      _owner,
      _ownerDoc,
      _phone,
      _email,
      _password,
      _brand,
      _legal,
      _desc,
      _branchName,
      _address,
      _nit,
      _account,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Rellena el formulario con datos ficticios para probar la demo.
  void _autofill() {
    setState(() {
      _owner.text = _owner.text.isEmpty ? 'Laura Gómez (demo)' : _owner.text;
      _ownerDoc.text = '1020304050';
      _phone.text = _phone.text.isEmpty ? '3104567890' : _phone.text;
      if (_email.text.isEmpty) {
        _email.text = 'nuevo.negocio${++_seq}@demo.biffy.co';
      }
      _password.text = 'biffy123';
      _brand.text = 'Arepas del Campus (demo)';
      _legal.text = 'Arepas del Campus S.A.S. (ficticio)';
      _desc.text = 'Arepas rellenas y jugos naturales para estudiantes.';
      _cuisine = 'almuerzo';
      _address.text = 'Plazoleta Icesi · Local 9 (ficticio)';
      _nit.text = '901234567-8';
      _account.text = '12345678901';
      for (final k in _docs.keys) {
        _attached[k] = '$k-demo.pdf';
      }
    });
  }

  /// Valida que el campo obligatorio no esté vacío.
  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null;

  /// Valida el paso actual y avanza o confirma el registro.
  void _next() {
    if (_step < 5 && !(_forms[_step].currentState?.validate() ?? true)) return;
    if (_step == 3 && _attached.length < _docs.length) {
      showSnack(
        context,
        'Marca los ${_docs.length} documentos (simulados)',
        error: true,
      );
      return;
    }
    if (_step < 5) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  /// Crea el negocio y su sede, los registra y abre el menú.
  void _finish() {
    if (_session.auth.isRemote && !_session.isLoggedIn) {
      showSnack(
        context,
        'El alta de negocios con Supabase llega en la siguiente fase.',
        error: true,
      );
      return;
    }
    final catalog = context.read<CatalogController>();
    final notifications = context.read<NotificationCenter>();
    try {
      if (!_session.isLoggedIn) {
        _session.register(
          name: _owner.text,
          email: _email.text,
          password: _password.text,
          role: UserRole.restaurant,
          phone: _phone.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _step = 0);
      showSnack(context, e.message, error: true);
      return;
    }
    final n = ++_seq;
    final bizId = 'biz-new-$n';
    final p = pointById(_pointId);
    final acc = _account.text.replaceAll(RegExp(r'\D'), '');
    final biz = Business(
      id: bizId,
      brand: _brand.text.trim(),
      legalName: _legal.text.trim(),
      nit: _nit.text.trim(),
      cuisine: _cuisine,
      description: _desc.text.trim(),
      ownerName: _owner.text.trim(),
      ownerDoc: _ownerDoc.text.trim(),
      ownerPhone: _phone.text.trim(),
      ownerEmail: _email.text.trim(),
      bankName: _bank,
      accountType: _accountType,
      accountNumber:
          '•••• ${acc.length >= 4 ? acc.substring(acc.length - 4) : acc}',
      legalDocs: Map.of(_attached),
    );
    final branch = Restaurant(
      id: 'rest-new-$n',
      businessId: bizId,
      name: _brand.text.trim(),
      emoji: categoryById(_cuisine).emoji,
      tagline: _desc.text.trim(),
      cuisine: _cuisine,
      address: _address.text.trim(),
      rating: 4.5,
      prepMin: 15,
      lat: p.lat + 0.0006,
      lng: p.lng + 0.0004,
      radiusKm: _radius,
      couriersNearby: 3,
      openHour: _open,
      closeHour: _close,
      closedWeekdays: _closed.toList(),
      campusId: p.campusId,
      studentDiscount: p.campusId == null ? 0 : _discount,
      branchName: _branchName.text.trim(),
    );
    catalog.registerBusiness(biz, [branch]);
    _session.linkBusiness(bizId);
    notifications.push(
      title: 'Negocio registrado (demo) ✅',
      body: 'Crea tu primer producto para aparecer en el catálogo.',
      audience: 'business:$bizId',
      route: '/negocio/menu',
    );
    showSnack(context, '${biz.brand} registrado · agrega tu menú');
    context.go('/negocio/menu');
  }

  /// Dibuja el paso actual del registro y los botones de navegación.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final titles = [
      'Responsable',
      'Negocio',
      'Sede y horarios',
      'Información legal',
      'Pagos (simulados)',
      'Resumen',
    ];
    final hours = [for (var h = 5; h <= 23; h++) h];
    return Scaffold(
      appBar: AppBar(
        title: Text('Paso ${_step + 1}/6 · ${titles[_step]}'),
        actions: [
          TextButton(
            key: const Key('autofill'),
            onPressed: _autofill,
            child: const Text('Autocompletar demo'),
          ),
        ],
      ),
      body: MobileFrame(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            LinearProgressIndicator(
              value: (_step + 1) / 6,
              color: AppColors.primary,
              backgroundColor: context.palette.border,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(height: 16),
            if (_step == 0)
              Form(
                key: _forms[0],
                child: Column(
                  children: [
                    TextFormField(
                      controller: _owner,
                      decoration: const InputDecoration(
                        labelText: 'Nombre del responsable *',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ownerDoc,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Cédula *'),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Teléfono *',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      readOnly: _session.isLoggedIn,
                      decoration: const InputDecoration(labelText: 'Correo *'),
                      validator: (v) => (v == null || !v.contains('@'))
                          ? 'Correo no válido'
                          : null,
                    ),
                    if (!_session.isLoggedIn) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Contraseña de demostración *',
                          helperText:
                              'Solo en memoria. No uses una contraseña real.',
                        ),
                        validator: (v) => (v == null || v.length < 6)
                            ? 'Mínimo 6 caracteres'
                            : null,
                      ),
                    ],
                  ],
                ),
              ),
            if (_step == 1)
              Form(
                key: _forms[1],
                child: Column(
                  children: [
                    TextFormField(
                      controller: _brand,
                      decoration: const InputDecoration(
                        labelText: 'Nombre comercial *',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _legal,
                      decoration: const InputDecoration(
                        labelText: 'Razón social *',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _cuisine,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de cocina',
                      ),
                      items: [
                        for (final c in kCategories)
                          DropdownMenuItem(
                            value: c.id,
                            child: Text('${c.emoji} ${c.label}'),
                          ),
                      ],
                      onChanged: (v) =>
                          setState(() => _cuisine = v ?? _cuisine),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _desc,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Descripción *',
                      ),
                      validator: _req,
                    ),
                  ],
                ),
              ),
            if (_step == 2)
              Form(
                key: _forms[2],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _branchName,
                      decoration: const InputDecoration(
                        labelText: 'Nombre de la sede *',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'Dirección *',
                      ),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _pointId,
                      decoration: const InputDecoration(
                        labelText: 'Zona (ubicación simulada)',
                      ),
                      items: [
                        for (final p in kDeliveryPoints)
                          DropdownMenuItem(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: (v) =>
                          setState(() => _pointId = v ?? _pointId),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: _open,
                            decoration: const InputDecoration(
                              labelText: 'Abre',
                            ),
                            items: [
                              for (final h in hours)
                                DropdownMenuItem(
                                  value: h,
                                  child: Text('${two(h)}:00'),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _open = v ?? _open),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: _close,
                            decoration: const InputDecoration(
                              labelText: 'Cierra',
                            ),
                            items: [
                              for (final h in hours)
                                DropdownMenuItem(
                                  value: h,
                                  child: Text('${two(h)}:00'),
                                ),
                            ],
                            validator: (v) => (v ?? 0) <= _open
                                ? 'Debe ser después de abrir'
                                : null,
                            onChanged: (v) =>
                                setState(() => _close = v ?? _close),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('Días cerrados', style: t.titleSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var d = 1; d <= 7; d++)
                          SelectPill(
                            label: capitalize(weekdayName(d)).substring(0, 3),
                            selected: _closed.contains(d),
                            onTap: () => setState(
                              () => _closed.contains(d)
                                  ? _closed.remove(d)
                                  : _closed.add(d),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Radio de entrega: ${_radius.toStringAsFixed(1)} km',
                      style: t.titleSmall,
                    ),
                    Slider(
                      min: 0.5,
                      max: 6,
                      divisions: 11,
                      value: _radius,
                      onChanged: (v) => setState(() => _radius = v),
                    ),
                    if (pointById(_pointId).campusId != null) ...[
                      Text(
                        'Descuento universitario: ${(_discount * 100).round()}%',
                        style: t.titleSmall,
                      ),
                      Slider(
                        min: 0,
                        max: 0.3,
                        divisions: 6,
                        value: _discount,
                        onChanged: (v) => setState(() => _discount = v),
                      ),
                    ],
                  ],
                ),
              ),
            if (_step == 3)
              Form(
                key: _forms[3],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _nit,
                      decoration: const InputDecoration(labelText: 'NIT *'),
                      validator: _req,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Documentos: márcalos como adjuntados para la demo. No se suben, no se verifican y no se transmiten.',
                      style: t.bodySmall,
                    ),
                    for (final e in _docs.entries)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.value),
                        subtitle: Text(_attached[e.key] ?? 'Sin adjuntar'),
                        value: _attached.containsKey(e.key),
                        onChanged: (v) => setState(
                          () => v == true
                              ? _attached[e.key] = '${e.key}-demo.pdf'
                              : _attached.remove(e.key),
                        ),
                      ),
                  ],
                ),
              ),
            if (_step == 4)
              Form(
                key: _forms[4],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DemoBadge('Datos de pago simulados'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _bank,
                      decoration: const InputDecoration(labelText: 'Banco'),
                      items: [
                        for (final b in [
                          'Bancolombia',
                          'Davivienda',
                          'BBVA',
                          'Banco de Bogotá',
                          'Nequi',
                        ])
                          DropdownMenuItem(value: b, child: Text(b)),
                      ],
                      onChanged: (v) => setState(() => _bank = v ?? _bank),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _accountType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de cuenta',
                      ),
                      items: [
                        for (final a in ['Ahorros', 'Corriente'])
                          DropdownMenuItem(value: a, child: Text(a)),
                      ],
                      onChanged: (v) =>
                          setState(() => _accountType = v ?? _accountType),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _account,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Número de cuenta (ficticio) *',
                        helperText: 'Solo se guardan los últimos 4 dígitos.',
                      ),
                      validator: (v) => (v == null || v.length < 6)
                          ? 'Mínimo 6 dígitos'
                          : null,
                    ),
                  ],
                ),
              ),
            if (_step == 5)
              BiffyCard(
                child: Column(
                  children: [
                    InfoRow('Responsable', _owner.text),
                    InfoRow('Correo', _email.text),
                    InfoRow('Negocio', _brand.text),
                    InfoRow('Cocina', categoryById(_cuisine).label),
                    InfoRow(
                      'Sede',
                      '${_branchName.text} · ${pointById(_pointId).name}',
                    ),
                    InfoRow('Horario', '${two(_open)}:00 – ${two(_close)}:00'),
                    InfoRow('Radio', '${_radius.toStringAsFixed(1)} km'),
                    InfoRow(
                      'Documentos',
                      '${_attached.length}/${_docs.length} marcados',
                    ),
                    InfoRow('Banco', '$_bank · $_accountType'),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            Row(
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
                    key: const Key('mr-next'),
                    label: _step < 5 ? 'Siguiente' : 'Confirmar registro',
                    onPressed: _next,
                  ),
                ),
              ],
            ),
            if (_step == 0)
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/'),
                child: const Text('Cancelar'),
              ),
          ],
        ),
      ),
    );
  }
}
