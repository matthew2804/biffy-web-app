# Base de datos · Biffy (Supabase)

Proyecto: `jwdzpwsfwtkdeeuceaco` · URL: `https://jwdzpwsfwtkdeeuceaco.supabase.co`

## Estado

| Fase | Estado |
|---|---|
| Esquema, RLS, RPC, Storage y seed de referencia | ✅ escrito en `supabase/migrations/` |
| Aplicado al proyecto remoto | ⏳ pendiente (requiere credenciales de administración) |
| App conectada (`supabase_flutter`) | ⏳ siguiente fase |

La app **sigue funcionando en modo demo local**: sin `SUPABASE_URL` no hace
ninguna petición de red.

## Cómo aplicar (una sola vez)

### Opción A · Dashboard (la más rápida, sin instalar nada)

1. Abre el proyecto en <https://supabase.com/dashboard>.
2. **SQL Editor → New query**.
3. Pega el contenido completo de [`apply_all.sql`](apply_all.sql) y pulsa **Run**.
4. Verifica en **Table Editor** que aparecen las tablas y que `universities`,
   `delivery_points` y `categories` tienen filas. Al final del run debe salir
   un aviso `Biffy OK · … tablas · … políticas RLS`.

`apply_all.sql` es idempotente: si algo falla a mitad, se puede volver a
ejecutar. La limpieza de las tablas viejas queda marcada en `_biffy_meta`, así
que un segundo run no borra nada.

> El SQL Editor ejecuta el script en **una sola transacción**: si falla una
> sentencia, se revierte todo y no queda nada a medias.

### Opción B · CLI (recomendada para el equipo)

```bash
npm i -g supabase
supabase login
supabase link --project-ref jwdzpwsfwtkdeeuceaco
supabase db push          # aplica supabase/migrations/*.sql
```

Desde ahí, **todo cambio futuro es una migración nueva**. No se edita el
esquema desde el panel: así la base queda versionada y reproducible.

## Estructura

```text
supabase/
  config.toml                     # configuración del CLI
  apply_all.sql                   # bootstrap generado (pegar en el SQL Editor)
  migrations/
    0000_legacy_cleanup.sql       # reemplaza `public` (con datos → `legacy_*`)
    0001_init.sql                 # extensiones, enums, secuencias, updated_at
    0002_schema.sql               # tablas, FKs, checks e índices
    0003_functions.sql            # RPC de negocio + triggers de identidad
    0004_rls.sql                  # RLS y políticas por rol
    0005_storage.sql              # buckets y políticas de archivos
    0006_seed_reference.sql       # universidades, puntos, categorías, recompensas
    0008_reward_boxes.sql         # premios por caja + sorteo ponderado
    0009_welcome_gotas.sql        # 450 Gotas al crear el perfil
    0010_realtime.sql             # publica branches/dishes/orders en Realtime
    0099_verify.sql               # verifica tablas, columnas y RPC clave
```

> `apply_all.sql` se regenera concatenando `migrations/*.sql`. No se edita a
> mano.

## Modelo

```text
universities ─┬─ delivery_points
              └─ branches.campus_id

profiles ─┬─ businesses ── branches ── dishes ── dish_options
          ├─ addresses
          ├─ preferences / app_settings
          ├─ gotas_ledger
          ├─ gotas_rewards ─┬─ gotas_reward_prizes
          │                 └─ reward_redemptions
          ├─ coupons (vía user_coupons)
          ├─ favorite_dishes / favorite_branches
          ├─ courier_profiles
          └─ orders ── order_items / order_events / order_declines / reviews
```

Decisiones pensadas para no volver a tocar la base:

- **Dinero en `int` (COP)**, nunca `float`.
- **`timestamptz`** en UTC; la app formatea a `America/Bogota`.
- **Enums** para estado de pedido, rol, vehículo, zona y tipo de cupón.
- **Borrado lógico** (`deleted_at`) en catálogo y direcciones.
- **`updated_at` por trigger** en las 9 tablas mutables.
- **Índices** en todas las FKs y en `orders (status)` / ofertas disponibles.
- **IDs**: `uuid` generado por la base; `orders.code` (`BF-2041`) con secuencia.
- **RPC con un `jsonb` de entrada**: se agregan campos sin cambiar firmas.
- **PostGIS opcional**: si la extensión existe se conservan
  `universities.boundary_polygon` y `location` en sedes y puntos de entrega
  (el radio actual sigue usando lat/lng; esto habilita `ST_DWithin` después).
- **Nunca toca objetos de extensiones**: la limpieza de `0000` filtra por
  `pg_depend` (PostGIS deja `spatial_ref_sys`, `geometry_columns`… en `public`).

## Seguridad

