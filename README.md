# Biffy · App móvil (Flutter)

Biffy es una aplicación de domicilios de comida para estudiantes universitarios en Colombia. Conecta tres roles sobre un mismo pedido: **comprador**, **restaurante** y **repartidor**.

- **Sprint 1 (actual):** frontend Flutter funcional con datos simulados. Sin pagos reales, sin GPS y sin notificaciones push.
- **Rama `supabase`:** integración del backend en preparación (ver [Supabase](#supabase-en-integración)). Hoy la app sigue funcionando 100 % en memoria, sin red.

> La app web anterior (React/Lovable) se conserva solo como referencia de comportamiento y diseño en [`legacy_web/`](legacy_web/). No se le agregan funcionalidades.

## Stack

| Capa | Tecnología |
|---|---|
| UI | Flutter 3.44 · Material 3 · tema propio (claro/oscuro) |
| Estado | `provider` + `ChangeNotifier` (`AppServices` como contenedor de dependencias) |
| Navegación | `go_router` con un `StatefulShellRoute` por rol y guardas por sesión |
| Datos | Repositorios en memoria detrás de interfaces (`lib/data/repositories/`) |
| Reglas de negocio | Funciones puras en `lib/domain/` |
| Tipografía | Sora + Manrope empaquetadas en `assets/fonts/` (offline) |
| Evidencia de entrega | `image_picker` |
| Backend (en integración) | Supabase (Postgres + Auth + Storage + Realtime) |

## Requisitos

- **Flutter 3.44 o superior** (probado con Flutter 3.44.8 / Dart 3.12.2).
- **Android SDK / Android Studio** y un emulador o teléfono con depuración USB, solo si vas a compilar o ejecutar en Android.
- **Supabase CLI** (opcional, únicamente para aplicar migraciones de base de datos).

## Puesta en marcha

### 1. Modo actual, sin backend

```bash
flutter pub get
flutter run                 # dispositivo o emulador conectado
flutter run -d chrome       # vista previa en el navegador
```

No requiere variables de entorno, claves ni servicios externos.

### 2. Con Supabase (cuando las migraciones estén aplicadas)

Copia [`env.example.json`](env.example.json) a `env.json` (ya está ignorado por git):

```json
{
  "SUPABASE_URL": "https://jwdzpwsfwtkdeeuceaco.supabase.co",
  "SUPABASE_KEY": "sb_publishable_..."
}
```

Y ejecuta:

```bash
flutter run --dart-define-from-file=env.json
```

Reglas de seguridad:

- El archivo `env.json` **nunca** se versiona.
- En la app solo va la **clave publicable** (`sb_publishable_...`, equivalente a la anon key). Es pública por diseño: la protección real son las políticas RLS.
- La **service_role key** y la **contraseña de la base** no van en la app ni en el repositorio: se usan solo en scripts de administración o en la CLI.

Sin esas variables la app arranca igual, en **modo demo local** y sin red.

## Comandos

| Comando | Qué hace |
|---|---|
| `flutter pub get` | Instala dependencias |
| `flutter run` | Ejecuta la app en el dispositivo conectado |
| `flutter run -d chrome` | Vista previa web |
| `dart format .` | Formatea el código |
| `flutter analyze` | Análisis estático |
| `flutter test` | Unitarias + widgets + integración sin dispositivo |
| `flutter test integration_test/app_test.dart -d <id>` | Integración en Android/iOS (requiere dispositivo) |
| `flutter build apk --debug` | APK de depuración |
| `flutter build web --release` | Sitio estático en `build/web` |
| `supabase db push` | Aplica las migraciones al proyecto remoto |

## Estructura del proyecto

```text
lib/
  main.dart                  # Punto de entrada (AppServices.demo())
  app/                       # BiffyApp, router (go_router), tema (colores, tipografía)
  core/
    constants/               # Categorías, universidades, puntos de entrega, valores demo
    navigation/              # Shells con navegación inferior por rol + barra del carrito
    utils/                   # Formato COP/fechas, distancia, reloj inyectable
    widgets/                 # Componentes compartidos (botones, tarjetas, hojas, píldoras)
  data/
    models/                  # Modelos tipados (catálogo, carrito, pedido, usuario…)
    repositories/            # Interfaces + implementaciones en memoria
    mock/                    # Datos semilla ficticios (catálogo, usuarios, pedidos)
  domain/                    # Reglas puras: precios, filtros, transiciones, horarios,
                             # recomendaciones, asistente, repetición de pedidos
  features/
    onboarding/  auth/
    buyer/                   # home, explore, restaurant, product, cart, tracking, orders,
                             # ai, preferences, rewards, favorites, notifications, settings,
                             # support, payments, addresses, campus, profile
    courier/                 # registration, home, offers, pickup, delivery, earnings, profile
    restaurant_owner/        # registration, home, orders, menu, products, statistics, profile
  shared/state/              # Controladores ChangeNotifier + AppServices (inyección)
test/
  unit/  widget/  integration/   # 104 pruebas (sin dispositivo)
  helpers.dart
integration_test/app_test.dart   # Flujo completo en Android/iOS
supabase/
  migrations/              # migraciones SQL versionadas (esquema, RLS, RPC, storage)
  apply_all.sql            # bootstrap para pegar en el SQL Editor
assets/
  fonts/  images/
```

## Arquitectura

- **Estado:** `AppServices` construye y conecta `SessionController`, `CatalogController`, `CartController`, `OrderService` y `NotificationCenter` sobre repositorios. Las pruebas crean su propio `AppServices` con reloj fijo y semilla aleatoria, por lo que son deterministas.
- **Reglas fuera de la UI:** `pricing.dart`, `catalog_rules.dart` (regla única de cobertura `isReachable`), `order_rules.dart` (tabla `kAllowedTransitions`, pago al repartidor, métricas), `scheduling.dart`, `recommendation.dart`, `assistant.dart`, `reorder.dart`.
- **Pedidos compartidos:** `OrderService` es el único que cambia estados. La aceptación del repartidor es atómica: si el pedido ya tiene repartidor devuelve `alreadyAssigned`.
- **Navegación:** `lib/app/router.dart` concentra las rutas. El comprador explora sin sesión; checkout, pedidos, recompensas, favoritos, direcciones y pagos exigen cuenta y conservan la ruta de origen (`/login?from=…`). `/repartidor/*` exige perfil de repartidor y `/negocio/*` un negocio vinculado.
- **Preparado para backend:** `CatalogRepository`, `OrderRepository` y `AuthRepository` son interfaces; la implementación remota se inyecta en `AppServices` sin tocar las pantallas.

## Roles y flujo de demostración

**Comprador** (Inicio · Explorar · Biffy AI · Perfil): explora sin cuenta, filtra, personaliza platos, arma el carrito, programa, elige dirección y pago simulado, confirma un pedido de demostración, sigue el estado, repite pedidos, recibe recomendaciones locales, gestiona preferencias, Gotas, favoritos, direcciones y soporte.

**Restaurante** (Inicio · Pedidos · Menú · Estadísticas · Perfil): registro en 6 pasos, panel con métricas, pedidos de cocina (aceptar, rechazar con motivo, marcar listo), CRUD de productos que se publican en el catálogo del comprador, estadísticas y perfil.

**Repartidor** (Inicio · Ganancias · Perfil): registro con vehículo, conexión y zona General/Campus, ofertas con asignación atómica, recogida con checklist obligatorio, entrega con código y evidencia fotográfica, ganancias e historial.

Un pedido creado por el comprador aparece en el panel del restaurante, pasa a las ofertas de los repartidores al marcarse listo y vuelve al historial del comprador al entregarse. `test/integration/full_flow.dart` recorre ese ciclo completo a través de la interfaz.

Guía paso a paso del ciclo completo: [`INFORME_SPRINT_1.md`](INFORME_SPRINT_1.md), sección 4.

## Cuentas de demostración

Contraseña de todas: `biffy123` (también hay botones de acceso rápido en el login).

| Rol | Correo |
|---|---|
| Comprador con historial (Icesi verificado, simulado) | `diego.demo@icesi.edu.co` |
| Comprador nuevo | `camila.demo@biffy.co` |
| Repartidor (moto) | `andres.repartidor@demo.biffy.co` |
| Repartidora (bicicleta) | `valentina.repartidora@demo.biffy.co` |
| Restaurante Qbano Icesi (demo) | `qbano@demo.biffy.co` |

Si pruebas de noche y todo aparece cerrado, activa **Configuración › Horario de demostración (12:00)**.

## Pruebas

Estado verificado en esta rama:

| Comando | Resultado |
|---|---|
| `flutter analyze` | `No issues found!` |
| `flutter test` | **104 pruebas, todas pasan** |

- **Unitarias:** precios, reglas de catálogo, sesión y Gotas, carrito, servicio de pedidos, programación y asistente.
- **Widgets:** recorrido de todas las rutas de los tres roles (falla ante excepciones u overflow), flujos del comprador y de roles, modo oscuro y punto sin cobertura.
- **Integración:** ciclo completo Comprador → Restaurante → Repartidor → Historial y prueba de asignación duplicada.

## Convenciones de código

- Archivos en `snake_case`, clases en `PascalCase`, miembros en `camelCase`.
- Un widget público por archivo cuando tiene lógica propia; los helpers internos llevan prefijo `_`.
- Las reglas de negocio no viven en widgets: van en `lib/domain/` y se cubren con pruebas unitarias.
- Los controladores no leen `BuildContext`; las pantallas escuchan con `context.watch`/`Selector`.
- Formato con `dart format` y validación con `flutter analyze` antes de cada commit.
- Todo control visible debe tener una acción real; lo simulado se rotula como demostración.

## Supabase

Proyecto: `jwdzpwsfwtkdeeuceaco`. Detalle operativo en [`supabase/README.md`](supabase/README.md).

**Estado:** el esquema ya está escrito y versionado en `supabase/migrations/`, pero **todavía no se ha aplicado** al proyecto remoto. La app sigue en modo demo local y no hace peticiones de red.

### Aplicar la base (una sola vez)

```text
Dashboard → SQL Editor → New query → pegar supabase/apply_all.sql → Run
```

o, con CLI:

```bash
supabase login
supabase link --project-ref jwdzpwsfwtkdeeuceaco
supabase db push
```

`apply_all.sql` se genera concatenando las migraciones y es idempotente. A partir de ahí, **cada cambio es una migración nueva**; no se edita el esquema desde el panel.

### Qué incluye

| Pieza | Detalle |
|---|---|
| Esquema | 27 tablas: perfiles, negocios, sedes, platos, direcciones, cupones, Gotas (saldo, recompensas, premios por caja y canjes), pedidos, eventos, repartidores, notificaciones |
| Seguridad | RLS activo en todas; catálogo público solo en lectura; datos personales por dueño; pedidos visibles solo para sus tres partes |
| Integridad | Enums, `CHECK`, FKs, `updated_at` por trigger, borrado lógico e índices en FKs y estado |
| Operaciones | RPC `place_order`, `restaurant_*`, `courier_*`, `buyer_cancel`, `verify_university`, `register_business` |
| Storage | `dish-images` (público), `delivery-evidence` y `merchant-docs` (privados por carpeta) |
| Seed | Universidades, puntos de entrega y categorías |

El RPC recibe un único `jsonb`, así se agregan campos sin volver a tocar firmas, y devuelve `{ result, order }` para mapear directo a los enums de Dart.

### Siguiente fase (app)

1. `supabase_flutter` + `Supabase.initialize()` en `main.dart`, activado solo si `AppConfig.hasSupabase`.
2. `SupabaseAuthRepository` (correo y contraseña, `onAuthStateChange`).
3. Repositorios remotos con caché hidratada + `realtime` para conservar los getters síncronos.
4. Escrituras de pedidos por RPC; subida de fotos a Storage.
5. Manejo de errores y estados de carga en las pantallas.

## legacy_web

Copia de la app React/Lovable original, conservada como referencia. No se compila ni se despliega desde esta rama y no recibe cambios.

## Documentación

- [`INFORME_SPRINT_1.md`](INFORME_SPRINT_1.md): alcance, arquitectura, pruebas, limitaciones y pendientes del Sprint 1.
- [`AGENTS.md`](AGENTS.md): reglas de arquitectura que debe respetar cualquier cambio.

## Roadmap

1. Supabase: esquema, RLS, RPC, Auth, Storage y Realtime.
2. Autenticación real con verificación de correo universitario.
3. Pasarela de pagos (Nequi, PSE, tarjeta).
4. Geolocalización real y seguimiento en mapa.
5. Notificaciones push (FCM).
6. CI con `flutter analyze`, `flutter test` y `flutter build web`.
