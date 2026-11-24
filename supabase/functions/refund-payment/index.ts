// Edge Function: ejecuta el reembolso en Wompi y lo registra.
//
// - Comprador dueño del pedido o cron con `x-cron-secret`.
// - Si el pago es de Wompi y tiene transacción, la anula/reembolsa.
// - Siempre deja el resultado en `payments` (refund_external_id).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { voidTransaction } from '../_shared/wompi.ts';

/// Responde JSON con CORS.
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Punto de entrada.
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') return json({ result: 'method_not_allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(url, service);

  const cronSecret = Deno.env.get('CRON_SECRET');
  const isCron = Boolean(cronSecret) &&
    req.headers.get('x-cron-secret') === cronSecret;

  let userId: string | null = null;
  if (!isCron) {
    const auth = req.headers.get('Authorization');
    if (!auth) return json({ result: 'not_authenticated' }, 401);
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: auth } },
    });
    const {
      data: { user },
      error,
    } = await userClient.auth.getUser();
    if (error || !user) return json({ result: 'not_authenticated' }, 401);
    userId = user.id;
  }

  let body: { orderId?: string; reason?: string };
  try {
    body = await req.json();
  } catch {
    return json({ result: 'invalid_payload' }, 400);
  }
  const orderId = (body.orderId ?? '').trim();
  if (!orderId) return json({ result: 'invalid_payload' }, 400);
  const reason = (body.reason ?? 'Cancelación del pedido').slice(0, 300);

  const { data: order, error: orderError } = await admin
    .from('orders')
    .select('id, buyer_id, branch_id, total, payment_method')
    .eq('id', orderId)
    .maybeSingle();
  if (orderError) {
    console.error('refund-payment order', orderError.message);
    return json({ result: 'server_error' }, 500);
  }
  if (!order) return json({ result: 'not_found' }, 404);

  if (!isCron) {
    let allowed = order.buyer_id === userId;
    if (!allowed) {
      const { data: branch } = await admin
        .from('branches')
        .select('business_id')
        .eq('id', order.branch_id)
        .maybeSingle();
      if (branch?.business_id) {
        const { data: business } = await admin
          .from('businesses')
          .select('owner_id')
          .eq('id', branch.business_id)
          .maybeSingle();
        allowed = business?.owner_id === userId;
      }
    }
    if (!allowed) return json({ result: 'forbidden' }, 403);
  }

  const { data: payment, error: paymentError } = await admin
    .from('payments')
    .select('id, method, status, provider, provider_transaction_id, refund_external_id')
    .eq('order_id', orderId)
    .order('attempt', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (paymentError) {
    console.error('refund-payment payment', paymentError.message);
    return json({ result: 'server_error' }, 500);
  }
  if (!payment) return json({ result: 'no_payment' }, 200);

  // El efectivo no tiene pasarela: solo se registra la devolución.
  if (payment.method === 'cash' || payment.provider !== 'wompi') {
    const { error } = await admin.rpc('payment_refund', {
      p_order: orderId,
      p_reason: reason,
      p_external_id: null,
    });
    if (error) {
      console.error('payment_refund cash', error.message);
      return json({ result: 'server_error' }, 500);
    }
    return json({ result: 'ok', method: 'cash' });
  }

  if (payment.status !== 'refunded' && payment.status !== 'approved') {
    return json({ result: 'invalid_state', status: payment.status }, 200);
  }
  if (payment.refund_external_id) {
    return json({
      result: 'ok',
      already: true,
      externalId: payment.refund_external_id,
    });
  }

  let externalId: string | null = null;
  if (payment.provider_transaction_id) {
    try {
      await voidTransaction(payment.provider_transaction_id);
      externalId = `void:${payment.provider_transaction_id}`;
    } catch (error) {
      console.error('voidTransaction', String(error));
      return json({ result: 'provider_error' }, 502);
    }
  }

  const { error: refundError } = await admin.rpc('payment_refund', {
    p_order: orderId,
    p_reason: reason,
    p_external_id: externalId,
  });
  if (refundError) {
    console.error('payment_refund', refundError.message);
    return json({ result: 'server_error' }, 500);
  }

  return json({ result: 'ok', externalId });
});