- RLS activo en las 24 tablas. Sin política = sin acceso.
- El catálogo es público solo en lectura y solo si está activo.
- Las cuentas bancarias y documentos del negocio **no** son públicos
  (`businesses_public` solo expone marca, cocina y descripción).
- `profiles` tiene un trigger que impide que el cliente se cambie el rol, las
  Gotas o la verificación.
- Un pedido lo ven solo: su comprador, su repartidor, el restaurante dueño de
  la sede y (mientras no tenga repartidor) los repartidores disponibles.
- Las escrituras de pedidos no tienen política: solo entran por RPC
  `security definer`.
- Storage: `dish-images` público; `delivery-evidence` y `merchant-docs`
  privados por carpeta (pedido / negocio).
- La app solo lleva la **clave publicable**. La `service_role` y la contraseña
  de la base nunca van al repositorio.

## RPC disponibles

| Función | Quién | Qué hace |
|---|---|---|
| `place_order(payload)` | comprador | Crea pedido + líneas + evento, quema Gotas y cupón |
| `restaurant_accept(order)` | restaurante | `pending → preparing` |
| `restaurant_reject(order, reason)` | restaurante | `pending → cancelled` + reembolso de Gotas |
| `restaurant_ready(order)` | restaurante | `preparing → ready` |
| `buyer_cancel(order)` | comprador | `pending → cancelled` + reembolso |
| `courier_accept(order)` | repartidor | Asignación atómica (`already_assigned`, `busy`, `out_of_range`) |
| `courier_decline(order)` | repartidor | Registra el rechazo de la oferta |
| `courier_pickup(order)` | repartidor | `ready → on_the_way` |
| `courier_deliver(order, code, evidence)` | repartidor | Valida código y evidencia, entrega y acredita Gotas |
| `redeem_reward(payload)` | comprador | Canjea con Gotas; en cajas sortea un premio ponderado |
| `use_reward_redemption(code)` | restaurante | Valida el código del plato ganado y lo marca como reclamado |
| `verify_university(payload)` | comprador | Verifica el correo contra el dominio de la universidad |
| `register_business(payload)` | restaurante | Crea negocio + sedes y lo vincula al perfil |

Todas devuelven `jsonb` con `result` (`ok`, `invalid_state`, `forbidden`,
`already_assigned`, `wrong_code`, `missing_evidence`, …) para mapear directo a
los enums de Dart.

## Recompensas (Gotas)

El catálogo está en `gotas_rewards` y cada caja tiene sus premios con peso en
`gotas_reward_prizes`. `redeem_reward` descuenta las Gotas y sortea el premio:

| Caja | Costo | Límite | Premios |
|---|---|---|---|
| `box_5` · Caja básica | 5 | **ilimitada** | platos de restaurantes o premios de plataforma |
| `free_shipping` | 10 | cada 12 h | quita el envío del pedido |
| `box_25` · Caja sorpresa | 25 | cada 12 h | 5 premios |
| `box_50` · Caja premium | 50 | cada 12 h | 5 premios |
| `box_100` · Caja sorteo | 100 | cada 24 h | 5 premios + boleto |

Los límites son columnas (`cooldown_hours`, `daily_limit`): se cambian con un
`update`, sin tocar código. Los restaurantes meten sus platos en `box_items`
(pantalla `/negocio/cajas`); el sorteo los usa primero y, si una caja no tiene
platos, cae a `gotas_reward_prizes`.

El peso es relativo: se suma y se sortea con `random()`, así que ajustar
probabilidades es cambiar `weight` (en `0008_reward_boxes.sql` o con un
`update`), nunca código de la app. El premio queda guardado en
`reward_redemptions` (`prize_label`, `prize_type`, `prize_amount`).

## Cuentas demo

Se crean en Supabase Auth (no en memoria) para probar los tres roles contra la
base. Contraseña: **`biffy123`**.

| Rol | Correo | Nombre |
|---|---|---|
| Comprador | `diego.demo@icesi.edu.co` | Diego (demo) |
| Repartidor | `andres.repartidor@demo.biffy.co` | Andrés (demo) |
| Restaurante | `qbano@demo.biffy.co` | Qbano (demo) |

Requisito: **Authentication → Providers → Email → "Confirm email" desactivado**.
Con la confirmación activa el alta queda pendiente y la cuenta no puede entrar.

**Estado: ✅ creadas.**

- **Diego**: comprador verificado con `@icesi.edu.co` y una dirección guardada.
- **Andrés**: `courier_profiles` con moto, zona campus y `online = true`.
- **Qbano**: negocio + sede *Qbano Icesi* + 4 platos en `dishes`.
- Las tres con 450 Gotas de bienvenida.

Al registrarse:

- `handle_new_user` crea el perfil con el rol que llega en `user_metadata`;
- el trigger de bienvenida acredita **450 Gotas**;
- el repartidor obtiene su fila en `courier_profiles`;
- el restaurante crea negocio y sede con `register_business`.

