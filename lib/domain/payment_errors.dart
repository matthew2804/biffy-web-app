import 'entities/payment.dart';

/// Traduce el código/`status_detail` de Wompi a un mensaje en español.
///
/// Si no hay una traducción conocida, se usa [detail] (que Wompi a veces manda
/// en inglés) o [fallback]. La UI nunca muestra códigos técnicos.
String paymentErrorText({
  String? code,
  String? detail,
  String? fallback,
}) {
  final c = (code ?? '').trim().toLowerCase();
  final d = (detail ?? '').trim().toLowerCase();
  final raw = '$c $d';

  // Resultados de nuestra propia app/Edge Function.
  switch (c) {
    case 'amount_mismatch':
      return 'El total del pedido cambió. Vuelve a revisarlo antes de pagar.';
    case 'not_found':
      return 'No encontramos el pedido para cobrar.';
    case 'forbidden':
      return 'Este pedido no es tuyo.';
    case 'invalid_state':
      return 'El pedido ya no admite este pago.';
    case 'expired':
      return 'El tiempo para pagar venció. Vuelve a intentarlo.';
    case 'already_paid':
      return 'Este pedido ya está pagado.';
    case 'not_configured':
      return 'La pasarela no está configurada.';
    case 'network':
      return 'No pudimos conectar con la pasarela. Revisa tu conexión.';
    case 'server_error':
      return 'No pudimos completar el pago. Inténtalo de nuevo.';
    case 'invalid_method':
      return 'Ese método de pago no está disponible.';
  }

  // Detalles típicos de tarjeta/Wompi.
  if (raw.contains('insufficient') || raw.contains('insuficiente')) {
    return 'Tu tarjeta o cuenta no tiene fondos suficientes.';
  }
  if (raw.contains('bad_filled_card_number') || raw.contains('invalid_number')) {
    return 'Revisa el número de la tarjeta.';
  }
  if (raw.contains('bad_filled_date') || raw.contains('expired_date')) {
    return 'La fecha de vencimiento de la tarjeta no es válida.';
  }
  if (raw.contains('bad_filled_security_code') || raw.contains('cvv')) {
    return 'Revisa el código de seguridad (CVV) de la tarjeta.';
  }
  if (raw.contains('call_for_authorize') || raw.contains('authoriz')) {
    return 'Tu banco debe autorizar el pago. Llama a tu banco e inténtalo de nuevo.';
  }
  if (raw.contains('high_risk') || raw.contains('fraud') ||
      raw.contains('rejected_by_bank')) {
    return 'El banco rechazó el pago por seguridad.';
  }
  if (raw.contains('pse')) {
    return 'El banco rechazó el débito PSE. Inténtalo con otro banco.';
  }
  if (raw.contains('nequi')) {
    return 'Nequi rechazó el pago. Revisa tu saldo e inténtalo de nuevo.';
  }
  if (raw.contains('daviplata')) {
    return 'DaviPlata rechazó el pago. Revisa tu saldo e inténtalo de nuevo.';
  }
  if (raw.contains('voided') || raw.contains('refunded')) {
    return 'El pago fue anulado y el dinero se devolverá.';
  }
  if (raw.contains('pending')) {
    return 'El pago está pendiente de confirmación.';
  }

  if (detail != null && detail.trim().isNotEmpty) return detail.trim();
  return fallback ?? 'No pudimos completar el pago. Inténtalo de nuevo.';
}

/// Etiqueta corta del estado del pago para la UI.
String paymentStatusLabel(PaymentStatus status) => switch (status) {
  PaymentStatus.pending => 'Pendiente de pago',
  PaymentStatus.processing => 'Procesando pago',
  PaymentStatus.approved => 'Pago aprobado',
  PaymentStatus.rejected => 'Pago rechazado',
  PaymentStatus.expired => 'Pago vencido',
  PaymentStatus.refunded => 'Pago reembolsado',
};
