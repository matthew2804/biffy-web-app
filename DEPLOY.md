# Despliegue

Guía para publicar Biffy con Supabase. Lo que se hace en el **Dashboard** no se
puede automatizar desde el repo; lo demás sí.

---

## 1. Base de datos

1. Confirmar que las migraciones están aplicadas:
   ```sql
   select count(*) from public._biffy_meta;          -- 1 fila (marcador)
   select count(*) from public.gotas_reward_prizes;  -- > 0
   ```
2. Si falta alguna, pegar el archivo correspondiente de `supabase/migrations/`
   o `supabase/apply_all.sql` en el **SQL Editor**.
3. Verificar con `0099_verify.sql`: debe imprimir `Biffy OK · …`.
4. Cargar el catálogo demo (opcional en producción):
   ```bash
   dart run tool/seed_supabase.dart
   ```

Estado del proyecto `jwdzpwsfwtkdeeuceaco` (2026-11-24): aplicadas de la `0000`
a la **`0027`** y `0099_verify` sin errores.

| Migración | Qué agrega | Cómo saber si está |
|---|---|---|
| `0026_payments.sql` | Pagos con Wompi, `payments`, `payment_events` | `select count(*) from payments;` no falla |
| `0027_server_guards.sql` | Horario, repartidores conectados reales y `sold_today` en el servidor | `select sold_on from dishes limit 1;` no falla |

La `0027` agenda con **`pg_cron`** el reinicio diario de `sold_today` (05:00
UTC = medianoche en Colombia). Si el proyecto no tiene `pg_cron`, la migración
lo avisa y sigue: la lectura ignora igual los conteos de días anteriores.
Comprobar el job:

```sql
select jobname, schedule from cron.job where jobname = 'biffy_reset_sold_today';
```

> **Ojo:** con la `0027`, una sede solo es visible si hay **repartidores
> conectados**. Sin ninguno, el comprador ve "No hay repartidores conectados
> ahora". En la demo, primero entra con la cuenta del repartidor.

---

## 1b. Edge Functions y pagos

Despliegue, secretos y datos de prueba de Wompi: ver
[`GUIA_SANDBOX_WOMPI.md`](GUIA_SANDBOX_WOMPI.md). Funciones del proyecto:
`create-payment`, `wompi-webhook`, `expire-payments`, `refund-payment`,
`send-university-code`, `university-revalidation` y `resend-webhook`.

---

## 2. Autenticación

En **Authentication → Providers → Email**:

- **Confirm email: ON** (en demo estaba apagado).
- Plantilla de correo en español.
- **Site URL** = dominio de la app (ej. `https://biffy.app`).
- **Redirect URLs**: el dominio + `http://localhost:3000` para desarrollo.

En **Authentication → Rate limits**: revisar los límites de registro y login.

---

## 3. Build

```bash
flutter build web --release \
  --dart-define-from-file=env.json
```

`env.json` se crea a partir de `env.example.json` y **no se versiona**.

> Sin `--dart-define-from-file`, el build arranca en **modo demo** (datos en
> memoria). Es útil para demos, pero no para producción.

---

## 4. Hosting (web)

Cualquier hosting estático sirve. Necesita **rewrite de SPA**: todas las rutas
deben devolver `index.html`.

| Hosting | Configuración |
|---|---|
| Firebase Hosting | `"rewrites": [{ "source": "**", "destination": "/index.html" }]` |
| Netlify | `/* /index.html 200` en `_redirects` |
| Vercel | rewrite `/(.*)` → `/index.html` |
| GitHub Pages | requiere `404.html` igual a `index.html` |

Subir el contenido de `build/web/`.

---

## 5. CI

`.github/workflows/ci.yml` corre en cada push a `dev`, `main` y ramas `hu*`, en
cada PR, y a mano desde **Actions → CI → Run workflow**:

| Job | Qué hace |
|---|---|
| `analyze-test-build` | `flutter analyze`, `flutter test`, build web (artefacto `biffy-web`) |
| `integration-supabase` | Smoke, HU-1 (perfiles y RLS) y HU-4 (reglas del servidor, avisos en vivo, cupones) contra el proyecto real |
| `build-android` | APK de release (artefacto `biffy-android`) |
| `sql-tests` | Todas las migraciones + `supabase/tests/*.sql` en un Postgres con PostGIS |

`expire-payments.yml` vence los pagos pendientes cada 15 minutos.

Para activar las pruebas reales: **Settings → Secrets and variables → Actions**:

| Secreto | Valor |
|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_KEY` | clave publicable (`sb_publishable_…`) |

Si no existen, el job imprime un aviso y no falla. `hu4_servidor_test` crea un
pedido de prueba con las cuentas demo y lo cancela al final.

---

## 6. Seguridad antes de publicar

### Revisión del repositorio (2026-11-24)

Se revisó **todo el historial de git de todas las ramas** buscando
`sb_secret_`, JWT de `service_role`, contraseñas en cadenas `postgres://`,
llaves privadas de Wompi (`prv_`, `*_integrity_`, `*_events_`) y llaves de
Resend (`re_`). **No hay secretos versionados.** El único `env.json` que se
subió (rama `frontendFlutterApps`) trae la URL y la llave **publicable**, que
está hecha para ir dentro de la app y la protege RLS.

