import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/format.dart';
import '../../../core/widgets/actions.dart';
import '../../../core/widgets/catalog_cards.dart';
import '../../../core/widgets/ui.dart';
import '../../../shared/state/catalog_controller.dart';
import '../../../shared/state/order_service.dart';
import '../../../shared/state/session_controller.dart';

/// Campus Live: restaurantes populares de la universidad que entregan en el
/// punto actual, más la verificación universitaria SIMULADA.
class CampusScreen extends StatefulWidget {
  const CampusScreen({super.key});

  /// Crea el estado de la verificación universitaria simulada.
  @override
  State<CampusScreen> createState() => _CampusScreenState();
}

/// Estado con el correo y la universidad elegidos para verificar.
class _CampusScreenState extends State<CampusScreen> {
  final _email = TextEditingController();
  String? _uniId;
  String? _error;

  /// Libera el controlador del correo universitario.
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  /// Construye el selector de universidad, la verificación y los populares.
  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final catalog = context.watch<CatalogController>();
    final orders = context.watch<OrderService>();
    final t = Theme.of(context).textTheme;
    final uniId = _uniId ?? session.universityId ?? 'icesi';
    final uni = universityById(uniId)!;
    final verified = session.verifiedUniversityId == uniId;
    final now = catalog.now;
    final list = catalog.campusRestaurants(uniId);
    int ordersToday(String rid) => orders.all
        .where((o) => o.restaurantId == rid && sameDay(o.createdAt, now))
        .length;
    list.sort((a, b) => ordersToday(b.id).compareTo(ordersToday(a.id)));

    return Scaffold(
      appBar: AppBar(title: const Text('Campus Live')),
      body: MobileFrame(
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
                        ? '✅ Verificado en ${uni.name} (simulado)'
                        : '🎓 Verifica tu correo de ${uni.name}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Simulación: solo comprobamos que el dominio sea @${uni.domain}. '
                    'No demuestra que controles ese correo ni es una verificación segura.',
                    style: t.bodySmall,
                  ),
                  if (!verified) ...[
                    const SizedBox(height: 12),
                    if (!session.isLoggedIn)
                      PrimaryButton(
                        label: 'Inicia sesión para verificar',
                        onPressed: () => requireLogin(
                          context,
                          reason: 'verificar tu universidad',
                        ),
                      )
                    else ...[
                      TextField(
                        key: const Key('uni-email'),
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Correo universitario',
                          hintText: 'tu.nombre@${uni.domain}',
                          errorText: _error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      PrimaryButton(
                        key: const Key('uni-verify'),
                        label: 'Verificar (simulado)',
                        onPressed: () {
                          final r = session.verifyUniversity(
                            uniId,
                            _email.text,
                          );
                          setState(() {
                            _error = switch (r) {
                              VerifyResult.ok => null,
                              VerifyResult.invalidEmail =>
                                'Escribe un correo válido',
                              VerifyResult.domainMismatch =>
                                'El correo debe terminar en @${uni.domain}',
                              VerifyResult.notLoggedIn =>
                                'Inicia sesión primero',
                            };
                          });
                          if (r == VerifyResult.ok) {
                            showSnack(
                              context,
                              'Verificación simulada completada 🎓',
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
            SectionHeader('Populares cerca de ${uni.name}'),
            Text(
              'Solo restaurantes que entregan en ${session.point.name}.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            if (list.isEmpty)
              EmptyState(
                emoji: '🏫',
                title: 'Ningún restaurante de ${uni.name} entrega en tu punto',
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
        ),
      ),
    );
  }
}
