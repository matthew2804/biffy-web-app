# Plan · HU-5 · Pasarela de pagos (Wompi)

> Rama: `hu5-pasarela-pagos`, creada desde `dev` (commit del merge del PR #5).
> Proveedor elegido: **Wompi** (sandbox y producción), porque en Colombia cubre
> **Nequi, Daviplata, tarjeta y PSE**; Mercado Pago Colombia solo ofrece tarjeta,
> PSE, Efecty y saldo MP.
> Guía de sandbox: `GUIA_SANDBOX_WOMPI.md`.

## 0. Resumen

El comprador arma el carrito, elige el horario de entrega y el método de pago, y
desde el **mismo carrito** pulsa **Pagar**. Para métodos online se crea el pedido
(con el total calculado por `place_order`) y se abre el **Checkout de Wompi** en
el navegador. Si el pago se rechaza, el comprador **vuelve al carrito** con el
mensaje y el motivo, conservando sus productos, horario y método para reintentar.
El pedido queda en espera de pago y **no se ofrece al restaurante** hasta que el
pago esté aprobado. Si no se aprueba dentro de la ventana (30 min), el pedido se
cancela y se devuelven Gotas y cupón. El efectivo sigue funcionando sin pasarela,
con selección del billete y cálculo de vueltas.

Decisiones:

| Tema | Decisión |
|---|---|
| Pasarela | Wompi, **Checkout Web** (redirección). La app no captura datos de tarjeta. |
| Métodos | Nequi, Daviplata, tarjeta y PSE; efectivo sin pasarela. |
| Secretos | `WOMPI_PUBLIC_KEY`, `WOMPI_PRIVATE_KEY`, `WOMPI_EVENTS_SECRET`, `WOMPI_INTEGRITY_SECRET` solo en Supabase Secrets. La app solo recibe la URL de checkout. |
| Monto | `place_order` calcula `orders.total`; `create-payment` lo copia. Si el cliente manda `amount`, se compara y se rechaza con `amount_mismatch`. |
| Pedido | Se crea antes de pagar (reserva platos, Gotas y cupón). |
| Rechazo | No cancela de inmediato: vuelve al carrito con el motivo y permite reintentar. Se cancela al vencer la ventana. |
| Expiración | 30 min sin pago aprobado → cancelar + devolver Gotas/cupón + registrar. |
| Idempotencia | `orders.client_key` + una intención reutilizada mientras esté pendiente + `payment_events.event_id` único. |
| Reembolso | Se registra siempre; con pago aprobado se anula/reembolsa en Wompi desde Edge Function. |
| Efectivo | `payment_status = 'approved'` directo; se guarda `cash_tendered` y se calculan las vueltas. |
| Demo | `InMemoryPaymentRepository` simula aprobado/rechazado sin red. |

## 1. Mapa de archivos

```
supabase/migrations/0026_payments.sql
supabase/migrations/0099_verify.sql
supabase/tests/hu5_payments.sql

supabase/functions/_shared/wompi.ts             # API + URL de checkout + firma
supabase/functions/_shared/wompi_signature.ts   # checksum de eventos
supabase/functions/_shared/wompi_signature_test.ts
supabase/functions/create-payment/index.ts
supabase/functions/wompi-webhook/index.ts
supabase/functions/expire-payments/index.ts
supabase/functions/refund-payment/index.ts
supabase/config.toml

lib/domain/entities/payment.dart
lib/domain/repositories/payment_repository.dart
lib/domain/usecases/payments/start_payment.dart
lib/domain/usecases/payments/check_payment_status.dart
lib/domain/usecases/payments/retry_payment.dart
lib/domain/payment_errors.dart
lib/domain/cash_payment.dart                    # billetes y vueltas

lib/data/repositories/supabase_payment_repository.dart
lib/data/repositories/in_memory_payment_repository.dart
lib/shared/adapters/payment_adapters.dart

lib/features/buyer/cart/cash_payment_sheet.dart # elegir billete y ver vueltas
lib/features/buyer/cart/bloc/payment_bloc.dart
lib/features/buyer/cart/bloc/payment_event.dart
lib/features/buyer/cart/bloc/payment_state.dart
lib/features/buyer/cart/payment_banner.dart     # rechazo/expirado en el carrito
lib/features/buyer/payment/payment_status_screen.dart

test/unit/payment_bloc_test.dart
test/unit/payment_usecases_test.dart
test/unit/payment_errors_test.dart
test/unit/cash_payment_test.dart
test/widget/payment_flow_test.dart
```

## 2. Flujo de usuario (el que pediste)

1. **Carrito**: productos, nota, propina, cupón, Gotas, dirección.
2. **Horario**: se elige la hora de entrega (hoja actual).
3. **Método**: Nequi, Daviplata, tarjeta, PSE o efectivo.
4. **Pagar**:
   - **Online**: se crea el pedido (`pending`, `payment_status='pending'`) y se
     abre el Checkout de Wompi. Al volver a la app (o por Realtime), se consulta
     el estado.
   - **Efectivo**: se elige el billete, se muestra el cambio y se confirma sin
     pasarela; el pedido queda aprobado y visible para el restaurante.
5. **Rechazo**: se vuelve al carrito con un banner rojo:
   "Pago rechazado: <motivo>" y botones **Reintentar** / **Cambiar método**.
   El carrito conserva productos, horario y método; el pedido sigue pendiente.
6. **Aprobado**: se vacía el carrito y se navega al seguimiento.
7. **Expira**: banner "El pago venció", pedido cancelado, Gotas y cupón
   devueltos; el carrito se conserva para empezar de nuevo.

> Desviación acordada con la HU: un rechazo **no** cancela el pedido de
> inmediato (para poder reintentar). La cancelación y devolución ocurren al
> vencer la ventana de pago, y también si el comprador cancela a mano.

## 3. Base de datos (`0026_payments.sql`)

### 3.1 Tipos y tablas

```sql
create type public.payment_status as enum
  ('pending', 'processing', 'approved', 'rejected', 'expired', 'refunded');

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  attempt int not null default 1,
  amount int not null check (amount > 0),
  currency text not null default 'COP',
  method text not null check (method in ('nequi','daviplata','card','pse')),
  status public.payment_status not null default 'pending',
  provider text not null default 'wompi',
  reference text not null,                -- referencia enviada a Wompi
  checkout_url text,
  provider_transaction_id text unique,    -- id de la transacción en Wompi
  status_detail text,                     -- motivo del rechazo
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  approved_at timestamptz,
  rejected_at timestamptz,
  expired_at timestamptz,
  refunded_at timestamptz,
  refund_amount int not null default 0,
  refund_reason text,
  unique (order_id, attempt)
);

create table if not exists public.payment_events (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid references public.payments (id) on delete cascade,
  event_id text not null unique,          -- id del evento de Wompi
  signature_valid boolean not null default false,
  result text not null default '',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.orders
  add column if not exists payment_status public.payment_status not null
    default 'pending',
  add column if not exists payment_expires_at timestamptz,
  add column if not exists cash_tendered int,
  add column if not exists cash_change int;

update public.orders
   set payment_status = 'approved'
 where payment_method = 'cash' and payment_status = 'pending';
```

> `payments` es una fila **por intento** (auditoría). `orders.payment_status`
> es el espejo agregado: el restaurante solo ve `approved`.

### 3.2 RPC nuevas

| Función | Quién | Qué hace |
|---|---|---|
| `payment_begin(p_order uuid, p_method text, p_key text)` | service_role | Valida dueño, pedido y método. Reutiliza el intento `pending` o crea el siguiente con `amount = orders.total`. Marca `orders.payment_status='pending'` y fija `payment_expires_at` si es el primero. |
| `payment_set_checkout(p_payment uuid, p_url text)` | service_role | Guarda la URL de Wompi y la referencia. |
| `payment_apply(p_payment uuid, p_status, p_tx_id, p_detail)` | service_role | Idempotente (bloquea fila, ignora repetidos). `approved` → pedido aprobado + aviso al restaurante. `rejected` → intento rechazado y pedido sigue pendiente. `expired` → cancela + `refund_order`. `refunded` → registra reembolso. |
| `payment_refund(p_order uuid, p_reason text)` | service_role | Marca el pago aprobado como `refunded` y guarda monto/motivo/fecha. |
| `expire_pending_payments()` | service_role | Cancela pedidos con `payment_expires_at < now()` sin pago aprobado. |
| `payment_for_order(p_order uuid)` | authenticated | Devuelve el último intento si el comprador es dueño (o su sede). |

### 3.3 Cambios a lo existente

1. **`place_order`** (partir de la versión de `0025`):
   - `cash` → `payment_status='approved'`, `cash_tendered` obligatorio y
     `cash_tendered >= total`; guarda `cash_change = cash_tendered - total`.
   - online → `payment_status='pending'`, `payment_expires_at = now + 30 min`.
2. **`orders_read` / `can_read_order`**: el restaurante solo lee pedidos con
   `payment_status='approved'`.
3. **`restaurant_accept`**: si no está aprobado → `payment_pending`.
4. **Notificaciones (0022)**: no avisar al restaurante con pago pendiente;
   `payment_apply` crea "Nuevo pedido pagado" al aprobar.
5. **`buyer_cancel` / `restaurant_reject`**: además de `refund_order`, marcan el
   pago como `refunded` si estaba aprobado (la Edge Function hace la anulación).
6. **Realtime**: publicar `payments`.
7. **`0099_verify.sql`**: `payments`, `payment_events`, `orders.cash_tendered`.
8. **`apply_all.sql`**: regenerar.

### 3.4 RLS

```sql
alter table public.payments enable row level security;

create policy payments_read on public.payments
  for select to authenticated
  using (
    buyer_id = auth.uid()
    or (public.is_my_branch(branch_id) and status = 'approved')
  );

revoke insert, update, delete, truncate on public.payments
  from authenticated, anon;
revoke all on public.payment_events from authenticated, anon;
```

## 4. Edge Functions

### 4.1 Secretos

| Secreto | Uso |
|---|---|
| `WOMPI_PUBLIC_KEY` | Se incrusta en la URL del Checkout Web (llave de prueba o producción). |
| `WOMPI_PRIVATE_KEY` | Consultar transacciones y anular/reembolsar. |
| `WOMPI_INTEGRITY_SECRET` | Firma de integridad del checkout. |
| `WOMPI_EVENTS_SECRET` | Verificar el checksum de los eventos. |
| `WOMPI_ENV` | `sandbox` o `production` (elige host de API). |
| `CRON_SECRET` | Header `x-cron-secret` para `expire-payments`. |

### 4.2 `create-payment` (JWT)

1. Usuario autenticado y dueño del pedido.
2. Body `{ orderId, method, amount? }`; si `amount != orders.total` →
   `amount_mismatch`.
3. Reutiliza el intento pendiente si existe; si no, `payment_begin`.
4. Construye la firma de integridad:
   `SHA256(reference + amountInCents + 'COP' + WOMPI_INTEGRITY_SECRET)`
   (el orden exacto se copia del panel de Wompi).
5. Devuelve
   `https://checkout.wompi.co/p/?public-key=...&currency=COP&amount-in-cents=...&reference=...&signature:integrity=...&redirect-url=...`.
6. `payment_set_checkout` y responde `{ result:'ok', paymentId, amount, checkoutUrl }`.

### 4.3 `wompi-webhook` (`verify_jwt=false`)

1. Lee `X-Event-Checksum` y el body.
2. Toma `signature.properties` (rutas de campos), concatena esos valores en orden
   + `signature.timestamp` + `WOMPI_EVENTS_SECRET`, SHA-256 y compara.
3. Dedupe por `payment_events.event_id` (único); repetido → 200 `ignored`.
4. **No confía en el body**: `GET /v1/transactions/{id}` con la llave privada.
5. `payment_apply(...)`; 200 rápido. Wompi reintenta hasta 3 veces en 24 h.

### 4.4 `expire-payments` y `refund-payment`

- `expire-payments`: `x-cron-secret`; llama `expire_pending_payments()`.
  Se agenda con cron de Supabase o GitHub Action cada 10 min.
- `refund-payment`: JWT del dueño o cron; si el pago está aprobado, anula o
  reembolsa en Wompi (`/v1/transactions/{id}/void` o `/refund`) y registra el
  resultado. Si falla, queda `refund_reason` para reintento.

### 4.5 `config.toml`

```toml
[functions.wompi-webhook]
verify_jwt = false

[functions.expire-payments]
verify_jwt = false

[functions.refund-payment]
verify_jwt = false
```

## 5. Dominio

- `Payment`: `id`, `orderId`, `attempt`, `amount`, `method`, `status`,
  `checkoutUrl`, `statusDetail`, fechas.
- `PaymentStatus`: `pending`, `processing`, `approved`, `rejected`, `expired`,
  `refunded` (espejo de la base).
- `PaymentRepository`: `isRemote`, `start`, `status`, `retry`, `watch`, `refund`.
- Casos de uso: `StartPayment`, `CheckPaymentStatus`, `RetryPayment`.
- `payment_errors.dart`: `status_detail`/código de Wompi → español
  (fondos insuficientes, tarjeta vencida, banco rechazó PSE, Nequi sin saldo,
  etc.).
- `cash_payment.dart` (puro, con tests):
  - `kCopBills = [1000, 2000, 5000, 10000, 20000, 50000, 100000]`
  - `cashOptions(total)` → `[Pago exacto, ...billetes >= total]`
  - `changeFor(total, tendered)` y validación `tendered >= total`.

## 6. Datos + GetIt

- `SupabasePaymentRepository`: `create-payment` + Realtime `payments` +
  `payment_for_order` + `refund-payment`; sondeo de respaldo.
- `InMemoryPaymentRepository`: simula aprobado (2 s) o rechazado (modo de
  prueba) con `StreamController`; el efectivo no pasa por aquí.
- `data_module.dart`: registra una u otra según `AppConfig.hasSupabase`.
- `domain_module.dart`: casos de uso `Factory`.
- `presentation_module.dart`: `PaymentBloc` `Factory` con `param1` (orderId).

## 7. Presentación

### `PaymentBloc`

Eventos: `PaymentStarted(orderId, method)`, `PaymentStatusChecked`,
`PaymentRetried`, `PaymentChanged`, `PaymentClosed`.
Estado: `step` (`idle`, `processing`, `pending`, `approved`, `rejected`,
`expired`, `networkError`), `payment`, `message`, `canRetry`, `attempt`.

### Carrito (pantalla principal del flujo)

- Botón **Pagar** al final, después de horario y método.
- Si el método es online: crea el pedido (una sola vez), abre Wompi con
  `url_launcher` y, al volver, consulta el estado. Mientras tanto, Realtime
  actualiza.
- `PaymentBanner` dentro del carrito:
  - rechazado → rojo, "Pago rechazado: <motivo>", botones **Reintentar** y
    **Cambiar método**.
  - expirado → "El pago venció y el pedido se canceló"; el carrito se conserva.
  - error de red → "No pudimos confirmar el pago" + **Reintentar**.
- El carrito **no se vacía** hasta que el pago está aprobado (o es efectivo).
- Si el comprador edita el carrito con un pedido pendiente, se cancela ese
  pedido antes de crear el nuevo (para no dejar pedidos huérfanos).
- **Efectivo**: hoja con billetes sugeridos (`cashOptions`) y "Pago exacto";
  muestra "Pagas con $50.000 · Vueltas $17.600"; guarda `cash_tendered`.

### Seguimiento y otros roles

- `/pago/:orderId`: estado del pago, motivo del rechazo, botón de reintento y
  "Volver al pedido". Sirve para deep links y para el detalle.
- `tracking_screen`: tarjeta de estado del pago ("Esperando pago",
  "Pago aprobado", "Pago rechazado: …").
- Restaurante: RLS oculta los pedidos sin pago aprobado; en cocina se muestra
  "Pagado" y el efectivo con "Paga con … · Vueltas …".
- Repartidor: en la entrega ve el efectivo y las vueltas.

## 8. Pruebas

| Nivel | Archivo | Qué cubre |
|---|---|---|
| Unit Bloc | `test/unit/payment_bloc_test.dart` | 7 etapas, rechazo → carrito, reintento, red, Realtime. |
| Unit casos de uso | `test/unit/payment_usecases_test.dart` | start/status/retry, monto del servidor, `amount_mismatch`. |
| Unit errores | `test/unit/payment_errors_test.dart` | motivos de rechazo en español. |
| Unit efectivo | `test/unit/cash_payment_test.dart` | billetes, pago exacto, vueltas, validaciones. |
| Widget | `test/widget/payment_flow_test.dart` | carrito → Pagar → aprobado → seguimiento; rechazo → banner en carrito; efectivo con billete. |
| SQL | `supabase/tests/hu5_payments.sql` | RLS, gating del restaurante, monto del servidor, rechazo no cancela, expiración sí cancela y devuelve, efectivo, reembolso, idempotencia. |
| Firma | `supabase/functions/_shared/wompi_signature_test.ts` | checksum válido, inválido y replay (Deno). |
| Sandbox | `tool/evidence/hu5_payments/` | Nequi/Daviplata/tarjeta aprobada y rechazada + capturas del panel. |
| Arquitectura | `test/architecture_test.dart` | dominio puro; `features/buyer/cart` no importa `data/` ni Supabase; solo `lib/app/di` conoce implementaciones. |

CI: `denoland/setup-deno` + `deno test`; los SQL entran por `hu*.sql`.

## 9. Documentación

- `GUIA_SANDBOX_WOMPI.md`: paso a paso de cuenta, llaves, URL de eventos,
  secretos en Supabase, despliegue, datos de prueba y evidencia.
- `supabase/README.md`: migración `0026`, tablas, RPC, secrets, webhook.
- `DEPLOY.md`: secrets, deploy, webhook, cron y checklist de producción.
- `HANDOFF.md`: sección HU-5 con hecho/pendiente y cómo probar.
- `README.md`: Wompi, `PaymentBloc`, `url_launcher`, efectivo con billete y
  contador de pruebas.
- `AGENTS.md`: regla del slice de pagos (Bloc + dominio + secretos solo en
  Edge Functions; gating por `payment_status`).
- `INFORME_HU5_PAGOS.md`: criterios → evidencia, capturas y comandos.

## 10. Fases y estimación

| Fase | Entregable | Días |
|---|---|---|
| 1 | `0026` + RLS + SQL tests + `apply_all` + `0099` | 1.5 |
| 2 | Edge Functions Wompi + firma + sandbox | 2 |
| 3 | Dominio + efectivo + casos de uso + tests | 1 |
| 4 | Repos + GetIt + Realtime + demo | 1 |
| 5 | `PaymentBloc` + carrito + banner + `/pago` + seguimiento | 2 |
| 6 | Widget tests, ajuste de tests existentes, docs y evidencia | 1 |
| 7 | PR a `dev` con CI verde | 0.5 |
| **Total** | | **~9 días** |

## 11. Facturación y modelo de negocio (importante)

**Cobrar no es lo mismo que facturar.** La pasarela mueve el dinero; la factura
es una obligación tributaria aparte. Para esta HU y para el sandbox **no se
necesita empresa, RUT ni facturación**: Wompi deja crear la cuenta y usar el modo
pruebas, y el entregable del curso se cumple con las tarjetas/Nequi de prueba.
El flujo técnico es idéntico en sandbox y en producción.

### 11.1 Si solo es el proyecto del curso (recomendado ahora)

- Cuenta de Wompi en **modo pruebas** + llaves `*_test_*`.
- Dinero simulado, sin cobros reales, sin DIAN.
- La app registra el pago en `payments` (auditoría) y muestra un
  **comprobante de pago** con código de pedido, monto, método, id de transacción
  y fecha. Ese comprobante **no es una factura electrónica**; es un recibo de la
  app.
- Es exactamente lo que pide la HU: sandbox con aprobado y rechazado.

### 11.2 Si algún día se cobra de verdad

Wompi pide una cuenta de comercio con verificación (KYC):

- Persona natural o jurídica, cédula/NIT, RUT, cuenta bancaria (Bancolombia o
  Nequi), correo y aceptación de términos.
- Wompi cobra una **comisión por transacción** (tarifa vigente según el plan) y
  **te factura esa comisión**. La venta al comprador la factura el vendedor.
- Si la DIAN te obliga a facturar electrónicamente, debes emitir la factura de
  la venta (o el documento equivalente que corresponda). Hay regímenes y
  umbrales; eso se consulta con un contador. La pasarela no factura por ti.

### 11.3 Tres modelos posibles para Biffy

| Modelo | Quién es el comercio | Quién factura la comida | Cuándo conviene |
|---|---|---|---|
| A. Biffy como comercio | Biffy | Biffy | Piloto simple; Biffy asume la venta y la factura. |
| B. Marketplace / split | Cada restaurante | Cada restaurante | Producción real: Biffy cobra una comisión de servicio y reparte al restaurante y al repartidor (Wompi Split / pagos a terceros). Requiere alta de cada comercio. |
| C. Enlace personal | Nadie formal | Nadie | No recomendado: no hay integración, auditoría ni conciliación. |

Para el curso se implementa el modelo **A en sandbox** (una sola cuenta). El
modelo **B** se documenta como evolución: el pedido guarda `branch_id`, el pago
guarda `branch_id` y el split se puede agregar sin cambiar el `PaymentBloc`.

### 11.4 Qué deja hecho la HU

- `payments` como registro auditable (referencia, monto, método, estado, fechas).
- Un **comprobante de pago** visible en la app (no DIAN).
- Un punto de extensión para facturación electrónica: cuando se necesite, se
  agrega un `invoice_ref`/proveedor (Siigo, Alegra, Factus…) al confirmar el
  pago; el flujo de cobro no cambia.

## 12. Riesgos y notas

1. **Wompi vs la HU**: la HU menciona Wompi como ejemplo, así que cumple los
   cuatro métodos. Mercado Pago Colombia no tiene Nequi ni Daviplata.
2. **Checkout Web vs Widget**: se usa Checkout Web (redirección) para no manejar
   datos de tarjeta en la app. El comprador elige el método en la página segura
   de Wompi; la app registra el método preferido.
3. **Firma de integridad**: el orden de los campos debe copiarse del panel de
   Wompi; si se usa `expiration-time`, entra en la cadena.
4. **Webhook**: Wompi reintenta; idempotencia obligatoria. Verificar el checksum
   y luego consultar la transacción real.
5. **Cron**: confirmar que el plan de Supabase permite agendar; si no, GitHub
   Action con `CRON_SECRET`.
6. **Reembolso**: Wompi distingue anulación y reembolso; usar el endpoint que
   corresponda y registrar siempre el resultado.
7. **Test existentes**: el pago por defecto es `nequi`; la demo aprobará sola y
   habrá que ajustar los flujos que hoy llegan directo al seguimiento.
8. **Numeración**: esta HU es la 5; el repo ya tenía HU-3 (ciclo del pedido) y
   HU-4 (Gotas). El documento y la rama usan HU-5.
