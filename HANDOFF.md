# Estado del proyecto y pendientes

> Documento de traspaso. Está escrito para que **una persona o una IA** pueda
> retomar el trabajo sin adivinar qué está hecho, qué falta y cómo se trabaja.
>
> Rama de integración: **`dev`** (frontend + `supabase` unidos). Proyecto Supabase:
> `jwdzpwsfwtkdeeuceaco`.
>
> **Lee primero** [`AGENTS.md`](AGENTS.md) (reglas de arquitectura) y
> [`supabase/README.md`](supabase/README.md) (detalle de la base).

---

## 1. Cómo se corre

| Modo | Comando | Qué usa |
|---|---|---|
| Demo local (por defecto) | `flutter run` | Datos en memoria, sin red |
| Supabase | `flutter run --dart-define-from-file=env.json` | Auth, catálogo, pedidos y Storage reales |

`env.json` se copia de `env.example.json` y **no se versiona**. Sin las dos
variables (`SUPABASE_URL`, `SUPABASE_KEY`) la app arranca en demo.

**Cuentas demo (contraseña `biffy123`):**

| Rol | Correo |
|---|---|
| Comprador | `diego.demo@icesi.edu.co` |
| Repartidor | `andres.repartidor@demo.biffy.co` |
| Restaurante | `qbano@demo.biffy.co` |

La confirmación de correo está **desactivada** mientras sea demo.

---

## 2. Arquitectura en una pantalla

```text
Pantallas (lib/features/**)
   ↓ eventos / lectura
OrdersBloc (lib/features/orders/bloc)        Controladores ChangeNotifier (sesión,
   ↓ llama a                                  catálogo, carrito: aún sin migrar)
Casos de uso (lib/domain/usecases/orders)
   ↓ dependen de interfaces
Dominio: entidades, OrderRepository, puertos (lib/domain/**)  ← Dart puro
   ↑ implementan
Repositorios (lib/data/repositories/**)
   ├── InMemory…   → modo demo
   └── Supabase…   → backend real
```

HU-4 usa BLoC + Clean por feature (acuerdo del equipo):

```text
Pantalla ──► Cubit (lib/features/**/x_cubit.dart)
               ──► Caso de uso (lib/domain/usecases/)
                     ──► Interfaz (lib/domain/repositories/)
                           ◄── Supabase… / InMemory… (lib/data/repositories/)
```

Cubits de HU-4: `RateOrderCubit`, `RewardsCubit`, `MerchantBoxesCubit`,
`NotificationsCubit`, `EarningsCubit`. Se crean con GetIt (`getIt<…Cubit>()`), uno nuevo por pantalla.

Reglas que **no** se negocian:

- La regla de alcance (radio + repartidores + campus) vive solo en
  `lib/domain/catalog_rules.dart` (`isReachable`).
- Los pedidos solo cambian de estado por `OrdersBloc` → casos de uso →
  `OrderRepository`; ninguna pantalla toca `Order` ni los repositorios.
- Las reglas de negocio (precios, filtros, transiciones, horarios) son funciones
  puras en `lib/domain/` con tests.
- El modo demo (sin credenciales de Supabase) debe seguir funcionando: las pruebas lo
  levantan con `makeServices()` (GetIt en memoria, reloj fijo).

---

## 3. Qué ya está hecho

### Base de datos (aplicada y verificada)

| Pieza | Detalle |
|---|---|
| Esquema | 30 tablas físicas (24 de negocio + auxiliares), FKs, `CHECK`, índices, `updated_at` por trigger |
| RLS | Políticas por dueño y por rol; probadas con dos usuarios reales |
| RPC | `place_order`, `restaurant_accept/reject/ready`, `buyer_cancel`, `courier_accept/decline/pickup/deliver`, `redeem_reward`, `verify_university`, `register_business` |
| Storage | `dish-images` (público), `delivery-evidence` y `merchant-docs` (privados por carpeta) |
| Datos | 4 universidades, 8 puntos con geometría, 9 categorías, 5 recompensas con 18 premios, 15 sedes y 32 platos |
| Cuentas | 3 cuentas demo reales con bienvenida de 450 Gotas |

