# Informe del Sprint 1 · Biffy (frontend Flutter)

Fecha: 24 de octubre de 2026 · Rama: `frontendFlutterApps`

## 1. Resumen

Se implementó desde cero el frontend móvil de Biffy en **Flutter/Dart**, reemplazando la app web React/Lovable (que se movió a `legacy_web/` solo como referencia). La app conecta los tres actores del modelo cliente‑proveedor sobre un estado local compartido:

- **Comprador**: explora sin iniciar sesión, filtra, personaliza platos, arma el carrito, programa, elige dirección y pago simulado, confirma un *pedido de demostración* (sin cobros), sigue el estado, repite pedidos, recibe recomendaciones locales (Biffy AI), gestiona preferencias, Gotas, favoritos, direcciones, ajustes y soporte.
- **Restaurante**: registro por pasos, panel con métricas derivadas, pedidos de cocina (aceptar/rechazar con motivo/marcar listo/recibo), menú con CRUD de productos que se publican en el catálogo del comprador, estadísticas y perfil.
- **Repartidor**: registro con vehículo, conexión y zona General/Campus, ofertas (aceptar/rechazar/detalle) con asignación atómica, recogida con checklist obligatorio, entrega con código y evidencia fotográfica local, ganancias e historial.

Un pedido creado por el comprador aparece en el panel del restaurante, pasa a las ofertas de los repartidores al marcarse listo y vuelve al historial del comprador al entregarse. Todo el ciclo está cubierto por una prueba de integración que lo recorre **a través de la interfaz**.

Cifras: 83 archivos Dart en `lib/` (~17.000 líneas) y 104 pruebas automatizadas que pasan.

## 2. Arquitectura

```text
lib/
  main.dart                 Punto de entrada (AppServices.demo())
  app/                      BiffyApp, router (go_router), tema (colores, tipografía)
  core/
    constants/              Categorías, universidades, puntos de entrega, valores demo
    navigation/             Shells con navegación inferior por rol + barra del carrito
    utils/                  Formato COP/fechas, distancia, reloj inyectable
    widgets/                Componentes reutilizables (tarjetas, botones, píldoras, hojas)
  data/
    models/                 Modelos tipados (catálogo, carrito, pedido, usuario, negocio…)
    repositories/           Interfaces + implementaciones en memoria (catálogo, pedidos, auth)
    mock/                   Datos semilla ficticios (catálogo, usuarios, pedidos)
  domain/                   Reglas de negocio puras: precios, filtros, transiciones,
                            horarios, recomendaciones, asistente, repetición de pedidos
  features/
    onboarding/ auth/
    buyer/…                 home, explore, restaurant, product, cart, tracking, orders,
                            ai, preferences, rewards, favorites, notifications, settings,
                            support, payments, addresses, campus, profile
    courier/…               registration, home, offers, pickup, delivery, earnings, profile
    restaurant_owner/…      registration, home, orders, menu, products, statistics, profile
  shared/state/             Controladores ChangeNotifier + AppServices (inyección)
test/ unit/ widget/ integration/      integration_test/ (dispositivo)
```

- **Gestión de estado**: `provider` + `ChangeNotifier`. `AppServices` crea y conecta `SessionController`, `CatalogController`, `CartController`, `OrderService` y `NotificationCenter` sobre repositorios en memoria. Las pruebas crean su propio `AppServices` con un reloj fijo.
- **Reglas de negocio** fuera de los widgets (`lib/domain/`): `pricing.dart`, `catalog_rules.dart` (regla única de cobertura `isReachable`), `order_rules.dart` (tabla `kAllowedTransitions`, pago al repartidor, métricas), `scheduling.dart`, `recommendation.dart`, `assistant.dart`, `reorder.dart`.
- **Pedidos compartidos**: `OrderService` es el único que cambia estados; la aceptación del repartidor es atómica (si ya tiene repartidor devuelve `alreadyAssigned`).
- **Navegación**: `go_router` centralizado en `lib/app/router.dart`, con un `StatefulShellRoute` por rol (conserva el estado de cada pestaña) y `redirect` que protege rutas: el comprador explora libremente; checkout, pedidos, recompensas, etc. exigen sesión y conservan la ruta de origen (`/login?from=…`); `/repartidor/*` exige perfil de repartidor y `/negocio/*` un negocio vinculado.
- **Preparado para Firebase**: `CatalogRepository`, `OrderRepository` y `AuthRepository` son interfaces; basta con implementarlas contra Firestore/Auth y cambiarlas en `AppServices`.

