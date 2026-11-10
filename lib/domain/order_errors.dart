import '../core/utils/format.dart';

/// Traduce el `result` de los RPC de pedidos a un mensaje en español para la
/// persona usuaria. Nunca devuelve el código crudo ni una excepción.
///
/// `data` es el `jsonb` completo del RPC: algunos códigos traen contexto
/// (`dish` = nombre del plato, `expected` = total que calculó el servidor).
String orderErrorMessage(String code, [Map<String, dynamic> data = const {}]) {
  final dish = data['dish'] as String?;
  final expected = (data['expected'] as num?)?.toInt();

  return switch (code) {
    // Sesión y permisos
    'not_authenticated' => 'Inicia sesión para continuar.',
    'no_profile' =>
      'No encontramos tu perfil. Cierra sesión y vuelve a entrar.',
    'forbidden' => 'No tienes permiso para hacer esto con este pedido.',

    // Crear pedido
    'branch_not_found' => 'Este restaurante ya no está disponible.',
    'branch_paused' => 'El restaurante pausó sus pedidos por ahora.',
    'address_not_found' =>
      'No encontramos esa dirección. Elige o crea otra para continuar.',
    'point_not_found' => 'El punto de entrega de esa dirección ya no existe.',
    'out_of_zone' => 'El restaurante no entrega en la zona de esa dirección.',
    'outside_campus' => 'Esa sede solo entrega dentro del campus.',
    'empty_cart' => 'Tu carrito está vacío.',
    'invalid_qty' => 'Revisa las cantidades: hay un producto con cantidad no válida.',
    'dish_not_found' => 'Un producto de tu carrito ya no existe.',
    'dish_unavailable' =>
      dish == null
          ? 'Un producto de tu carrito ya no está disponible.'
          : '$dish ya no está disponible.',
    'no_portions' =>
      dish == null
          ? 'Ya no quedan porciones de un producto de tu carrito.'
          : 'Ya no quedan suficientes porciones de $dish.',
    'invalid_option' =>
      dish == null
          ? 'Una opción de tu pedido cambió. Vuelve a elegirla.'
          : 'Una opción de $dish cambió. Vuelve a elegirla.',
    'subtotal_mismatch' ||
    'total_mismatch' =>
      expected == null
          ? 'Los precios cambiaron. Revisa tu carrito y confirma de nuevo.'
          : 'Los precios cambiaron: ahora el total es ${cop(expected)}. '
                'Revisa tu carrito y confirma de nuevo.',
    'insufficient_gotas' => 'No tienes suficientes Gotas para este pedido.',
    'invalid_gotas' =>
      'Las Gotas elegidas superan lo que falta por pagar. Ajusta e intenta de nuevo.',
    'invalid_tip' => 'La propina no es válida. Elige otra opción.',
    'invalid_payment' => 'Elige un método de pago válido.',
    'coupon_unavailable' =>
      'Ese cupón ya no está disponible. Quítalo e intenta de nuevo.',
    'invalid_payload' =>
      'No pudimos leer tu pedido. Vuelve al carrito e intenta de nuevo.',

    // Transiciones
    'not_found' => 'No encontramos el pedido o ya no tienes acceso a él.',
    'invalid_state' =>
      'El pedido ya cambió de estado. Actualizamos la pantalla con lo último.',
    'not_synced' =>
      'Este pedido aún no se sincroniza con el servidor. Espera un momento.',

    // Repartidor
    'already_assigned' => 'Otro repartidor ya tomó este pedido.',
    'not_available' => 'La oferta ya no está disponible.',
    'busy' => 'Termina tu entrega actual antes de aceptar otra.',
    'out_of_range' =>
      'La distancia supera el alcance de tu medio de transporte.',
    'declined_before' => 'Ya rechazaste esta oferta.',
    'wrong_code' => 'El código del cliente es incorrecto.',
    'missing_evidence' =>
      'Adjunta una foto de evidencia de la entrega para finalizar.',
    'upload_failed' =>
      'No pudimos subir la foto. Revisa tu conexión e intenta de nuevo.',

    // Transporte
    'network' =>
      'Sin conexión con el servidor. Revisa tu internet e intenta de nuevo.',
    _ => 'No pudimos completar la acción. Intenta de nuevo en un momento.',
  };
}

/// Códigos de error de transporte: el servidor puede o no haber procesado la
/// petición, así que conviene recargar antes de reintentar.
bool isTransportError(String code) =>
    code == 'network' || code == 'server_error' || code == 'upload_failed';