Migraciones en `supabase/migrations/` (`0000`–`0019`; la `0019_order_cycle`
es el ciclo del pedido de HU-3). El bootstrap para pegar
en el SQL Editor es `supabase/apply_all.sql` (generado concatenando las
migraciones).

### App (Fase 2a–2c)

| Archivo | Qué hace |
|---|---|
| `lib/core/config/app_config.dart` | Lee `--dart-define`; decide demo vs Supabase |
| `lib/main.dart` | `Supabase.initialize()` + restaura sesión |
| `lib/data/repositories/supabase_auth_repository.dart` | Login, registro con rol, sesión, saldo, direcciones y perfil de repartidor |
| `lib/data/repositories/supabase_catalog_repository.dart` | Catálogo con caché hidratada + Realtime |
| `lib/data/repositories/supabase_order_repository.dart` | Pedidos: caché + RPC con resultado tipado (`RpcResult`), recarga tras cada RPC, Realtime + sondeo de 30 s, sube evidencia |
| `lib/data/repositories/rpc_result.dart` | Respuesta normalizada de un RPC (`code`, `data`, `order`) |
| `lib/domain/order_errors.dart` | `result` del servidor → mensaje en español (con tests) |
| `lib/app/di/injection.dart` | Raíz de composición con **GetIt**: `configureDependencies()` registra los módulos `core`, `data`, `domain` y `presentation` (`lib/app/di/modules/`) |
| `lib/app/di/bootstrap.dart` | `bootstrapApp()`: restaura la sesión (Supabase) o carga los datos demo |
| `lib/shared/state/controller_scope.dart` | `ControllerScope` + `context.watchController<T>()`: redibujan las pantallas cuando cambia un controlador, sin Provider |
| `lib/shared/state/session_controller.dart` | `loginAsync`, `registerAsync`, `restoreAsync`, hidratación remota y persistencia de perfil |
| `lib/features/orders/bloc/` | `OrdersBloc`: eventos → casos de uso → `OrdersState` (`orders`, `revision`, `outcome`). Con servidor, **el servidor decide**: llama al RPC y el estado llega con la recarga |
| `lib/domain/usecases/orders/` | `PlaceOrder`, `CancelOrder`, `AcceptOrder`, `RejectOrder`, `MarkOrderReady`, `AcceptOffer`, `DeclineOffer`, `ConfirmPickup`, `CompleteDelivery`, `OrderQueries`; se ensamblan en `OrderUseCases` |
| `lib/domain/repositories/order_repository.dart` | Interfaz `OrderRepository` + `OrderResult` (mismos códigos en demo y servidor) |
| `lib/shared/adapters/order_adapters.dart` | Conectan los puertos del dominio con `CatalogController`, `SessionController` y `NotificationCenter` |
| `tool/admin_seed.dart` | Crea/actualiza las 3 cuentas demo con `service_role` (idempotente) |
| `supabase/functions/send-university-code/` | Envía el código al correo institucional con Resend |
| `supabase/functions/university-revalidation/` | Cron: revalida, revoca Campus y avisa |
| `test/integration/hu1_supabase_test.dart` | 13 pruebas de perfil, verificación y RLS con usuarios reales |

Verificado con un pedido real: `BF-2041` creado, aceptado, listo, asignado,
recogido y entregado (6 eventos, evidencia en Storage, +12 Gotas).

### HU-3 · Ciclo completo del pedido (comprador → restaurante → repartidor)

Código y pruebas listos; **falta aplicar `0019_order_cycle.sql` al proyecto
remoto** (ver «Cómo probarlo» abajo).

- `0019_order_cycle.sql`: `place_order` calcula precios, descuento de campus,
  tarifa, cupón, distancia y pago al repartidor en el servidor; idempotente con
  `client_key`; el código de entrega pasa a `order_secrets` (el repartidor ya
  no puede leerlo); cancelar/rechazar devuelve Gotas **y** cupón;
  `order_events.from_status`; `courier_deliver` verifica la foto en Storage;
  las ofertas solo las ven repartidores; escrituras directas revocadas;
  `credit_gotas` ya no es llamable por clientes.
