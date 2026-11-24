// Cliente mínimo de Wompi: API de transacciones y URL del Checkout Web.
//
// La llave privada y los secretos viven en los secrets de Supabase. La app solo
// recibe la URL del checkout; nunca ve estas llaves.
const API_BASE = Deno.env.get('WOMPI_ENV') === 'production'
  ? 'https://production.wompi.co/v1'
  : 'https://sandbox.wompi.co/v1';

/// Transacción tal como la devuelve Wompi (solo los campos que usamos).
export type WompiTransaction = {
  id: string;
  status: string;
  status_message?: string;
  reference: string;
  amount_in_cents: number;
  currency?: string;
  payment_method_type?: string;
};

/// Hace una petición autenticada a la API de Wompi.
export async function wompiFetch<T>(
  path: string,
  init: RequestInit = {},
): Promise<T> {
  const key = Deno.env.get('WOMPI_PRIVATE_KEY');
  if (!key) throw new Error('wompi_not_configured');
  const res = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`wompi_${res.status}: ${body.slice(0, 300)}`);
  }
  return await res.json() as T;
}

/// Consulta una transacción por su id (nunca se confía en el webhook).
///
/// La API de Wompi devuelve `{ data: { ...transacción } }`; se desenvuelve para
/// que el resto del código lea `status`, `reference`, etc. directamente.
export async function getTransaction(id: string): Promise<WompiTransaction> {
  const res = await wompiFetch<{ data?: WompiTransaction } & WompiTransaction>(
    `/transactions/${encodeURIComponent(id)}`,
  );
  return (res.data ?? res) as WompiTransaction;
}

/// Anula una transacción aprobada (reembolso del mismo día).
export function voidTransaction(id: string): Promise<unknown> {
  return wompiFetch(`/transactions/${encodeURIComponent(id)}/void`, {
    method: 'POST',
  });
}

/// Construye la URL del Checkout Web con la firma de integridad.
export function checkoutUrl({
  publicKey,
  amountInCents,
  reference,
  integrity,
  redirectUrl,
}: {
  publicKey: string;
  amountInCents: number;
  reference: string;
  integrity: string;
  redirectUrl?: string;
}): string {
  const params = new URLSearchParams({
    'public-key': publicKey,
    currency: 'COP',
    'amount-in-cents': String(amountInCents),
    reference,
    'signature:integrity': integrity,
  });
  if (redirectUrl) params.set('redirect-url', redirectUrl);
  return `https://checkout.wompi.co/p/?${params.toString()}`;
}
