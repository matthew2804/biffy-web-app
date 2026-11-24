// Edge Function: cancela los pedidos cuyo pago venció (cron con secreto).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

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

  const secret = Deno.env.get('CRON_SECRET');
  if (!secret || req.headers.get('x-cron-secret') !== secret) {
    return json({ result: 'forbidden' }, 401);
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );
  const { data, error } = await admin.rpc('expire_pending_payments');
  if (error) {
    console.error('expire_pending_payments', error.message);
    return json({ result: 'server_error' }, 500);
  }
  return json({ result: 'ok', expired: data ?? 0 });
});