- Prueba SQL de punta a punta: `supabase/tests/hu3_order_cycle.sql` (87
  comprobaciones, termina en `ROLLBACK`).
- Flutter: Clean Architecture + Bloc (ver tabla arriba), mensajes en español
  para cada `result`, doble toque protegido, reintento seguro del pedido.


### HU-1 · Autenticación y perfiles reales

- ✅ Esquema aplicado en el proyecto remoto; cuentas demo y catálogo semilla cargados.
- ✅ `tool/admin_seed.dart` crea/actualiza las 3 cuentas demo sin duplicar datos.
- ✅ Nombre y teléfono se guardan en `profiles`; el perfil de repartidor se
  guarda en `courier_profiles`.
- ✅ `verify_university` se llama desde la app; el estado verificado se
  rehidrata al volver a iniciar sesión.
- ✅ Errores de `register_business` y de conexión se muestran en español.
- ✅ Correo institucional separado del correo personal: código de 6 dígitos,
  vencimiento a 30 días y revocación de Campus sin bloquear la app.
- ✅ 13 pruebas de RLS contra el proyecto real (se saltan sin credenciales).
- ⏳ Configurar `RESEND_API_KEY`/`FROM_EMAIL` y desplegar las Edge Functions;
  hasta entonces la app usa el código demo visible en la pantalla.
- ✅ Cuentas demo verificadas en el SQL Editor: Andrés y Qbano conservan 450
  Gotas con una sola bienvenida; Diego tiene 332 porque gastó en pruebas.
  Evidencia: `tool/evidence/hu1_cuentas_demo.csv`.
- ⏳ Adjuntar al informe la salida literal de `0099_verify.sql` (la consulta ya
  se ejecutó en el SQL Editor; falta el pantallazo/texto).

### Migración a Bloc · rama `blocs`

- **Fase 1a completada:** `LoginCubit`, `RegisterCubit` y
  `UniversityVerificationCubit`; `AuthRepository`/`AuthException` viven en
  `lib/domain/repositories/` con re-export de compatibilidad.
- Las pantallas de login, registro y Campus usan los cubits; la lógica de
  sesión sigue en `SessionController` para no romper las otras 45 pantallas.
- `test/architecture_test.dart` impide que los cubits de auth importen `data/`
  o Supabase.
- **Fase 2 completada:** `CartCubit` reemplaza a `CartController` (se eliminó el
  archivo) y `CheckoutCubit` maneja el envío, la idempotencia y los errores.
  El checkout sigue usando `OrdersBloc` como única fuente de pedidos.
- **Integración con GetIt:** la rama se rebasó sobre el `dev` con inyección de
  dependencias. `CartCubit` se registra como `LazySingleton` y se publica con
  `BlocProvider` en `app.dart` (no va en `ControllerScope`: no es `Listenable`);
  `LoginCubit`, `RegisterCubit`, `UniversityVerificationCubit` y `CheckoutCubit`
  son `Factory` en `presentation_module.dart`. Las pantallas los piden con
  `getIt<T>()` y observan controladores con `context.watchController<T>()`.
- **Pendiente 1b:** `SessionBloc` que reemplace `SessionController` y migre sus
  consumidores; se hará como slice independiente.
- **Pendiente 3:** `CatalogBloc`/`ExploreCubit` y el resto de pantallas.
- Calidad de la rama: `flutter analyze` limpio · **235/235** tests ·
  21 pruebas saltadas (las que necesitan credenciales de Supabase).

### HU-4 · Gotas, recompensas, cupones, reseñas y notificaciones

Rama `hu4-gotas-recompensas-notificaciones`.

- ✅ Cupones: el descuento lo calcula `place_order` de HU-3 (`0019_order_cycle`);
  `hu4_cupones.sql` prueba que el valor de la app se ignora, y que no se usan
  cupones ajenos, vencidos o repetidos.
