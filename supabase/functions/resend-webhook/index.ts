// Edge Function: webhook de Resend para rebotes del correo institucional.
//
// Si Resend avisa que el correo rebotó, se revoca Campus de inmediato y se
// envía un aviso al correo personal de la cuenta. Configura el webhook en
// Resend apuntando a esta función y guarda el signing secret en
// `RESEND_WEBHOOK_SECRET`.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { Webhook } from 'https://esm.sh/svix@1';
import { sendEmail } from '../_shared/email.ts';

/// Punto de entrada del webhook de Resend.
Deno.serve(async (req: Request) => {
  const secret = Deno.env.get('RESEND_WEBHOOK_SECRET');
  if (!secret) return new Response('not_configured', { status: 500 });

  const payload = await req.text();
  let event: Record<string, unknown>;
  try {
    const headers = Object.fromEntries(req.headers.entries());
    event = new Webhook(secret).verify(payload, headers) as Record<
      string,
      unknown
    >;
  } catch {
    return new Response('invalid_signature', { status: 401 });
  }

  const type = String(event.type ?? '');
  if (!type.includes('bounced') && !type.includes('failed')) {
    return new Response('ignored', { status: 200 });
  }

  const data = (event.data ?? {}) as Record<string, unknown>;
  const to = Array.isArray(data.to)
    ? String(data.to[0] ?? '').toLowerCase()
    : String(data.email ?? '').toLowerCase();
  if (!to) return new Response('no_email', { status: 200 });

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { data: row } = await admin
    .from('university_verifications')
    .select('user_id')
    .eq('email', to)
    .in('status', ['active', 'pending'])
    .maybeSingle();
  if (!row) return new Response('no_verification', { status: 200 });

  await admin.rpc('revoke_university_verification', {
    p_user: row.user_id,
    p_reason: 'bounce',
  });

  const { data: profile } = await admin
    .from('profiles')
    .select('email')
    .eq('id', row.user_id)
    .maybeSingle();
  if (profile?.email) {
    await sendEmail({
      to: profile.email,
      subject: 'Campus deshabilitado en Biffy',
      text:
        'El correo institucional rebotó y Campus quedó deshabilitado. ' +
        'Puedes seguir usando Biffy con normalidad; vuelve a verificar cuando tengas un correo activo.',
      html:
        '<p>El correo institucional rebotó y Campus quedó deshabilitado.</p>' +
        '<p>Puedes seguir usando Biffy con normalidad; vuelve a verificar cuando tengas un correo activo.</p>',
    });
  }

  return new Response('ok', { status: 200 });
});