## 3. Pantallas

**Comunes**: Splash · Login (con accesos demo) · Registro con selección de rol · Selector de cuentas demo · Notificaciones · Soporte · Página no encontrada.

**Comprador** (navegación: Inicio, Explorar, Biffy AI, Perfil): Inicio · Explorar + panel de filtros · Detalle de restaurante · Detalle de plato (también edición de línea del carrito) · Carrito · Programación (hoja) · Checkout · Seguimiento · Mis pedidos (Activos/Programados/Anteriores/Cancelados) · Pedidos frecuentes y «Pedir ya» · Biffy AI (recomendaciones + chat) · Preferencias (3 pasos) · Recompensas/Gotas · Favoritos · Campus Live y verificación simulada · Direcciones + formulario · Métodos de pago · Configuración · Perfil · Información personal.

**Repartidor** (navegación: Inicio, Ganancias, Perfil): Registro inicial · Inicio (conexión, zona, ganancias, metas, mapa ilustrativo, ofertas) · Detalle de oferta · Recogida · Entrega · Ganancias e historial · Perfil.

**Restaurante** (navegación: Inicio, Pedidos, Menú, Estadísticas, Perfil): Registro del negocio (6 pasos) · Inicio · Pedidos/cocina · Mi menú · Formulario de producto · Estadísticas · Perfil.

## 4. Cómo probar el ciclo completo de un pedido

1. Abre la app: tras el splash verás el inicio **sin sesión** (punto «Icesi · Biblioteca»).
2. Toca **Qbano en Icesi** → **Qbano Especial** → marca un extra → **Agregar**.
3. Toca la barra negra del carrito → elige *Ahora* o *Programar*, pago, propina → **Continuar al checkout**.
4. Se pide iniciar sesión: elige **Comprador · Diego** y la app vuelve al flujo y abre el checkout.
5. Revisa el resumen → **Confirmar pedido** («Pedido de demostración · sin cobros reales»). Anota el **código de entrega**.
6. En el seguimiento, en «Modo demostración», toca **Abrir como Qbano · Icesi** → **Aceptar** → **Marcar como listo**.
7. Perfil del restaurante → **Cuentas de demostración** → **Andrés (repartidor demo)** → activa **Conectado** → **Aceptar** la oferta.
8. Marca los tres puntos del checklist → **Confirmar recogida** → escribe el código del paso 5 → **Usar evidencia demo** (o cámara/galería) → **Marcar como entregado**.
9. Perfil → Cuentas de demostración → **Diego** → Perfil → **Mis pedidos** → pestaña **Anteriores**: el pedido aparece entregado. Las Gotas, las métricas del restaurante y las ganancias del repartidor quedan actualizadas.

Si es de noche y los restaurantes están cerrados, usa el aviso del inicio o **Configuración › Horario de demostración (12:00)**.

## 5. Funcionalidades

**Implementadas (con lógica real en el estado local)**: exploración sin sesión; búsqueda por nombre, restaurante, descripción, categoría, etiquetas e ingredientes; filtros rápidos (campus, nutrición, <15 min, <$15.000, ⭐4,7+, abierto, sin mis alérgenos) y panel (precio $5.000–$40.000 en pasos de $1.000, estilo de vida, categorías, contador de resultados); regla de cobertura por radio + repartidores + solo campus; detalle con ingredientes que se pueden quitar, tamaños, acompañantes, extras, nota y cantidad con precio recalculado; advertencia de alérgenos; carrito de un restaurante con edición sin perder la línea, vaciado con confirmación, descuento de campus, tarifa, Gotas, cupones, propina; programación validada contra el horario; direcciones CRUD con predeterminada; checkout con validaciones; pedido con ID único (`BF-2041`, `BF-2042`…); seguimiento de 4 pasos; cancelación antes de la aceptación; historial en 4 pestañas; repetir pedido comprobando disponibilidad, precios y opciones; «Pedir ya» con confirmación explícita; Biffy AI con 6 modos, 3 recomendaciones con motivos y coincidencia estimada, y chat local; encuesta de 3 pasos con 300 Gotas una sola vez; 450 Gotas de bienvenida una vez; canje con confirmación y validación de saldo; favoritos (requieren sesión); ajustes con efectos (notificaciones, promociones, modo oscuro, horario demo); soporte con FAQ y respuestas locales; flujo completo de restaurante y repartidor; notificaciones locales por rol que abren la pantalla relacionada.