- ✅ `0020` canjear `free_shipping` entrega su cupón (antes cobraba sin dar nada).
- ✅ `0021` reseñas solo por `rate_order` (pedido propio, entregado, una vez,
  en la sede del pedido) y `branches.rating` con el promedio real.
- ✅ `0022` notificaciones creadas por la base en cada transición, por usuario
  y rol, en Realtime; el usuario solo puede cambiar `read_at`.
- ✅ `0023` `credit_gotas` falla si el saldo quedaría negativo (saldo = ledger)
  y respeta `biffy.internal` de quien la llama (lo necesita `hu3_order_cycle.sql`).
- ✅ `0024` envío gratis cuesta 5 Gotas.
- ✅ App: pantalla para calificar, avisos en vivo sin duplicados y en hora
  local, ganancias reales del repartidor, cajas del restaurante sin caerse en demo.
- ✅ BLoC + Clean en todas las pantallas de HU-4 (ver sección 2). Calificar usa
  el caso de uso `RateOrder` con puertos (`BranchRatingPort`, `ReviewNotifier`);
  con Supabase el notificador de pedidos es `ServerOrderNotifier` (no duplica
  los avisos que crea la base).
- ✅ Pruebas SQL de RLS/RPC (`tool/test_supabase_sql.sh`, job `sql-tests`):
  la base local trae las cuentas demo (`_demo_accounts.sql`), así que
  `hu3_order_cycle.sql` también corre ahí.
- ✅ `0020`–`0024` aplicadas en el proyecto remoto (comprobado el 2026-11-24).

### HU-5 · Pasarela de pagos (Wompi) + efectivo con billete

Rama `hu5-pasarela-pagos`.

- ✅ `0026_payments.sql` aplicada: `payments` (un intento auditable por reintento),
  `payment_events` (webhook idempotente), `orders.payment_status`,
  `payment_expires_at`, `cash_tendered` y `cash_change`; RLS y RPC
  (`payment_begin`, `payment_set_checkout`, `payment_apply`, `payment_refund`,
  `expire_pending_payments`, `payment_for_order`).
- ✅ Gating: el restaurante no ve ni acepta un pedido sin pago aprobado; los
  avisos no salen antes; la expiración cancela y devuelve Gotas/cupón; el
  efectivo queda aprobado sin pasarela.
- ✅ Edge Functions desplegadas: `create-payment`, `wompi-webhook`
  (checksum + consulta real a Wompi), `expire-payments` y `refund-payment`.
  Las llaves `WOMPI_*` viven solo en Supabase Secrets; la app recibe la URL del
  checkout.
- ✅ Flutter: `Payment`/`PaymentRepository`, casos de uso, `PaymentBloc` (7
  etapas), `/pago/:id`, apertura de Wompi, banner de rechazo con motivo y
  reintento en el checkout, billetes/vueltas del efectivo y estado del pago en
  el seguimiento.
- ✅ Pruebas: `hu5_payments.sql`, 5 pruebas Deno de firma, unit del Bloc, casos
  de uso, errores, efectivo y repositorio. `flutter analyze` limpio ·
  `flutter test` **251/251**.
- ✅ Webhook probado con un evento firmado de la transacción aprobada:
  `payment_events.result = applied` y `signature_valid = true`.
- ✅ Wompi llama al webhook con la URL configurada en **pruebas** y el secreto
  `test_events_…` correcto. Se corrigieron dos detalles: la función acepta el
  checksum del header **o** del body (algunos proxies entregan el header vacío)
  y usa `signature.sent_at` cuando el evento real no trae
  `signature.timestamp` (Wompi firma con la hora de envío en segundos).
- ✅ BF-2058 aprobado con el evento real reenviado: `payment_events.result =
  applied` y `signature_valid = true`; el restaurante recibió el aviso.
- ✅ Cron de vencidos: `.github/workflows/expire-payments.yml` cada 15 minutos
  con el secret `CRON_SECRET` (cargado en GitHub y en Supabase).
