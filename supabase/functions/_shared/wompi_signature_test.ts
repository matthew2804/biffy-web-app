// Pruebas de las firmas de Wompi (se corren con `deno test`).
import { assertEquals } from 'jsr:@std/assert';
import { createHash } from 'node:crypto';
import {
  integritySignature,
  sha256Hex,
  verifyEventSignature,
  type WompiEvent,
} from './wompi_signature.ts';

/// SHA-256 independiente (node:crypto) para no probar la función consigo misma.
function sha(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

Deno.test('sha256Hex coincide con node:crypto', async () => {
  assertEquals(await sha256Hex('abc'), sha('abc'));
  assertEquals(
    await sha256Hex('Biffy paga con Wompi'),
    sha('Biffy paga con Wompi'),
  );
});

Deno.test('integridad: referencia + monto + moneda + secreto', async () => {
  const reference = 'BF-1001-1-abcdef';
  const amount = 1365000;
  const secret = 'test_integrity_secreto';
  assertEquals(
    await integritySignature(reference, amount, 'COP', secret),
    sha(`${reference}${amount}COP${secret}`),
  );
});

function eventWith(
  checksum: string,
  timestamp = 1700000000,
): WompiEvent {
  return {
    event: 'transaction.updated',
    data: {
      transaction: {
        id: 'tx-1',
        status: 'APPROVED',
        amount_in_cents: 1365000,
      },
    },
    signature: {
      properties: [
        'transaction.id',
        'transaction.status',
        'transaction.amount_in_cents',
      ],
      checksum,
      timestamp,
    },
  };
}

Deno.test('evento: checksum válido en header y en el body', async () => {
  const secret = 'test_events_secreto';
  const timestamp = 1700000000;
  const checksum = sha(`tx-1APPROVED1365000${timestamp}${secret}`);
  const event = eventWith(checksum, timestamp);

  assertEquals(await verifyEventSignature(event, checksum, secret), true);
  assertEquals(await verifyEventSignature(event, null, secret), true);
  // Algunos proxies entregan el header vacío; debe usar el checksum del body.
  assertEquals(await verifyEventSignature(event, '', secret), true);
});

Deno.test('evento: checksum inválido o secreto equivocado se rechaza', async () => {
  const secret = 'test_events_secreto';
  const timestamp = 1700000000;
  const checksum = sha(`tx-1APPROVED1365000${timestamp}${secret}`);
  const event = eventWith(checksum, timestamp);

  // Un header inválido no importa si el body trae el checksum correcto.
  assertEquals(await verifyEventSignature(event, 'deadbeef', secret), true);
  // Si ambos checksums son inválidos, se rechaza.
  const bad = eventWith('deadbeef', timestamp);
  assertEquals(await verifyEventSignature(bad, 'deadbeef', secret), false);
  assertEquals(await verifyEventSignature(event, checksum, 'otro-secreto'), false);
});

Deno.test('evento: usa sent_at si falta signature.timestamp', async () => {
  const secret = 'test_events_secreto';
  const timestamp = 1700000000;
  const sentAt = new Date(timestamp * 1000).toISOString();
  const checksum = sha(`tx-1APPROVED1365000${timestamp}${secret}`);
  const event = eventWith(checksum, timestamp);
  delete event.signature!.timestamp;
  event.signature!.sent_at = sentAt;

  assertEquals(await verifyEventSignature(event, checksum, secret), true);

  // También se acepta `sent_at` en la raíz del evento.
  delete event.signature!.sent_at;
  event.sent_at = sentAt;
  assertEquals(await verifyEventSignature(event, checksum, secret), true);
});

Deno.test('evento: sin firma o sin timestamp se rechaza', async () => {
  const secret = 'test_events_secreto';
  const sinFirma: WompiEvent = { event: 'transaction.updated', data: {} };
  assertEquals(await verifyEventSignature(sinFirma, null, secret), false);

  const sinTimestamp = eventWith('abc');
  delete sinTimestamp.signature!.timestamp;
  assertEquals(await verifyEventSignature(sinTimestamp, 'abc', secret), false);
});
