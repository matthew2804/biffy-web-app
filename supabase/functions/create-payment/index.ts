// Edge Function: inicia (o reutiliza) el pago de un pedido en Wompi.
//
// - Requiere JWT del comprador dueño del pedido.
// - El monto SIEMPRE sale de orders.total; si el cliente manda otro, se rechaza.
// - Devuelve la URL del Checkout Web de Wompi.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { checkoutUrl } from '../_shared/wompi.ts';
import { integritySignature } from '../_shared/wompi_signature.ts';

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

  const auth = req.headers.get('Authorization');
  if (!auth) return json({ result: 'not_authenticated' }, 401);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const publicKey = Deno.env.get('WOMPI_PUBLIC_KEY');
  const integritySecret = Deno.env.get('WOMPI_INTEGRITY_SECRET');
  if (!publicKey || !integritySecret) {
    return json({ result: 'not_configured' }, 500);
  }

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
  });
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();
  if (userError || !user) return json({ result: 'not_authenticated' }, 401);

  let body: { orderId?: string; method?: string; amount?: number };
  try {
    body = await req.json();
  } catch {
    return json({ result: 'invalid_payload' }, 400);
  }

  const orderId = (body.orderId ?? '').trim();
  const method = (body.method ?? '').trim();
  if (!orderId || !['nequi', 'daviplata', 'card', 'pse'].includes(method)) {
    return json({ result: 'invalid_payload' }, 400);
  }

  const admin = createClient(url, service);
  const { data: order, error: orderError } = await admin
    .from('orders')
    .select('id, buyer_id, total, status, payment_status')
    .eq('id', orderId)
    .maybeSingle();
  if (orderError) {
    console.error('create-payment order', orderError.message);
    return json({ result: 'server_error' }, 500);
  }
  if (!order) return json({ result: 'not_found' }, 404);
  if (order.buyer_id !== user.id) return json({ result: 'forbidden' }, 403);

  // El monto del cliente, si viene, debe coincidir con el del servidor.
  if (body.amount !== undefined && body.amount !== null) {
    if (Number(body.amount) !== Number(order.total)) {
      return json(
        { result: 'amount_mismatch', expected: order.total },
        200,
      );
    }
  }

  const { data: begin, error: beginError } = await admin.rpc('payment_begin', {
    p_order: orderId,
    p_buyer: user.id,
    p_method: method,
    p_key: orderId,
  });
  if (beginError) {
    console.error('payment_begin', beginError.message);
    return json({ result: 'server_error' }, 500);
  }

  const started = (begin ?? {}) as Record<string, unknown>;
  const result = String(started.result ?? 'server_error');
  if (result !== 'ok') {
    // already_paid, expired, invalid_state… se traducen en la app.
    return json({ result });
  }
  if (started.checkout_url) {
    return json({
      result: 'ok',
      paymentId: started.payment_id,
      amount: started.amount,
      attempt: started.attempt,
      reference: started.reference,
      checkoutUrl: started.checkout_url,
      reused: true,
    });
  }

  const paymentId = String(started.payment_id);
  const amount = Number(started.amount);
  const reference = String(started.reference);
  const integrity = await integritySignature(
    reference,
    amount * 100,
    'COP',
    integritySecret,
  );
  const urlCheckout = checkoutUrl({
    publicKey,
    amountInCents: amount * 100,
    reference,
    integrity,
  });

  const { error: setError } = await admin.rpc('payment_set_checkout', {
    p_payment: paymentId,
    p_url: urlCheckout,
  });
  if (setError) {
    console.error('payment_set_checkout', setError.message);
    return json({ result: 'server_error' }, 500);
  }

  return json({
    result: 'ok',
    paymentId,
    amount,
    attempt: started.attempt,
    reference,
    checkoutUrl: urlCheckout,
    reused: false,
  });
});
