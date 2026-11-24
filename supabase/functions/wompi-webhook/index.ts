// Edge Function: webhook de eventos de Wompi (sin JWT).
//
// - Verifica `X-Event-Checksum` (SHA-256) antes de tocar la base.
// - Deduplica por `payment_events.event_id`; si ya se aplicó, responde 200.
// - NO confía en el body: consulta la transacción real en la API de Wompi.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { getTransaction } from '../_shared/wompi.ts';
import {
  sha256Hex,
  verifyEventSignature,
  type WompiEvent,
} from '../_shared/wompi_signature.ts';

/// Traduce el estado de Wompi al enum de la base.
function paymentStatus(status: string): string | null {
  switch (status) {
    case 'APPROVED':
      return 'approved';
    case 'DECLINED':
    case 'ERROR':
      return 'rejected';
    case 'VOIDED':
      return 'refunded';
    case 'PENDING':
      return 'pending';
    default:
      return null;
  }
}

/// Responde texto plano (Wompi solo mira el status).
function text(body: string, status = 200): Response {
  return new Response(body, { status, headers: { 'Content-Type': 'text/plain' } });
}

/// Punto de entrada del webhook.
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return text('method_not_allowed', 405);

  const secret = Deno.env.get('WOMPI_EVENTS_SECRET');
  if (!secret) return text('not_configured', 500);

  let event: WompiEvent;
  try {
    event = JSON.parse(await req.text()) as WompiEvent;
  } catch {
    return text('invalid_payload', 400);
  }

  const header = req.headers.get('x-event-checksum');
  if (!(await verifyEventSignature(event, header, secret))) {
    // Diagnóstico: Wompi sí llama, pero la firma no coincide. Se registra el
    // evento y el hash (no el secreto) para comparar con el panel.
    console.error(
      'wompi_invalid_signature',
      JSON.stringify({
        environment: event.environment,
        event: event.event,
        signature: event.signature,
        header,
        body: event.signature?.checksum,
        secretLength: secret.trim().length,
        secretHash: await sha256Hex(secret.trim()),
      }),
    );
    return text('invalid_signature', 401);
  }

  const tx = event.data?.transaction ?? {};
  const transactionId = String(tx.id ?? '');
  const reference = String(tx.reference ?? '');
  if (!transactionId || !reference) return text('no_transaction', 200);

  const url = Deno.env.get('SUPABASE_URL')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(url, service);

  const { data: payment, error: paymentError } = await admin
    .from('payments')
    .select('id, order_id')
    .eq('reference', reference)
    .maybeSingle();
  if (paymentError) {
    console.error('wompi-webhook payment', paymentError.message);
    return text('db_error', 500);
  }

  const eventId = `tx:${transactionId}:${String(tx.status ?? 'unknown')}`;
  const { data: existing, error: existingError } = await admin
    .from('payment_events')
    .select('id, result')
    .eq('event_id', eventId)
    .maybeSingle();
  if (existingError) {
    console.error('wompi-webhook event', existingError.message);
    return text('db_error', 500);
  }
  // Ya se aplicó en una entrega anterior: idempotente.
  if (existing?.result === 'applied') return text('ignored', 200);

  if (!existing) {
    const { error: insertError } = await admin.from('payment_events').insert({
      payment_id: payment?.id ?? null,
      event_id: eventId,
      request_id: req.headers.get('x-request-id'),
      signature_valid: true,
      result: 'received',
      payload: event,
    });
    // Carrera con otra entrega del mismo evento: se continúa (payment_apply
    // también es idempotente).
    if (insertError && insertError.code !== '23505') {
      console.error('wompi-webhook insert', insertError.message);
      return text('db_error', 500);
    }
  }

  if (!payment) {
    await admin
      .from('payment_events')
      .update({ result: 'payment_not_found' })
      .eq('event_id', eventId);
    return text('payment_not_found', 200);
  }

  // Se consulta la transacción real: el body solo sirve para ubicarla.
  let real;
  try {
    real = await getTransaction(transactionId);
  } catch (error) {
    console.error('wompi-webhook getTransaction', String(error));
    return text('provider_error', 500);
  }

  const status = paymentStatus(real.status);
  if (!status) return text('ignored_status', 200);

  const { error: applyError } = await admin.rpc('payment_apply', {
    p_payment: payment.id,
    p_status: status,
    p_tx_id: real.id,
    p_detail: real.status_message ?? '',
  });
  if (applyError) {
    console.error('payment_apply', applyError.message);
    return text('db_error', 500);
  }

  await admin
    .from('payment_events')
    .update({ result: 'applied' })
    .eq('event_id', eventId);

  return text('ok', 200);
});