**Simuladas (y rotuladas como tales en la interfaz)**: autenticación y contraseñas (solo en memoria); verificación universitaria por dominio de correo; métodos de pago (no se piden datos bancarios ni se cobra); tarifa de entrega, pago al repartidor, tarifa Biffy (10 %), bonos y liquidaciones; mapa de demanda ilustrativo; documentos legales del restaurante y del repartidor (solo se marcan localmente); enlaces de «compartir» y «pedido grupal» (se copian al portapapeles, no hay carrito colaborativo); contacto con el repartidor (solo copia de datos, sin chat ni llamadas); evidencia de entrega (foto local vía `image_picker` o evidencia demo explícita).

**Pendientes / fuera de alcance**: ver secciones 9 y 12. La búsqueda por voz (opcional) no se implementó para no simular algo que no funciona.

## 6. Diseño

- **Colores**: primario `#FCBD1A` (botones, selección, navegación activa, códigos), secundario `#F3B428` (recompensas, acentos), fondo `#F4F5F9`, texto `#1E1E20`, éxito `#23A05B`, error `#E85D57`, superficies `#FFFFFF`, lavanda `#EFEAFA` (fondos de emojis), bordes `#E0E2E8`. Modo oscuro con la misma identidad amarilla. El violeta `#5E23E3` no se usa.
- **Tipografía**: Sora (títulos) y Manrope (texto, botones, navegación), incluidas como archivos TTF con licencia OFL en `assets/fonts/` (no dependen de red).
- **Componentes** (`lib/core/widgets/`): tarjetas blancas radio 20 con sombra suave, botones principales de ancho completo y 52 px, píldoras seleccionables, botones redondos con etiqueta accesible, barra flotante del carrito, hojas inferiores, carruseles horizontales nativos, contenido limitado a 480 px de ancho y áreas seguras respetadas.
- **Recursos**: se reutilizó el **logo original de la abeja** (`assets/images/biffy-logo.png`) en splash, login y vacíos, y se generaron con él los íconos de Android, iOS y web. Fotos de demostración existentes del repo (`demo-qbano-sandwich.jpg`, `demo-bowl.jpg`, `demo-burger.jpg`); el resto de productos usa emojis sobre lavanda.

## 7. Pruebas

Comandos ejecutados realmente (Flutter 3.44.8, Windows 11) y resultados:

| Comando | Resultado |
|---|---|
| `flutter test test/unit` | **73 pruebas, todas pasaron** |
| `flutter test test/widget` | **29 pruebas, todas pasaron** |
| `flutter test test/integration` | **2 pruebas, todas pasaron** |
| `flutter test` (todo) | **104 pruebas, todas pasaron** |
| `flutter test integration_test/app_test.dart -d chrome` | **No ejecutable**: «Web devices are not supported for integration tests yet». |
| `flutter test integration_test/app_test.dart -d windows` | **No ejecutable**: el proyecto no tiene plataforma Windows y no hay Visual Studio instalado. |

No se midió cobertura de código.

