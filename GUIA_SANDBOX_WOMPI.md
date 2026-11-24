# Guía paso a paso · Sandbox de Wompi (HU-5)

Esta guía deja el sandbox listo para probar Nequi, Daviplata, tarjeta y PSE sin
mover dinero real. Se apoya en la documentación oficial de Wompi:
<https://docs.wompi.co/docs/colombia/datos-de-prueba-en-sandbox> y
<https://docs.wompi.co/docs/colombia/eventos>.
Los nombres del panel pueden cambiar; si algo no coincide, busca la sección
equivalente en `comercios.wompi.co`.

## 1. Cuenta de comercio

1. Entra a <https://comercios.wompi.co> y crea una cuenta (o inicia sesión).
2. Completa los datos del comercio. Para sandbox no necesitas cobrar de verdad,
   pero la cuenta debe existir y estar activa.
3. En el panel, activa **Modo pruebas** (en *Desarrollo* o
   *Programadores*, según la versión del panel).

## 2. Llaves de prueba

En **Desarrollo → Programadores / Credenciales**, con el modo pruebas activo,
copia las cuatro llaves:

| Llave | Prefijo típico | Dónde se usa |
|---|---|---|
| Llave pública de prueba | `pub_test_...` | URL del Checkout Web |
| Llave privada de prueba | `prv_test_...` | Consultar/anular transacciones (solo servidor) |
| Secreto de integridad de prueba | `test_integrity_...` | Firma del checkout |
| Secreto de eventos de prueba | `test_events_...` | Verificar el webhook |

> La llave privada y los secretos **nunca** van a la app ni al repositorio.

## 3. URL de eventos (webhook)

1. En el panel, abre **Desarrollo → Eventos / Webhooks** y configura la URL de
   eventos del ambiente de pruebas:
   ```
   https://<PROJECT_REF>.supabase.co/functions/v1/wompi-webhook
   ```
   (`<PROJECT_REF>` es `jwdzpwsfwtkdeeuceaco` en este proyecto).
2. Activa el evento `transaction.updated`.
3. Wompi reintenta hasta 3 veces en 24 h si no recibe `HTTP 200`; la función
   debe ser idempotente.

## 4. Secretos en Supabase

Con el CLI de Supabase autenticado y el proyecto vinculado:

```bash
supabase secrets set \
  WOMPI_PUBLIC_KEY=pub_test_xxx \
  WOMPI_PRIVATE_KEY=prv_test_xxx \
  WOMPI_INTEGRITY_SECRET=test_integrity_xxx \
  WOMPI_EVENTS_SECRET=test_events_xxx \
  WOMPI_ENV=sandbox \
  CRON_SECRET=una-cadena-larga-aleatoria
```

En este repo también puedes guardar los valores en
`supabase/functions/.env` (está en `.gitignore`) y cargarlos de una vez:

```bash
npx supabase secrets set --env-file supabase/functions/.env --remote=jwdzpwsfwtkdeeuceaco --yes
```

Verifica (solo muestra nombres y hashes, nunca los valores):

```bash
npx supabase secrets list --remote=jwdzpwsfwtkdeeuceaco
```

**Estado actual:** las 6 llaves están cargadas en el proyecto `Biffy`
(`jwdzpwsfwtkdeeuceaco`), el proyecto está **activo**, la migración `0026` ya
se aplicó y las cuatro Edge Functions están desplegadas y `ACTIVE`. Falta
configurar la URL de eventos en Wompi y hacer la compra de prueba.

## 5. Desplegar las Edge Functions

```bash
supabase functions deploy create-payment
supabase functions deploy wompi-webhook
supabase functions deploy expire-payments
supabase functions deploy refund-payment
```

`wompi-webhook`, `expire-payments` y `refund-payment` deben quedar con
`verify_jwt = false` (configurado en `supabase/config.toml`) y validar su propio
secreto/firma dentro de la función.

## 6. Aplicar la base de datos

```bash
dart run tool/generate_apply_all.dart
```

Luego aplica `supabase/migrations/0026_payments.sql` (o pega `apply_all.sql` en
el SQL Editor) y corre `0099_verify.sql`. Debe decir `Biffy OK`.

## 7. Datos de prueba

> Copia estos datos de la página oficial de sandbox de Wompi; si el panel o la
> documentación muestran otros, usan los del panel.

### Tarjetas

| Escenario | Número | Resultado |
|---|---|---|
| Aprobada | `4917 4800 0000 0057` | `APPROVED` |
| Rechazada | `4917 4800 0000 0008` | `DECLINED` |

Usa cualquier fecha futura y cualquier CVV. El nombre del titular también puede
cambiar el resultado en algunos sandbox (p. ej. `APPROVED` / `DECLINED`).

### Nequi

- Número aprobado: `3991111111`.
- En el checkout elige Nequi, ingresa ese número y confirma en la app de
  pruebas.

### Daviplata

- Número de prueba para token/transacción: `3991111111`.
- Sigue el flujo de Daviplata del checkout; el sandbox simula la aprobación.

### PSE

- Elige PSE, cualquier banco de la lista de pruebas y completa el redirect.
- Wompi simula la respuesta del banco.

## 8. Probar el flujo completo