- ✅ PR **#6** mergeado en `dev` (`89823c2`); la rama `hu5-pasarela-pagos` se
  eliminó.
- ⏳ Wompi reintenta los eventos anteriores (BF-2052/BF-2057) de forma
  idempotente; el flujo real ya quedó verificado con BF-2058 y el endpoint
  acepta los eventos reales.

### HU-4 (sprint final) · Flujo completo y cierre de entrega

Rama `hu4-cierre-entrega` (desde `dev`).

- ✅ **`0027_server_guards.sql`** (aplicada en el remoto, `0099_verify` sin
  errores). Con triggers, así sirve con cualquier versión de `place_order`:
  - Horario: el pedido «Ahora» exige la sede abierta (hora de Colombia) y el
    programado, una hora dentro del horario. `app_settings.demo_lunch` simula
    las 12:00 también en el servidor.
  - Repartidores: `branches.couriers_nearby` se calcula con los repartidores
    conectados (`courier_set_online`); zona general sirve a todas las sedes y
    zona campus solo a las de su universidad. El cliente ya no lo puede escribir.
  - `sold_today` lo lleva el servidor: sube con cada ítem, valida el límite con
    la fila bloqueada, baja al cancelar (`order_items.sold_on`) y se reinicia a
    medianoche (`pg_cron`).
  - Rechazos como excepción `biffy:<código>` → `RpcResult.fromException` →
    mensaje en español (`branch_closed`, `invalid_schedule`, `no_portions`).
- ✅ El repartidor guarda su disponibilidad en el servidor al conectarse, cambiar
  de zona e iniciar sesión; se desconecta al cerrar sesión.
- ✅ Foto de evidencia para el comprador: `OrderRepository.evidenceUrl` (URL
  firmada de 1 h) → `GetDeliveryEvidence` → `DeliveryEvidenceCubit` →
  tarjeta en el seguimiento.
- ✅ Notificaciones entre dispositivos y cupones reales comprobados contra el
  proyecto real con tres sesiones: `test/integration/hu4_servidor_test.dart`.
- ✅ Carga / vacío / error con reintento: `SyncStatus` en los repositorios de
  catálogo y pedidos, `OrdersState.sync` + `OrdersRefreshRequested`, widget
  `SyncStateView`. Aviso «No hay repartidores conectados ahora».
- ✅ Sin «(simulado)» en modo Supabase donde ya es real.
- ✅ CI: jobs `integration-supabase` y `build-android`, artefactos web y APK,
  disparo manual.
- ✅ Sin secretos en el historial de git (ver `DEPLOY.md` §6).
- ✅ Documentación: `docs/ARQUITECTURA.md`, `docs/MANUAL_DE_PRUEBA.md`,
  `docs/GUION_DEMO.md`, `DEPLOY.md`.
- ⏳ **Necesita rol Owner/Admin en Supabase:** rotar la contraseña de la base,
  `service_role` y `CRON_SECRET`; activar la confirmación de correo y revisar
  los rate limits.
- ⏳ **Necesita admin del repo en GitHub:** secrets `SUPABASE_URL` y
  `SUPABASE_KEY` para que corra `integration-supabase`.
- ⏳ Evidencia en video o capturas del recorrido de `docs/MANUAL_DE_PRUEBA.md`.

Calidad actual (HU-3 + HU-4 + HU-5): `flutter analyze` limpio · `flutter test`
**266/266** (26 de integración se saltan sin credenciales; con `env.json`
pasan 22 contra el proyecto real) · pruebas SQL **237/237**.

---

## 4. Qué falta

Orden sugerido. Cada punto tiene criterio de aceptación.

### Fase 1 · Recompensas con cajas (2 días)

- ✅ `/recompensas` lee `gotas_rewards` y `gotas_reward_prizes` con Supabase.
- ✅ Abrir caja → RPC `redeem_reward` → diálogo con el premio sorteado.
- ✅ Historial de canjes desde `reward_redemptions`.
- ✅ Límites configurables en la base (`cooldown_hours`): caja de 5 ilimitada,
  el resto cada 12 h y la grande cada 24 h.