## Datos demo

```bash
dart run tool/seed_supabase.dart
```

Carga el catálogo de `lib/data/mock/seed_catalog.dart` (negocios, sedes, platos
y opciones) usando el mismo seed que la app. Es **idempotente**: crea lo que
falta, completa campos y no duplica. Cada negocio queda con su cuenta de dueño
(contraseña `biffy123`).

## Smoke test contra el proyecto

```bash
flutter test test/integration/supabase_smoke_test.dart \
  --dart-define=SUPABASE_URL=https://jwdzpwsfwtkdeeuceaco.supabase.co \
  --dart-define=SUPABASE_KEY=<clave publicable>
```

Valida perfil, catálogo, recompensas y que RLS no filtre pedidos ajenos. Sin
`--dart-define` el test se salta (el `flutter test` normal no toca la red).

## Campus y geocerca

`universities.boundary_polygon` guarda el contorno de cada campus (SRID 4326).

| Universidad | Polígono |
|---|---|
| Icesi | ✅ contorno real de OpenStreetMap (`relation/6784907`, migración `0015`) |
| UNAL, Andes, Javeriana (Bogotá) | ⛔ sin polígono: la geocerca usa el respaldo por `campus_id` |

La migración `0014` sincroniza `branches.location` con un trigger y deja una
validación con PostGIS en `place_order`.

**Reemplazar por el contorno real:**

```sql
-- GeoJSON del campus (OpenStreetMap → Exportar, o el plano de la universidad)
update public.universities
   set boundary_polygon = st_setsrid(st_geomfromgeojson('{"type":"Polygon","coordinates":[...]}'), 4326)
 where id = 'icesi';
```

Comprobación:

```sql
select id, st_asgeojson(boundary_polygon) from public.universities;
```

**Activar la geocerca en una sede** (`place_order` la aplica solo cuando la sede
es `campus_delivery_only`):

```sql
update public.branches set campus_delivery_only = true where campus_id = 'icesi';
```

> `Qbano · Icesi` ya viene con `campus_delivery_only = true`, así que la
> geocerca está activa ahí.

## Pendiente para cerrar la base1. Aplicar `apply_all.sql` (o `supabase db push`).
2. Crear las cuentas demo en Auth y cargar el catálogo semilla
   (`businesses`, `branches`, `dishes`) con la `service_role` desde un script
   de administración, nunca desde la app.
3. Activar respaldos/PITR en el plan del proyecto.

## Al desplegar (checklist)

Modo demo local hoy → Supabase real al publicar. En orden:

1. **Aplicar migraciones** (`apply_all.sql` o `db push`).
2. **Auth:** definir si el registro envía correo de confirmación.
   - Demo/staging: desactivado (Authentication → Providers → Email → *Confirm email* off).
   - Producción: activado + plantilla de correo en español.
3. **Cuentas demo:** crearlas con `service_role` desde un script local
   (`admin.createUser`), nunca desde la app. Mismos correos del README.
4. **Catálogo semilla:** cargar negocios, sedes y platos con el mismo script.
   Necesita un `owner_id` real, por eso no va en la migración.
5. **Claves:** `env.json`/secrets del CI con `SUPABASE_URL` y la clave
   publicable. La `service_role` solo en el script de administración.
6. **Límites:** revisar *Auth → Rate limits* y el tamaño máximo de subida.
7. **Respaldos:** activar PITR/backups según el plan (el plan Free no los
   incluye).
8. **Rotar** cualquier clave o contraseña que se haya compartido por chat.
9. **Smoke test:** registro → pedido → aceptar en restaurante → aceptar como
   repartidor → recoger → entregar, verificando `orders`, `order_events` y
   `gotas_ledger`.

## Si `apply_all.sql` falla

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `Tabla public.X conservada como public.legacy_X` (notice) | La tabla tenía datos | No es un error: los datos siguen ahí, bloqueados. Migrarlos cuando se decida |
| `permission denied for schema auth` | Se ejecutó con una conexión que no es `postgres` | Usar el SQL Editor del Dashboard o `db push` |
| `column "..." does not exist` | Quedó una tabla vieja con otro esquema | Confirmar que el script es el último `apply_all.sql` (0000 vacía `public`) |
| `type "user_role" already exists` | Migración parcial previa | Volver a ejecutar: el script es idempotente |
| `relation "X" already exists` | Tabla del proyecto con el mismo nombre y otro esquema | Reportar el nombre; se agrega una migración de reconciliación |

Cualquier otro error: copiar el mensaje completo (no la captura) y abrir un
issue o pasarlo al equipo; nunca aplicar cambios a mano en el panel para
"arreglarlo".
