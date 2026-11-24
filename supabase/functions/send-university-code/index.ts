// Edge Function: envía un código de 6 dígitos al correo institucional.
//
// El código lo genera `create_university_verification` con service_role y solo
// lo recibe esta función. En producción se envía con Resend; si no hay clave y
// `UNIVERSITY_DEMO_MODE=true`, se devuelve `demoCode` para probar en la app.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
import { escapeHtml, sendEmail } from '../_shared/email.ts';

/// Responde JSON con las cabeceras CORS.
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Punto de entrada de la Edge Function.
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

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
  });
  const {
    data: { user },
    error: userError,
  } = await userClient.auth.getUser();
  if (userError || !user) return json({ result: 'not_authenticated' }, 401);

  let body: { universityId?: string; email?: string; mode?: string };
  try {
    body = await req.json();
  } catch {
    return json({ result: 'invalid_payload' }, 400);
  }
  const universityId = (body.universityId ?? '').trim();
  const email = (body.email ?? '').trim().toLowerCase();
  const renewal = body.mode === 'renew';
  if (!universityId || !email) return json({ result: 'invalid_payload' }, 400);

  const admin = createClient(url, service);
  const { data: created, error: createError } = await admin.rpc(
    'create_university_verification',
    {
      p_user: user.id,
      p_university_id: universityId,
      p_email: email,
      p_renewal: renewal,
    },
  );
  if (createError) {
    console.error('create_university_verification', createError.message);
    return json({ result: 'rpc_error' }, 500);
  }

  const result = (created as Record<string, unknown> | null)?.result;
  if (result !== 'ok') {
    // Se devuelve 200 para que la app traduzca el código (rate_limited, etc.).
    return json({ result });
  }
  const token = (created as Record<string, unknown>).token as string;
  if (!token) return json({ result: 'rpc_error' }, 500);

  const safeEmail = escapeHtml(email);
  const emailResult = await sendEmail({
    to: email,
    subject: 'Tu código de verificación de Biffy',
    text:
      `Tu código para verificar el correo institucional es ${token}.\n` +
      'Vence en 15 minutos. Si no lo pediste, ignora este mensaje.',
    html:
      `<p>Tu código para verificar el correo institucional <b>${safeEmail}</b> es:</p>` +
      `<p style="font-size:28px;font-weight:bold;letter-spacing:6px">${token}</p>` +
      '<p>Vence en 15 minutos. Si no lo pediste, ignora este mensaje.</p>',
  });

  if (!emailResult.ok) {
    if (
      emailResult.reason === 'email_not_configured' &&
      Deno.env.get('UNIVERSITY_DEMO_MODE') === 'true'
    ) {
      return json({ result: 'ok', demoCode: token });
    }
    console.error('send-university-code', emailResult.reason);
    return json({ result: 'email_not_configured' }, 500);
  }

  return json({ result: 'ok' });
});