- ✅ Los restaurantes meten y sacan sus platos de las cajas (`box_items`,
  pantalla `/negocio/cajas`); el sorteo usa esos platos y cae a los premios de
  plataforma si no hay ninguno.
- ✅ Ciclo completo del plato: al ganarlo se genera un código de 6 caracteres
  (30 días) que el restaurante valida en `/negocio/cajas` → el canje pasa a
  `used`.
- ⏳ Saldo y libro de movimientos desde `gotas_ledger` (la pantalla aún usa el
  historial local en demo).
- ⏳ **Aplicar `0012_box_items.sql` y `0013_prize_claim.sql`** en el proyecto.
- **Hecho cuando:** abrir una caja descuenta en la base y al reabrir la app el
  premio sigue ahí.

### Fase 2 · Comercio real (3–4 días)

- ✅ Alta de negocio desde la app con `register_business` (cuenta + negocio +
  sede en la base).
- ✅ CRUD de platos remoto: crear, editar y borrar (borrado lógico) vía
  `SupabaseCatalogRepository.upsertDish/deleteDish`.
- ✅ Agotado y pausa de sede persistidos (`setDishSoldOut` / `setBranchPaused`).
- ✅ Fotos de platos a `dish-images/<business_id>/` con URL pública.
- **Hecho cuando:** un comerciante nuevo se registra, crea su menú y al reabrir
  ve lo mismo.

### Fase 3 · Catálogo completo (2 días)

- ✅ Catálogo cargado desde `lib/data/mock/seed_catalog.dart` con
  `tool/seed_supabase.dart` (idempotente): **14 negocios, 16 sedes, 36 platos y
  40 opciones** (tamaños, acompañantes y extras).
- ✅ Cada negocio tiene su cuenta demo (`biffy123`) como dueño real.
- ✅ `branches.location` sincronizada desde lat/lng (trigger + backfill).
- ✅ Polígono **real** de Icesi en `universities.boundary_polygon` (OSM).
  UNAL, Andes y Javeriana quedan sin polígono (respaldo por `campus_id`).
- ✅ `place_order` valida con PostGIS: radio (`ST_DWithin`) y geocerca
  (`ST_Covers`) cuando la sede es `campus_delivery_only`.
- **Hecho cuando:** el home en modo Supabase se ve igual que el demo.

### Fase 4 · Datos personales sincronizados (2–3 días)

- ✅ Direcciones (`addresses`) — crear/editar/borrar/predeterminada, con `dbId`.
- ✅ Preferencias y encuesta de 300 Gotas (`preferences` + RPC `complete_survey`).
- ✅ Favoritos (`favorite_dishes`, `favorite_branches`).
- ✅ Ajustes (`app_settings`), incluido el modo oscuro real.
- ✅ Cupones (`coupons`, `user_coupons`): los premios de caja generan cupón.
- ✅ Notificaciones persistentes (`notifications`) para el propio usuario.
- **Hecho cuando:** cerrar sesión y volver conserva todo.

- ⏳ **Verificación universitaria:** ✅ `SessionController.verifyUniversityAsync`
  llama al RPC `verify_university`, guarda `profiles.verified` /
  `university_email` y se rehidrata al iniciar sesión. Falta probar el camino
  feliz con una cuenta nueva desde la app (requiere `service_role` para
  limpiar la cuenta de prueba).

### Fase 5 · Robustez (2–3 días)

- ✅ Idempotencia de `place_order` con `client_key` (un reintento no duplica).
- ✅ Reintentos automáticos en `place_order` (3 intentos con espera).
- ✅ `ErrorView` con reintento en las pantallas que dependen de red; el resto
  lee de la caché hidratada.
- ✅ Estados de carga: checkout (`_placing`) y formulario de producto (`_saving`).
- ✅ Smoke test real en `test/integration/supabase_smoke_test.dart` (4 casos),
  gated por `--dart-define` y ejecutado en CI si hay secretos.
