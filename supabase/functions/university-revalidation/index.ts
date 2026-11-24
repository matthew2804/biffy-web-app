// Edge Function programada: revalida los correos institucionales cada mes.
//
// - A los 7 días del vencimiento envía un código nuevo al correo institucional.
// - Si el código no se confirma en 7 días, o el correo vence, revoca Campus.
// - Al revocar, Biffy sigue funcionando; solo se deshabilita Campus.
//
// Programar en Supabase (Cron) una vez al día, por ejemplo a las 08:00.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { sendEmail } from '../_shared/email.ts';

const DAY = 24 * 60 * 60 * 1000;

/// Responde JSON con un estado HTTP.
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/// Punto de entrada de la revalidación programada.
Deno.serve(async (req: Request) => {
  // Protección opcional para invocaciones desde Cron.
  const secret = Deno.env.get('REVALIDATION_SECRET');
  if (secret && req.headers.get('x-cron-secret') !== secret) {
    return json({ result: 'forbidden' }, 403);
  }

  const url = Deno.env.get('SUPABASE_URL')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(url, service);

  const now = new Date();
  const inSevenDays = new Date(now.getTime() + 7 * DAY);
  const grace = new Date(now.getTime() - 7 * DAY);
  const cooldown = new Date(now.getTime() - 20 * DAY);

  let sent = 0;
  let revoked = 0;

  // 1) Verificaciones activas que vencen pronto: enviar código nuevo.
  const { data: active, error: activeError } = await admin
    .from('university_verifications')
    .select('user_id, university_id, email, expires_at, last_sent_at')
    .eq('status', 'active');
  if (activeError) return json({ result: 'query_error' }, 500);

  for (const row of active ?? []) {
    const expires = row.expires_at ? new Date(row.expires_at) : null;
    const lastSent = row.last_sent_at ? new Date(row.last_sent_at) : null;
    if (!expires || expires > inSevenDays) continue;
    if (lastSent && lastSent > cooldown) continue;

    const { data: created } = await admin.rpc(
      'create_university_verification',
      {
        p_user: row.user_id,
        p_university_id: row.university_id,
        p_email: row.email,
        p_renewal: true,
      },
    );
    const token = (created as Record<string, unknown> | null)?.token as
      | string
      | undefined;
    if (!token) continue;

    const mail = await sendEmail({
      to: row.email,
      subject: 'Revalida tu correo institucional en Biffy',
      text:
        `Tu código para seguir usando Campus es ${token}.\n` +
        'Vence en 15 minutos. Si no lo confirmas, Campus se deshabilitará.',
      html:
        `<p>Tu código para seguir usando Campus es:</p>` +
        `<p style="font-size:28px;font-weight:bold;letter-spacing:6px">${token}</p>` +
        '<p>Vence en 15 minutos. Si no lo confirmas, Campus se deshabilitará.</p>',
    });
    if (mail.ok) sent++;
  }

  // 2) Pendientes demasiado tiempo o activas ya vencidas: revocar Campus.
  const { data: rows, error: rowsError } = await admin
    .from('university_verifications')
    .select('user_id, status, expires_at, last_sent_at, email')
    .in('status', ['active', 'pending']);
  if (rowsError) return json({ result: 'query_error' }, 500);

  const toRevoke: { user_id: string; reason: string }[] = [];
  for (const row of rows ?? []) {
    const expires = row.expires_at ? new Date(row.expires_at) : null;
    const lastSent = row.last_sent_at ? new Date(row.last_sent_at) : null;
    if (row.status === 'active' && expires && expires < now) {
      toRevoke.push({ user_id: row.user_id, reason: 'expired' });
    } else if (row.status === 'pending' && lastSent && lastSent < grace) {
      toRevoke.push({ user_id: row.user_id, reason: 'not_confirmed' });
    }
  }

  if (toRevoke.length > 0) {
    const ids = toRevoke.map((r) => r.user_id);
    const { data: profiles } = await admin
      .from('profiles')
      .select('id, email')
      .in('id', ids);
    const emailById = new Map(
      (profiles ?? []).map((p) => [p.id as string, p.email as string]),
    );

    for (const item of toRevoke) {
      await admin.rpc('revoke_university_verification', {
        p_user: item.user_id,
        p_reason: item.reason,
      });
      revoked++;

      const accountEmail = emailById.get(item.user_id);
      if (accountEmail) {
        await sendEmail({
          to: accountEmail,
          subject: 'Campus deshabilitado en Biffy',
          text:
            'Tu correo institucional ya no está activo o no fue confirmado. ' +
            'Puedes seguir usando Biffy con normalidad; Campus quedó deshabilitado.',
          html:
            '<p>Tu correo institucional ya no está activo o no fue confirmado.</p>' +
            '<p>Puedes seguir usando Biffy con normalidad; Campus quedó deshabilitado.</p>',
        });
      }
    }
  }

  return json({ result: 'ok', revalidation_emails: sent, revoked });
});