`.gitignore` cubre `env.json`, `supabase/functions/.env`,
`android/key.properties` y los `.jks`.

Para repetir la revisión:

```bash
git log --all -p -G'(sb_secret_|prv_(test|prod)_|_integrity_|_events_|postgres://[^:]+:[^@]{6,}@)' \
  -- . ':!legacy_web/node_modules' | grep -E '^\+.*(sb_secret_|prv_|_integrity_|_events_|postgres://)'
```

### Rotar lo que se compartió durante el desarrollo

Requiere rol **Owner** o **Administrator** en Supabase (con *Developer* el
panel no deja).

| Qué | Dónde | Después de rotar |
|---|---|---|
| Contraseña de la base | Supabase → Project Settings → Database → **Reset database password** | Avisar a quien use `psql` o el pooler. La app no se afecta (usa la llave publicable). |
| `service_role` / `sb_secret_…` | Supabase → Project Settings → API Keys → crear una secreta nueva y **revocar** la vieja | Actualizar `SUPABASE_SERVICE_ROLE_KEY` donde se corra `tool/admin_seed.dart`. |
| Llaves de Wompi (si salieron del equipo) | Panel de Wompi → Desarrollo → Programadores | `supabase secrets set …` con las nuevas (ver guía de Wompi). |
| `CRON_SECRET` | Generar una cadena nueva | Actualizarlo en Supabase (secrets) y en GitHub (secret del repo). |
| Contraseña `biffy123` de las cuentas demo | Es pública a propósito (demo) | Para producción: borrar o cambiar las cuentas demo. |

### Otras comprobaciones

| Tarea | Dónde |
|---|---|
| Revisar que `service_role` **no** esté en la app | `rg service_role lib/` (no debe salir nada) |
| Confirmar RLS en todas las tablas | `0099_verify.sql` |
| Límite de subida de Storage (5 MB evidencia) | Storage → Settings |
| CORS / dominios permitidos | Auth → URL Configuration |

---

## 7. Respaldos

El plan **Free no incluye backups ni PITR**. Antes de publicar:

1. Subir al plan que incluya respaldos, o
2. Programar un `pg_dump` diario a un bucket externo.

---

## 8. Smoke test después del despliegue

```bash
flutter test test/integration/supabase_smoke_test.dart \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_KEY=<clave publicable>
```

Y manualmente, con las tres cuentas demo:

1. Comprador: pedido completo (caja → cupón → checkout).
2. Restaurante: aceptar, marcar listo, validar un código de premio.
3. Repartidor: aceptar oferta, recoger, entregar con foto.

---

## 9. Android: generar el AAB firmado (entrega final)

**Requisitos:** Android SDK (Android Studio o `cmdline-tools`) y JDK 17.
`flutter config --android-sdk <ruta>` y `flutter doctor` deben mostrar el
Android toolchain en verde.

**Firma.** El release se firma con `android/app/biffy-release.jks` y las
credenciales de `android/key.properties`. **Ninguno de los dos se sube a git**
(están en `.gitignore`): guarda una copia segura del `.jks` y de sus claves; sin
ellos no se puede publicar una actualización de la misma app. Formato de
`key.properties`:

```properties
storePassword=<clave>
keyPassword=<clave>
keyAlias=biffy
storeFile=biffy-release.jks
```

Para crear un `.jks` nuevo:

```bash
keytool -genkeypair -v -keystore android/app/biffy-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias biffy
```

**Generar el AAB** (con las credenciales de Supabase dentro de la app):

```bash
flutter build appbundle --release --dart-define-from-file=env.json
```

Salida: `build/app/outputs/bundle/release/app-release.aab`. Sin
`--dart-define-from-file` la app arranca en modo demo (sin red).

**Instalarlo en un dispositivo.** Un `.aab` no se instala directamente; hay dos
caminos:

1. **APK universal** (lo más rápido para probar):
   ```bash
   flutter build apk --release --dart-define-from-file=env.json
   adb install build/app/outputs/flutter-apk/app-release.apk
   ```
2. **Desde el AAB** con `bundletool`:
   ```bash
   java -jar bundletool.jar build-apks --bundle=app-release.aab \
     --output=biffy.apks --mode=universal \
     --ks=android/app/biffy-release.jks --ks-key-alias=biffy
   java -jar bundletool.jar install-apks --apks=biffy.apks
   ```

El permiso `INTERNET` está declarado en el manifiesto principal: sin él la
versión release no puede conectarse a Supabase (la de depuración sí).

---

## Checklist final

- [x] Migraciones `0000`–`0027` aplicadas y `0099_verify` en verde
- [x] Sin secretos en el repositorio (revisión del historial completo)
- [ ] `SUPABASE_URL` y `SUPABASE_KEY` como secrets del repo en GitHub
- [ ] Confirm email activado y plantilla en español
- [ ] Site URL y redirect URLs del dominio real
- [ ] Build con `--dart-define-from-file=env.json`
- [ ] Rewrite SPA configurado en el hosting
- [ ] Contraseña de base, `service_role` y `CRON_SECRET` rotados (Owner)
- [x] `service_role` fuera de la app
- [ ] Respaldos activos
- [ ] Smoke test y recorrido manual de los 3 roles