- ✅ CI en GitHub Actions: analyze, test, build web y smoke opcional.

### Fase 6 · Publicación (1–2 días)

- Secrets por entorno; confirmación de correo activada + plantilla en español.
- Backups/PITR, rate limits.
- **Rotar** la contraseña de la base que se compartió por chat.
- Smoke test de los tres roles en el build final.

### Backlog técnico de la base

| Prioridad | Pendiente |
|---|---|
| ✅ | `couriers_nearby` real (repartidores conectados, `0027`). Falta la ubicación en vivo del repartidor para usar PostGIS. |
| Alta | Límite diario de canjes |
| Alta | Política INSERT de `notifications` |
| Media | `branches.rating` recalculado desde `reviews` |
| Media | Jobs `pg_cron`: auto-cancelar pedidos viejos, sorteo mensual, limpiar evidencias |
| Media | Ledger de pagos (restaurante y repartidor) |
| Media | Índices trigram para buscador |
| Baja | Auditoría de cambios de catálogo |
| Baja | `profiles.active_role` (multi-rol) |

---

## 5. Reglas de trabajo

1. **Una sola base compartida.** Los pedidos y cuentas de prueba los ve todo el
   equipo.
2. **Nada de cambios de esquema desde el panel.** Cada cambio es una migración
   nueva en `supabase/migrations/`; después se regenera `apply_all.sql`
   concatenando las migraciones en orden.
3. **La app nunca usa `service_role`.** Solo scripts locales de administración.
4. **Secretos fuera del repo:** `env.json`, contraseñas y `service_role` no se
   versionan.
5. Antes de subir: `flutter analyze` y `flutter test` en verde.
6. Commits pequeños; la rama de integración es `supabasev2` (creada desde `dev`).
7. **Comenta cada clase, función y widget** con una línea corta de qué es o qué
   hace (`///` en miembros públicos). Es requisito para dar algo por terminado.

---

## 6. Trampas conocidas (leer antes de tocar código)

| Tema | Detalle |
|---|---|
| Auth síncrona vs asíncrona | La demo usa `login/register` (síncronos, los tests dependen de ellos). Las pantallas usan `loginAsync/registerAsync`. No mezclar. |
| IDs de pedido | `Order.id` es el código visible (`BF-2041`); `Order.dbId` es el uuid de la base. Los RPC usan **`dbId`**. Si es `null`, el pedido aún no llegó a la base. |
| Servidor primero | Con Supabase el pedido **no** se crea ni cambia de estado localmente: se llama al RPC y el estado llega con la recarga. Si el RPC falla no queda nada a medias. En demo todo sigue siendo local e inmediato. |
| Un solo API | Las pantallas despachan eventos al `OrdersBloc` (`add`) o esperan el resultado con `await bloc.request(evento)`. No hay API síncrona de pedidos. Los tests de reglas usan `bloc.useCases.<caso de uso>(...)`. |
| Código de entrega | Vive en `order_secrets` (solo el comprador). El repartidor lo recibe vacío y lo valida el servidor; no compares códigos en la app. |
| Direcciones y cupones | Hasta la HU de datos personales son locales (sin uuid). Con servidor, `validate()` pide una dirección guardada en la cuenta y bloquea cupones locales. |
| Alcance | `isReachable` exige `couriersNearby > 0`. En demo es simulado (la sede demo tiene 3); con Supabase lo calcula la `0027` con los repartidores **conectados**: sin ninguno, el comprador no ve sedes. |
| Realtime | Requiere `0010` y `0022` (publican `branches`, `dishes`, `orders`, `order_events` y `notifications`). El estado `subscribed` llega un poco antes de que el servidor registre la escucha: en pruebas, espera ~3 s antes del primer cambio. |
| Reglas por trigger | Horario, porciones y `sold_today` (`0027`) se lanzan como excepción `biffy:<código>`, no como `result`. Si agregas una regla así, añade el código a `order_errors.dart`. Las pruebas SQL fijan la hora con `set biffy.now = '…'`. |
| `businesses` | Tiene RLS de dueño: el comprador no ve negocios (solo sedes y platos). `businessById` solo lo usan pantallas de comercio. |
| Evidencia | Se sube a `delivery-evidence/<order_uuid>/`; `courier_deliver` exige que el objeto exista. Máx. 5 MB, jpeg/png/webp. El bucket es privado: el comprador la ve con URL firmada de 1 h (`evidenceUrl`). |
| Fechas | `timestamptz` llega en UTC: el mapeo usa `.toLocal()` y `scheduled_for` se envía con `.toUtc()`. Sin eso las horas y los días (ganancias, seguimiento) salen corridos 5 h. |
| Imágenes | `image_url` acepta una ruta `assets/...` o una URL de Storage; `catalogImage` en `lib/core/widgets/ui.dart` elige asset o red. Hoy las 4 filas de Qbano tienen `null` (se ve el emoji). |
| Ids demo | En Supabase las sedes tienen uuid: no enlazar a ids fijos como `qbano-icesi`; usar `CatalogController.qbanoIcesi` o buscar en el catálogo. |
| Datos locales | Preferencias, favoritos, ajustes y cupones **no** se guardan en Supabase todavía (Fase 4). |
| Datos de prueba | Existe el pedido `BF-2041` entregado y `legacy_gotas_rewards` (tabla antigua conservada y bloqueada). |
| Confirmación de correo | Desactivada a propósito. Al publicar hay que activarla. |
| Registro abierto | `disable_signup = false`: cualquiera con la URL y la clave publicable puede crear cuenta. Es aceptable en demo, no en producción. |

