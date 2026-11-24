# Cuestionario de sustentación · 20 preguntas con ubicación y línea

> Líneas verificadas el 10 de noviembre de 2026 sobre la rama `dev`.
> Si el archivo cambia, el número puede moverse: busca el nombre de la función.

## Preguntas y respuestas

### 1. ¿Dónde se definen todas las rutas de la app?

- **Respuesta:** en `buildRouter()`, con `GoRoute` para rutas simples y `StatefulShellRoute.indexedStack` para las tres barras inferiores.
- **Ubicación:** `lib/app/router.dart`
- **Línea de inicio:** **128** (`GoRouter buildRouter(...)`); el arreglo `routes:` empieza en la **146**.

### 2. ¿Qué función decide si una ruta necesita sesión y cómo se llama?

- **Respuesta:** `appRedirect(session, location, fullUri)`. Revisa `/repartidor`, `/negocio` y `kBuyerProtected`, y guarda el origen en `?from=`.
- **Ubicación:** `lib/app/router.dart`
- **Línea de inicio:** **63**.

### 3. ¿Qué rutas del comprador están protegidas?

- **Respuesta:** `kBuyerProtected`: `/checkout`, `/pedido`, `/pedidos`, `/frecuentes`, `/recompensas`, `/favoritos`, `/direcciones`, `/pagos` y `/perfil/datos`.
- **Ubicación:** `lib/app/router.dart`
- **Línea de inicio:** **50**.

### 4. ¿Dónde está la navegación inferior por rol?

- **Respuesta:** `RoleShell` dibuja la barra; `kBuyerNav`, `kCourierNav` y `kRestaurantNav` definen las pestañas.
- **Ubicación:** `lib/core/navigation/shells.dart`
- **Líneas de inicio:** **19** (`kBuyerNav`), **27** (`kCourierNav`), **34** (`kRestaurantNav`) y **44** (`RoleShell`).

### 5. ¿Dónde se inicializa Supabase y se restaura la sesión al abrir la app?

- **Respuesta:** en `main()`: `Supabase.initialize()`, `AppServices.supabase()` y `session.restoreAsync()`.
- **Ubicación:** `lib/main.dart`
- **Línea de inicio:** **8**.

### 6. ¿Dónde está el contrato (interfaz) de autenticación?

- **Respuesta:** `AuthRepository` define login, registro, sesión, perfil, repartidor y verificación; `InMemoryAuthRepository` es la versión demo.
- **Ubicación:** `lib/data/repositories/auth_repository.dart`
- **Línea de inicio:** **17**.

### 7. ¿Dónde está la implementación real de autenticación con Supabase?

- **Respuesta:** `SupabaseAuthRepository` implementa `AuthRepository` contra Supabase Auth y `profiles`.
- **Ubicación:** `lib/data/repositories/supabase_auth_repository.dart`
- **Línea de inicio:** **11**.

### 8. ¿Dónde vive el estado de la sesión?

- **Respuesta:** `SessionController`: usuario, rol activo, Gotas, direcciones, preferencias, ajustes y verificación.
- **Ubicación:** `lib/shared/state/session_controller.dart`
- **Línea de inicio:** **78**.

### 9. ¿Dónde está el login y qué hace `navigateAfterAuth`?

- **Respuesta:** `LoginScreen` valida el formulario y llama `loginAsync`. `navigateAfterAuth` vuelve al `from` o al panel del rol.
- **Ubicación:** `lib/features/auth/login_screen.dart`
- **Líneas de inicio:** **14** (`navigateAfterAuth`) y **34** (`LoginScreen`).

### 10. ¿Dónde se registra una cuenta y qué pasa con el rol restaurante?

- **Respuesta:** `RegisterScreen._submit()` valida y registra. Si el rol es restaurante, hace `context.push('/negocio/registro')`; el formulario ampliado crea la cuenta y el negocio.
- **Ubicación:** `lib/features/auth/register_screen.dart`
- **Líneas de inicio:** **13** (`RegisterScreen`) y **42** (`_submit`).

### 11. ¿Dónde se llama `registerBusiness` y qué RPC usa?

- **Respuesta:** la pantalla de registro del comercio llama `_session.auth.registerBusiness(...)`; el repositorio llama al RPC `register_business`.
- **Ubicación:** `lib/features/restaurant_owner/registration/merchant_registration_screen.dart`
- **Línea de inicio:** **219**.
- **Implementación del repositorio:** `lib/data/repositories/supabase_auth_repository.dart`, línea **199**.
- **RPC en SQL:** `supabase/migrations/0003_functions.sql`, línea **737**.

### 12. ¿Dónde se verifica el correo universitario y qué RPC llama?

