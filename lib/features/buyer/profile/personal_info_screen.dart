import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/widgets/ui.dart';
import '../../../shared/state/session_controller.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _form = GlobalKey<FormState>();
  late final _session = context.read<SessionController>();
  late final _name = TextEditingController(text: _session.user?.name);
  late final _phone = TextEditingController(text: _session.user?.phone);

  @override
  void initState() {
    super.initState();
    _name;
    _phone;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<SessionController>().user;
    if (u == null) return const Scaffold();
    return Scaffold(
      appBar: AppBar(title: const Text('Información personal')),
      body: MobileFrame(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Escribe tu nombre'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: u.email,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Correo',
                  helperText:
                      'Informativo: el correo no se puede cambiar en la demo.',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                validator: (v) =>
                    (v != null &&
                        v.trim().isNotEmpty &&
                        v.replaceAll(RegExp(r'\D'), '').length < 7)
                    ? 'Teléfono no válido'
                    : null,
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: 'Guardar',
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  _session.updateProfile(name: _name.text, phone: _phone.text);
                  showSnack(context, 'Datos actualizados');
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
