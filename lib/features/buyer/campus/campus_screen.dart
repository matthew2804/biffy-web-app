import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/catalog_cards.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/controller_scope.dart';
import '../../../shared/state/session_controller.dart';
import '../../auth/bloc/university_verification_cubit.dart';
import '../../orders/bloc/orders_bloc.dart';
import '../../../app/di/injection.dart';

/// Campus Live: restaurantes de la universidad y verificación del correo
/// institucional con un código enviado por correo.
class CampusScreen extends StatefulWidget {
  const CampusScreen({super.key});

  /// Crea el estado de la verificación institucional.
  @override
  State<CampusScreen> createState() => _CampusScreenState();
}

/// Estado con el correo, el código y la universidad elegida.
class _CampusScreenState extends State<CampusScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  String? _uniId;
  late final UniversityVerificationCubit _verification;

  /// Prellena el correo institucional si ya se verificó antes.
  @override
  void initState() {
    super.initState();
    final session = getIt<SessionController>();
    _email.text = session.data.universityEmail ?? '';
    _verification = getIt<UniversityVerificationCubit>();
  }

  /// Libera los controladores del correo, del código y el cubit.
  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _verification.close();
    super.dispose();
  }

  /// Envía el código al correo institucional.
  Future<void> _send(SessionController session, String uniId) async {
    final email = _email.text.trim().isEmpty
        ? (session.data.universityEmail ?? '')
        : _email.text.trim();
    await _verification.sendCode(
      universityId: uniId,
      email: email,
      renewal:
          session.isVerifiedStudent && session.verifiedUniversityId == uniId,
    );
    if (!mounted) return;
    if (_verification.state.codeSent) {
      showSnack(context, 'Código enviado a $email');
    }
  }

  /// Confirma el código y activa Campus por 30 días.
  Future<void> _confirm(SessionController session, String uniId) async {
    final email = _email.text.trim().isEmpty
        ? (session.data.universityEmail ?? '')
        : _email.text.trim();
    await _verification.confirmCode(
      universityId: uniId,
      email: email,
      code: _code.text,
    );
    if (!mounted) return;
    if (session.isVerifiedStudent) {
      _code.clear();
      showSnack(context, 'Universidad verificada por 30 días 🎓');
    }
  }

  /// Construye el selector de universidad, la verificación y los populares.
  @override
  Widget build(BuildContext context) {
    final session = context.watchController<SessionController>();
    final catalog = context.watchController<CatalogController>();
    final orders = context.watch<OrdersBloc>();
    final t = Theme.of(context).textTheme;
    final uniId = _uniId ?? session.universityId ?? 'icesi';
    final uni = universityById(uniId)!;
    final verified =
        session.isVerifiedStudent && session.verifiedUniversityId == uniId;
    final expiry = session.verificationExpiresAt;
    final now = catalog.now;
    final list = catalog.campusRestaurants(uniId);
    int ordersToday(String rid) => orders.all
        .where((o) => o.restaurantId == rid && sameDay(o.createdAt, now))
        .length;
    list.sort((a, b) => ordersToday(b.id).compareTo(ordersToday(a.id)));

    return Scaffold(
      appBar: AppBar(title: const Text('Campus Live')),
      body: BlocBuilder<UniversityVerificationCubit, UniversityVerificationState>(
        bloc: _verification,
        builder: (context, vState) => MobileFrame(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Text('Universidad', style: t.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final u in kUniversities)
                    SelectPill(
                      label: u.name,
                      selected: u.id == uniId,
                      onTap: () {
                        setState(() => _uniId = u.id);
                        _verification.clearCode();
                        if (session.isLoggedIn && !session.isVerifiedStudent) {
                          session.setUniversity(u.id);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              BiffyCard(
                color: verified
                    ? AppColors.success.withValues(alpha: 0.12)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verified
                          ? '✅ Verificado en ${uni.name}'
                          : '🎓 Verifica tu correo de ${uni.name}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      verified
                          ? 'Tu correo institucional está activo. '
                                'Vence el ${expiry == null ? "sin fecha" : "${expiry.day}/${expiry.month}/${expiry.year}"}.'
                          : 'Enviaremos un código de 6 dígitos a tu correo @${uni.domain}. '
                                'Cada 30 días deberás confirmar que el correo sigue activo.',
                      style: t.bodySmall,
                    ),
                    if (!session.isLoggedIn)
                      PrimaryButton(
                        label: 'Inicia sesión para verificar',
                        onPressed: () => requireLogin(
                          context,
                          reason: 'verificar tu universidad',
                        ),
                      )
                    else ...[
                      if (!verified) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('uni-email'),
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Correo institucional',
                            hintText: 'tu.nombre@${uni.domain}',
                            errorText: vState.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        PrimaryButton(
                          key: const Key('uni-send'),
                          label: vState.sending ? 'Enviando…' : 'Enviar código',
                          onPressed: vState.sending
                              ? null
                              : () => _send(session, uniId),
                        ),
                      ] else ...[
                        const SizedBox(height: 8),
                        TextButton(
                          key: const Key('uni-renew'),
                          onPressed: vState.sending
                              ? null
                              : () => _send(session, uniId),
                          child: const Text('Revalidar ahora'),
                        ),
                      ],
                      if (vState.codeSent) ...[
                        const SizedBox(height: 12),
                        TextField(
                          key: const Key('uni-code'),
                          controller: _code,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Código de 6 dígitos',
                          ),
                        ),
                        if (vState.demoCode != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Modo demo · código: ${vState.demoCode}',
                            style: t.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 8),
                        PrimaryButton(
                          key: const Key('uni-confirm'),
                          label: vState.confirming
                              ? 'Confirmando…'
                              : 'Confirmar código',
                          onPressed: vState.confirming
                              ? null
                              : () => _confirm(session, uniId),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              if (!verified) ...[
                const SizedBox(height: 12),
                BiffyCard(
                  child: Text(
                    'Campus está deshabilitado mientras tu correo institucional no esté verificado. '
                    'Puedes seguir usando Biffy con normalidad, sin el descuento de campus.',
                    style: t.bodySmall,
                  ),
                ),
              ] else ...[
                SectionHeader('Populares cerca de ${uni.name}'),
                Text(
                  'Solo restaurantes que entregan en ${session.point.name}.',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  EmptyState(
                    emoji: '🏫',
                    title:
                        'Ningún restaurante de ${uni.name} entrega en tu punto',
                    body: 'Cambia el punto de entrega a uno del campus.',
                    actionLabel: 'Cambiar punto de entrega',
                    onAction: () => showDeliveryPointSheet(context),
                  )
                else
                  for (final r in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RestaurantCard(r),
                          Padding(
                            padding: const EdgeInsets.only(left: 12, top: 4),
                            child: Text(
                              '🔥 ${ordersToday(r.id)} pedidos hoy en la demo',
                              style: t.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