---

## 7. Cómo verificar el estado

```bash
flutter analyze
flutter test
flutter run --dart-define-from-file=env.json
```

En la base (SQL Editor o `psql`):

```sql
select count(*) from public.gotas_rewards;        -- 4
select count(*) from public.gotas_reward_prizes;  -- 15
select code, status from public.orders order by created_at desc limit 5;
select status from public.order_events order by created_at desc limit 6;
```

Pruebas SQL sin tocar el proyecto (Docker):

```bash
tool/test_supabase_sql.sh
```

Si `gotas_reward_prizes` no existe, falta aplicar `0008`.
Si la app no se refresca sola, falta `0010`.
Si `place_order` responde `total_mismatch` siempre o no existe `order_secrets`,
falta aplicar `0019`.

### Probar la HU-3 (ciclo del pedido)

1. **Base:** SQL Editor → pegar `supabase/apply_all.sql` → Run (debe terminar
   con `Biffy OK · 30 tablas …`). Si solo falta lo nuevo, basta
   `supabase/migrations/0019_order_cycle.sql`.
2. **Prueba SQL:** pegar `supabase/tests/hu3_order_cycle.sql` → Run. Debe
   imprimir ~87 líneas `PASS` y ningún `FALLO`; no deja datos (`ROLLBACK`).
3. **App:** copiar `env.example.json` a `env.json` y correr
   `flutter run --dart-define-from-file=env.json` (usa dos o tres dispositivos
   o ventanas, una por rol).
4. **Flujo:** comprador `diego.demo@icesi.edu.co` pide → restaurante
   `qbano@demo.biffy.co` acepta y marca listo → repartidor
   `andres.repartidor@demo.biffy.co` acepta, recoge y entrega con el código que
   ve el comprador y una foto → comprobar `orders`, `order_events` y
   `gotas_ledger`.

---

## 8. Glosario

| Término | Significado |
|---|---|
| Gota | Moneda de fidelidad. 1 Gota = $10 COP (`kGotaValue`) |
| Caja | Recompensa aleatoria (`mystery_box` / `monthly_raffle`) con premios ponderados |
| Sede / branch | Restaurante físico (`branches`) de un negocio (`businesses`) |
| Punto de entrega | Lugar del campus o casa (`delivery_points`) que fija la regla de alcance |
| RPC | Función Postgres expuesta por PostgREST; única vía de escritura de pedidos |