**Unitarias** (`test/unit/`):
- `pricing_test.dart` (15): subtotal, precio con tamaño/acompañante/extras, total, descuento de campus por universidad verificada, tarifa por campus, propina, Gotas limitadas por saldo y valor, cupón, presupuesto válido y dentro de presupuesto, `Dish.orderable` (agotado y límite de porciones).
- `catalog_rules_test.dart` (12): cobertura (radio, solo campus, sin repartidores), horario, filtros por precio, <$15.000, categoría, tiempo, búsqueda por restaurante/ingrediente, exclusión de alérgenos, estilo de vida, valoración/abiertos, limpiar filtros.
- `session_test.dart` (12): login/rol, contraseña incorrecta, registro duplicado, 450 Gotas una vez, logout, guardar preferencias, **300 Gotas la primera vez y nunca duplicadas**, sin sesión no hay Gotas, canje con saldo insuficiente, verificación por dominio, favoritos con sesión, modo Campus bloqueado sin verificación.
- `cart_test.dart` (7): agregar/quitar, agrupación por personalización, cantidades, un solo restaurante, edición de línea, agotado, vaciar.
- `order_service_test.dart` (16): **IDs únicos**, pedido visible para su restaurante, sin sesión no confirma, Gotas usadas y reembolsadas al rechazar, **tabla de estados permitidos**, no «listo» sin aceptar, cancelación del comprador, ofertas solo cuando está listo, **aceptación y prevención de asignación duplicada**, repartidor ocupado, rechazo por repartidor, **recogida con tres checks**, **validación de código y evidencia** y acreditación de ganancias/Gotas, **cálculo de ganancias**, **actualización de métricas del restaurante**.
- `scheduling_and_ai_test.dart` (11): horarios futuros dentro del horario, días cerrados, hora pasada, borrado de hora al cambiar de día, recomendaciones sin alérgenos, restricción vegana, gustos e historial, populares sin perfil, modo económico, asistente (presupuesto, ingredientes, pizza vegetariana, tiempo), reloj de horario demo.

**Widgets** (`test/widget/`):
- `all_screens_smoke_test.dart` (4): recorre **todas las rutas** de los tres roles (incluidas IDs inexistentes) y falla ante cualquier excepción u overflow; también modo oscuro y punto sin cobertura.
- `buyer_widgets_test.dart` (13): splash → Inicio; explorar sin sesión; filtros actualizan resultados; panel de filtros con contador y precio; agregar al carrito y barra flotante; personalizaciones cambian el precio; cancelar edición no pierde la línea; checkout con resumen correcto y creación del pedido; pestañas conservan estado; cambio de punto de entrega; perfil con Gotas actualizadas (sin duplicar); favoritos piden login; horario de demostración.
- `roles_widgets_test.dart` (12): login por rol (comprador, repartidor, restaurante), contraseña incorrecta, ruta protegida retoma el destino; restaurante ve el pedido, lo acepta y lo marca listo; rechazo con motivo; repartidor acepta la oferta; recogida exige los tres checks; entrega rechaza código incorrecto y exige evidencia; pedido entregado en el historial; producto nuevo del restaurante visible en el catálogo.

**Integración**:
- `test/integration/full_flow_test.dart` (2): flujo **Comprador → Carrito → login al confirmar → Checkout de demostración → Restaurante → Repartidor → Recogida → Entrega → Historial**, todo con toques en la UI y verificando los 24 pasos del flujo obligatorio; y prueba de que **dos repartidores no pueden aceptar el mismo pedido** (la pantalla del segundo se actualiza y el servicio devuelve `alreadyAssigned`).
- `integration_test/app_test.dart`: el mismo flujo con `IntegrationTestWidgetsFlutterBinding` para emulador o teléfono. Compila y pasa el análisis, pero **no se ejecutó** por falta de dispositivo compatible (ver tabla).

Durante el desarrollo, la prueba de recorrido detectó y permitió corregir errores reales: desbordes de diseño, un `Center` que dejaba con altura cero el detalle de plato, campos `late` que leían el contexto en `dispose()` y pantallas de rol que fallaban al cambiar de cuenta.

## 8. Análisis estático

- `dart format --output=none --set-exit-if-changed .` → «Formatted 96 files (0 changed)».
- `flutter analyze` → **No issues found!** (reglas de `flutter_lints` 6).
- `flutter build web --release` → **compiló correctamente** (`build/web`); además se revisó visualmente en Chrome sin interfaz.
- `flutter build apk --debug` → **no ejecutado**: este equipo no tiene Android SDK (`flutter doctor`: «Unable to locate Android SDK»). No se afirma que el APK compile hasta probarlo en un equipo con Android configurado.

## 9. Limitaciones