- **Respuesta:** `sendUniversityCodeAsync()` envía el código a través de la Edge Function; `confirmUniversityCodeAsync()` confirma el código con el RPC `confirm_university_verification`. La validación antigua es `verifyUniversityAsync`.
- **Ubicación:** `lib/shared/state/session_controller.dart`
- **Líneas de inicio:** **550** (`verifyUniversityAsync`), **586** (`sendUniversityCodeAsync`) y **621** (`confirmUniversityCodeAsync`).
- **Repositorio:** `lib/data/repositories/supabase_auth_repository.dart`, métodos en **267**, **286** y **315**.
- **RPC en SQL:** `supabase/migrations/0025_university_revalidation.sql` (código, confirmación, revocación y vencimiento).

### 13. ¿Dónde está la regla de distancia `isReachable`?

- **Respuesta:** `isReachable(Restaurant r, DeliveryPoint p)` valida campus, repartidores cerca y radio.
- **Ubicación:** `lib/domain/catalog_rules.dart`
- **Línea de inicio:** **12**.

### 14. ¿Dónde se calculan `reachableRestaurants` y `reachableDishes`?

- **Respuesta:** en `CatalogController`, aplicando `isReachable` y el filtro de menú activo.
- **Ubicación:** `lib/shared/state/catalog_controller.dart`
- **Líneas de inicio:** **83** (`reachableRestaurants`) y **88** (`reachableDishes`).

### 15. ¿Dónde está el repositorio de catálogo de Supabase y qué escucha en Realtime?

- **Respuesta:** `SupabaseCatalogRepository`; `_subscribe()` escucha cambios de `dishes` y `branches` en el canal `biffy-catalog`.
- **Ubicación:** `lib/data/repositories/supabase_catalog_repository.dart`
- **Líneas de inicio:** **15** (clase) y **131** (`_subscribe`).

### 16. ¿Dónde está el Bloc de pedidos y qué capas usa?

- **Respuesta:** `OrdersBloc` recibe eventos, llama casos de uso de `lib/domain/usecases/orders/` y usa la interfaz `OrderRepository`; las implementaciones viven en `lib/data/repositories/`.
- **Ubicación:** `lib/features/orders/bloc/orders_bloc.dart`
- **Línea de inicio:** **21**.
- **Interfaz:** `lib/domain/repositories/order_repository.dart`, línea **86**.

### 17. ¿Dónde está el composition root (`AppServices`)?

- **Respuesta:** `AppServices` crea repositorios, casos de uso, controladores y `OrdersBloc`, y los publica con `providers`.
- **Ubicación:** `lib/shared/state/app_services.dart`
- **Línea de inicio:** **40**.

### 18. ¿Dónde están las migraciones, las políticas RLS y los RPC de Supabase?

- **Respuesta:** en `supabase/migrations/`. Los RPC y triggers están en `0003_functions.sql`, las políticas en `0004_rls.sql` y la verificación en `0099_verify.sql`.
- **Ubicaciones y líneas:**
  - `supabase/migrations/0003_functions.sql`: **129** (`handle_new_user`), **218** (`verify_university`), **737** (`register_business`).
  - `supabase/migrations/0004_rls.sql`: **100** (`profiles_update`; el resto de políticas está a lo largo del archivo).
  - `supabase/migrations/0099_verify.sql`: **8** (bloque `do $$` de verificación).
  - `supabase/apply_all.sql`: **1** (bootstrap generado).

### 19. ¿Dónde están las pruebas unitarias, de widget, de integración y de arquitectura?

- **Respuesta:** `test/unit/`, `test/widget/`, `test/integration/` y `test/architecture_test.dart`.
- **Línea de inicio de arquitectura:** `test/architecture_test.dart`, **27** (`void main`).
- **Pruebas reales de HU-1:** `test/integration/hu1_supabase_test.dart` y `test/integration/hu1_registration_test.dart`.

### 20. ¿Dónde están las cuentas demo y el script que las crea?

- **Respuesta:** los correos y constantes están en `seed_users.dart`; el script de administración es `tool/admin_seed.dart`; la tabla de cuentas está en `supabase/README.md`.
- **Ubicaciones y líneas:**
  - `lib/data/mock/seed_users.dart`: **5** (`kDemoBuyerEmail`).
  - `tool/admin_seed.dart`: **38** (`main`).
  - `supabase/README.md`: **274** (sección “Cuentas demo”).

## Mapa rápido de rutas (con línea)

| Sección | Ruta | Línea en `lib/app/router.dart` |
|---|---|---|
| Pública | `/login` | 148 |
| Pública | `/registro` | 149 |
| Pública | `/carrito` | 166 |
| Comprador | `/checkout` | 167 |
| Comprador | `/pedido/:id` | 168 |
| Comprador | `/recompensas` | 172 |
| Comprador | `/favoritos` | 173 |
| Comprador | `/direcciones` | 178 |
| Comprador | `/campus` | 184 |
| Comprador | `/perfil/datos` | 185 |
| Repartidor | `/repartidor` | 242 |
| Repartidor | `/repartidor/ganancias` | 246 |
| Restaurante | `/negocio` | 263 |
| Restaurante | `/negocio/menu` | 274 |
| Restaurante | `/negocio/estadisticas` | 278 |
| Restaurante | `/negocio/cajas` | 289 |