1. En la app, inicia sesión como comprador demo.
2. Arma el carrito, elige horario y método (Nequi/Daviplata/tarjeta/PSE).
3. Pulsa **Pagar**. Debe abrirse el Checkout Web de Wompi.
4. Paga con el dato de prueba.
5. Verifica:
   - `payments.status = 'approved'` y `orders.payment_status = 'approved'`.
   - El pedido aparece en el panel del restaurante **solo después** de aprobar.
   - El webhook dejó una fila en `payment_events`.
6. Repite con la tarjeta rechazada:
   - Vuelve al carrito con el banner rojo y el motivo.
   - El pedido sigue pendiente y **no** aparece en el restaurante.
   - Al reintentar con la tarjeta aprobada, se aprueba el mismo pedido.
7. Prueba el efectivo:
   - Elige efectivo, un billete de $50.000 y verifica las vueltas.
   - El pedido aparece de inmediato en el restaurante con "Paga con $50.000 ·
     Vueltas $…".

## 9. Evidencia para el informe

Guarda en `tool/evidence/hu5_payments/`:

- Captura del panel de Wompi con la transacción aprobada (sandbox) y su id.
- Captura de la transacción rechazada con el motivo.
- Salida de `select * from payments where order_id = '...'` con estados y
  fechas.
- Salida de `select * from payment_events` con el evento del webhook.
- Captura del pedido oculto en el restaurante antes de aprobar y visible
  después.
- Captura del carrito con el banner de rechazo y el motivo.

## 10. Pasar a producción (cuando toque)

1. Completa la verificación del comercio en Wompi.
2. Copia las llaves de producción (`pub_prod_`, `prv_prod_`,
   `prod_integrity_`, `prod_events_`).
3. Cambia los secretos de Supabase y `WOMPI_ENV=production`.
4. Configura la URL de eventos de producción.
5. Haz una compra real mínima y verifica el webhook y la conciliación.
6. Reembolsa esa compra de prueba y guarda la evidencia.

## 11. Errores comunes

| Síntoma | Causa probable |
|---|---|
| El checkout dice "firma inválida" | Orden de campos o secreto de integridad incorrecto; revisa el panel. |
| El webhook devuelve 401 | El checksum no coincide. La función acepta header o body y usa `signature.sent_at` si no viene `signature.timestamp`; si ambos fallan, el `WOMPI_EVENTS_SECRET` del panel y el de Supabase no son el mismo. |
| El webhook no llega | URL mal escrita, función no desplegada o `verify_jwt` activo. |
| El pago queda `pending` | Wompi aún no confirma; espera el evento o corre `check-payment`. |
| El pedido no aparece en el restaurante | `payment_status` no está en `approved` (RLS). |
| Doble pedido al reintentar | Se creó otro `place_order` en vez de reutilizar el pendiente. |
| `cash_tendered` inválido | El billete es menor al total o falta en el payload. |

## 12. Siguientes pasos (orden exacto)

- [x] Restaurar el proyecto Supabase `jwdzpwsfwtkdeeuceaco`.
- [x] Aplicar la migración `0026_payments.sql` y verificar con `0099_verify.sql`.
- [x] Desplegar `create-payment`, `wompi-webhook`, `expire-payments` y
  `refund-payment` (las cuatro están `ACTIVE`).
- [x] Configurar en el panel de Wompi (ambiente de **pruebas**) la URL de
  eventos:
  `https://jwdzpwsfwtkdeeuceaco.supabase.co/functions/v1/wompi-webhook`
  con el evento `transaction.updated`.

  > La URL es **solo** el endpoint. No le agregues `evento: transaction.updated`
  > al final (eso produce `404 Requested function was not found`); el evento se
  > selecciona aparte en la lista del panel.
- [x] Wompi llama al webhook. Se corrigió el `401`: se acepta el checksum del
  header o del body, se recorta el secreto y se usa `signature.sent_at` cuando
  el evento real no trae `signature.timestamp`. BF-2058 quedó aprobado con el
  evento real (`signature_valid = true`).

- [x] Compra aprobada en sandbox (`BF-2046`, $23.910, VISA-0057). Se aplicó
  manualmente porque la URL de eventos aún no estaba configurada; el siguiente
  pago debe entrar solo por el webhook.
- [x] Webhook probado con un evento firmado de esa misma transacción:
  `payment_events.result = applied` y `signature_valid = true`.
- [x] Flutter: `PaymentBloc`, `/pago/:id`, banner de rechazo con motivo,
  reintento y efectivo con billetes/vueltas.
- [x] Cron de vencidos: `.github/workflows/expire-payments.yml` cada 15 minutos
  con el secret `CRON_SECRET` (ya configurado en GitHub y Supabase).
- [—] Compra rechazada y carpeta de evidencia: **no se adjuntan**; el equipo
  mostrará el proceso al profesor.
- [x] PR #6 mergeado en `dev` (`89823c2`) y rama `hu5-pasarela-pagos` eliminada.

### Seguridad de las llaves

- Los valores reales están solo en `supabase/functions/.env` (ignorado por Git)
  y en los secretos del proyecto Supabase. El repositorio solo lleva
  `supabase/functions/.env.example` con marcadores.
- `secrets list` muestra **nombres y hashes**, no los valores.
- Si el proyecto se comparte por zip o se sube a otro sitio, excluye
  `supabase/functions/.env`.
- Si las llaves se filtran fuera de este equipo, regéneralas en el panel de
  Wompi y vuelve a cargarlas. Al ser `*_test_*` el riesgo es bajo, pero es la
  misma disciplina que con producción.