- **Sin backend ni Firebase**: todo vive en memoria; al cerrar la app se pierden pedidos, cuentas nuevas y cambios. La sincronización entre roles ocurre solo dentro de la misma instancia de la app (no entre teléfonos ni en segundo plano).
- **Autenticación** simulada, sin seguridad de producción; contraseñas de demostración en memoria.
- **Pagos**: no hay pasarela ni cobros; los métodos son etiquetas.
- **GPS y mapas**: no se usan; los puntos de entrega y distancias son simulados.
- **Verificación universitaria e identidad**: simuladas; el dominio del correo no demuestra control del correo.
- **Notificaciones**: solo dentro de la app (sin push ni FCM).
- **Chat/llamadas** en tiempo real no disponibles.
- **Datos de demostración**: marcas, menús y precios son ilustrativos y no oficiales (p. ej. Qbano). Fechas de semilla relativas a la hora actual.
- Los textos de Material usan `flutter_localizations` (es-CO); los montos en COP y las fechas se formatean con utilidades propias en `lib/core/utils/format.dart` (sin `intl`).

## 10. Comandos de ejecución

Ejecutar **desde la raíz del repositorio** (carpeta que contiene `pubspec.yaml`). Requiere Flutter 3.44+; para Android, un emulador o un teléfono con depuración USB (`flutter devices` debe listarlo).

```bash
flutter --version
flutter pub get
dart format .
flutter analyze
flutter test
flutter run                         # dispositivo conectado (Android recomendado)
flutter run -d chrome               # vista previa en navegador
flutter test integration_test/app_test.dart -d <id-dispositivo>
flutter build apk --debug           # APK en build/app/outputs/flutter-apk/app-debug.apk
flutter build web --release         # sitio estático en build/web
```

No se requieren variables de entorno, claves ni servicios externos.

## 11. Datos de demostración

Todas las cuentas usan la contraseña **`biffy123`**. En **Login** hay accesos rápidos y en cualquier **Perfil › Cuentas de demostración** se puede cambiar de rol con un toque.

| Rol | Cuenta | Qué permite probar |
|---|---|---|
| Comprador | `diego.demo@icesi.edu.co` | Icesi verificado (simulado), 750 Gotas, 3 direcciones, favoritos, historial con pedidos frecuentes |
| Comprador | `camila.demo@biffy.co` | Usuario nuevo: bienvenida de 450 Gotas y encuesta con 300 Gotas |
| Repartidor | `andres.repartidor@demo.biffy.co` | Moto (placa ABC12D), campus Icesi, entregas previas |
| Repartidor | `valentina.repartidora@demo.biffy.co` | Bicicleta, sin universidad (para probar el bloqueo de Campus y la asignación duplicada) |
| Restaurante | `qbano@demo.biffy.co` | Qbano · Icesi con pedidos nuevos, en preparación, listos y entregados |
| Restaurante | `<negocio>@demo.biffy.co` | Una cuenta por cada negocio semilla (`horno`, `wokroll`, `verde`, `enjambre`, …) |

Pedidos semilla: BF-1830…BF-1843 (entregados, cancelado, nuevo, en preparación y dos listos para repartidores). Catálogo: 15 restaurantes ficticios (8 alrededor de Icesi en Cali y 7 en Bogotá) y 32 platos, incluidos Qbano Especial ($24.900), Sándwich de Pollo ($21.900), Sándwich Vegetariano ($18.900), Pizza Margarita ($18.000), Pizza Pepperoni ($21.000), Teriyaki Chicken Bowl ($22.500), Smash Burger Combo ($28.900) y Spicy Sushi Set ($32.500), con precios ilustrativos. «Dulce Panal» no tiene repartidores cerca para demostrar la regla de cobertura.

## 12. Pendientes para el siguiente sprint

1. **Firebase**: implementar `CatalogRepository`, `OrderRepository` y `AuthRepository` con Firestore y Firebase Auth; sincronización en tiempo real entre teléfonos (streams en lugar de `ChangeNotifier` en memoria) y reglas de seguridad por rol.
2. **Autenticación real**: correo/contraseña segura, recuperación de contraseña y verificación real del correo universitario.
3. **Pagos**: integración con una pasarela (Nequi, PSE, tarjeta) y manejo de estados de pago y reembolsos.
4. **Geolocalización**: GPS con permisos, cálculo real de cobertura y seguimiento del repartidor en mapa.
5. **Notificaciones push** con Firebase Cloud Messaging.
6. Subida segura de documentos y evidencias a almacenamiento en la nube.
7. Ejecutar `integration_test` y `flutter build apk` en un equipo con Android SDK y medir cobertura de pruebas.
