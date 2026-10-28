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
   ↓ solo lectura/acciones
Controladores ChangeNotifier (lib/shared/state/**)
   ↓ contratos síncronos
Repositorios (lib/data/repositories/**)
   ├── InMemory…   → modo demo
   └── Supabase…   → backend real
```

Reglas que **no** se negocian:

- La regla de alcance (radio + repartidores + campus) vive solo en
  `lib/domain/catalog_rules.dart` (`isReachable`).
- Los pedidos solo cambian de estado por `OrderService`; ninguna pantalla toca
  `Order`.
- Las reglas de negocio (precios, filtros, transiciones, horarios) son funciones
  puras en `lib/domain/` con tests.
- `AppServices.demo()` debe seguir funcionando: **los 104 tests dependen de él**.

---

## 3. Qué ya está hecho

### Base de datos (aplicada y verificada)

| Pieza | Detalle |
|---|---|
| Esquema | 27 tablas, FKs, `CHECK`, índices, `updated_at` por trigger |
| RLS | 43 políticas: catálogo público, datos por dueño, pedidos por rol |
| RPC | `place_order`, `restaurant_accept/reject/ready`, `buyer_cancel`, `courier_accept/decline/pickup/deliver`, `redeem_reward`, `verify_university`, `register_business` |
| Storage | `dish-images` (público), `delivery-evidence` y `merchant-docs` (privados por carpeta) |
| Datos | 4 universidades, 8 puntos con geometría, 9 categorías, 4 recompensas con premios, 1 negocio (Qbano Icesi) con 4 platos |
| Cuentas | 3 cuentas demo reales, 450 Gotas cada una |

Migraciones en `supabase/migrations/` (`0000`–`0011`). El bootstrap para pegar
en el SQL Editor es `supabase/apply_all.sql` (generado concatenando las
migraciones).

### App (Fase 2a–2c)

| Archivo | Qué hace |
|---|---|
| `lib/core/config/app_config.dart` | Lee `--dart-define`; decide demo vs Supabase |
| `lib/main.dart` | `Supabase.initialize()` + restaura sesión |
| `lib/data/repositories/supabase_auth_repository.dart` | Login, registro con rol, sesión, saldo, direcciones y perfil de repartidor |
| `lib/data/repositories/supabase_catalog_repository.dart` | Catálogo con caché hidratada + Realtime |
| `lib/data/repositories/supabase_order_repository.dart` | Pedidos: cache, mapeo y RPC; sube evidencia |
| `lib/shared/state/app_services.dart` | `AppServices.demo()` y `AppServices.supabase()` |
| `lib/shared/state/session_controller.dart` | `loginAsync`, `registerAsync`, `restoreAsync`, hidratación remota |
| `lib/shared/state/order_service.dart` | Réplica de cada transición por RPC |

Verificado con un pedido real: `BF-2041` creado, aceptado, listo, asignado,
recogido y entregado (6 eventos, evidencia en Storage, +12 Gotas).

Calidad actual: `flutter analyze` limpio · `flutter test` **104/104**.

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

> **Pendiente asignado a otra persona:** verificación universitaria desde la
> pantalla. El RPC `verify_university` ya existe y valida el dominio; falta que
> `SessionController.verifyUniversity` lo llame y refresque
> `profiles.verified` / `university_email`. Ver el TODO en
> `lib/shared/state/session_controller.dart`.

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
| Alta | `couriers_nearby` real (repartidores online + PostGIS) |
| Alta | Límite diario de canjes |
| Alta | Idempotencia de `place_order` |
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
| Escritura optimista | `place_order` se dispara después de crear el pedido local. Si el RPC falla, el pedido queda solo en memoria (gap de Fase 5). |
| `dbId` tardío | Se asigna cuando responde el RPC. Una transición en ese primer segundo puede no replicarse. |
| Alcance | `isReachable` exige `couriersNearby > 0`. Es un valor simulado (default 1); la sede demo tiene 3. |
| Realtime | Requiere `0010_realtime.sql` aplicado (publica `branches`, `dishes`, `orders`, `order_events`). Sin él todo funciona, pero hay que reabrir la app. |
| `businesses` | Tiene RLS de dueño: el comprador no ve negocios (solo sedes y platos). `businessById` solo lo usan pantallas de comercio. |
| Evidencia | Se sube a `delivery-evidence/<order_uuid>/`. El bucket es privado: para mostrarla hace falta URL firmada. |
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

Si `gotas_reward_prizes` no existe, falta aplicar `0008`.
Si la app no se refresca sola, falta `0010`.

---

## 8. Glosario

| Término | Significado |
|---|---|
| Gota | Moneda de fidelidad. 1 Gota = $10 COP (`kGotaValue`) |
| Caja | Recompensa aleatoria (`mystery_box` / `monthly_raffle`) con premios ponderados |
| Sede / branch | Restaurante físico (`branches`) de un negocio (`businesses`) |
| Punto de entrega | Lugar del campus o casa (`delivery_points`) que fija la regla de alcance |
| RPC | Función Postgres expuesta por PostgREST; única vía de escritura de pedidos |
