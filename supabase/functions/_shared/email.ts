// Envío de correos con Resend. Los secretos viven en Supabase, no en el repo.
export type EmailResult = { ok: true } | { ok: false; reason: string };

/// Envía un correo HTML/texto con Resend y devuelve el resultado.
export async function sendEmail({
  to,
  subject,
  html,
  text,
}: {
  to: string;
  subject: string;
  html: string;
  text: string;
}): Promise<EmailResult> {
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const from = Deno.env.get('FROM_EMAIL') ??
    'Biffy <no-reply@notifications.biffy.app>';

  if (!apiKey) return { ok: false, reason: 'email_not_configured' };

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ from, to: [to], subject, html, text }),
  });

  if (!res.ok) {
    return { ok: false, reason: `resend_${res.status}` };
  }
  return { ok: true };
}

/// Escapa texto para incluirlo en el HTML del correo.
export function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}
