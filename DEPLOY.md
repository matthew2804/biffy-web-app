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

`.github/workflows/ci.yml` corre en cada push/PR:

```text
flutter pub get → analyze → test → build web → smoke Supabase (opcional)
```

Para activar el smoke: **Settings → Secrets and variables → Actions**:

| Secreto | Valor |
|---|---|
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_KEY` | clave publicable (`sb_publishable_…`) |

Si no existen, el paso imprime “se omite” y no falla.

---

## 6. Seguridad antes de publicar

| Tarea | Dónde |
|---|---|
| **Rotar** la contraseña de la base compartida por chat | Settings → Database |
| Revisar que `service_role` **no** esté en la app | Repo (`rg service_role`) |
| Confirmar RLS en todas las tablas | `0099_verify.sql` |
| Límite de subida de Storage (10 MB) | Storage → Settings |
| CORS / dominios permitidos | Auth → URL Configuration |
| `env.json`, `env.example.json` con claves reales | `env.json` está en `.gitignore` |

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

## Checklist final

- [ ] Migraciones aplicadas y `0099_verify` en verde
- [ ] Confirm email activado y plantilla en español
- [ ] Site URL y redirect URLs del dominio real
- [ ] Build con `--dart-define-from-file=env.json`
- [ ] Rewrite SPA configurado en el hosting
- [ ] Secretos de CI configurados
- [ ] Contraseña de base rotada y `service_role` fuera de la app
- [ ] Respaldos activos
- [ ] Smoke test y recorrido manual de los 3 roles
