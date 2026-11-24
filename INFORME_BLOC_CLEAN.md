# Informe: cómo se implementó Clean Architecture + Bloc en Biffy

Escrito para entender el código, no solo para usarlo. Cubre **solo el slice de
pedidos** (comprador → restaurante → repartidor), que es lo único migrado.

---

## 1. La idea en 30 segundos

Antes, las pantallas llamaban a un `OrderService` que mezclaba todo: reglas de
negocio, guardado de datos, notificaciones y estado. Ahora el código está en
**capas**, y cada capa solo conoce a la de adentro:

```
 Pantalla (Flutter)
     │  bloc.add(evento)  /  context.watch<OrdersBloc>()
     ▼
 OrdersBloc  ───────────►  Casos de uso (domain/usecases/orders)
 (features/orders/bloc)        │ usan
                               ▼
                    Interfaces del dominio
        OrderRepository · OrderCatalogPort · OrderBuyerPort
        OrderWalletPort · OrderNotifier
                               ▲
                               │ implementan
        ┌──────────────────────┴──────────────────────┐
  InMemoryOrderRepository                  SupabaseOrderRepository
  (demo y tests)                           (servidor real)
  + adaptadores en shared/adapters (CatalogController, SessionController,
    NotificationCenter)
```

**Regla de oro:** las flechas solo apuntan hacia el dominio. El dominio no sabe
que existen Flutter, Supabase ni Bloc. Eso se comprueba automáticamente en
`test/architecture_test.dart`.

**Qué se gana:** se puede cambiar Supabase por otra cosa sin tocar reglas ni
pantallas, y se pueden probar las reglas con un repositorio falso, sin red.

---

## 2. Mapa de carpetas

| Capa | Carpeta | Qué contiene |
|---|---|---|
| Entidades | `lib/domain/entities/` | `Order`, `Address`, `Dish`, `AppUser`, etc. Dart puro. |
| Contratos | `lib/domain/repositories/`, `lib/domain/ports/` | Interfaces que el dominio *exige* que alguien implemente. |
| Reglas puras | `lib/domain/*.dart` | `pricing`, `order_rules`, `catalog_rules`, `scheduling`. Funciones sin estado. |
| Casos de uso | `lib/domain/usecases/orders/` | Una clase por acción del usuario. |
| Errores | `lib/domain/order_errors.dart` | Código del servidor → mensaje en español. |
| Datos | `lib/data/repositories/` | Implementaciones: en memoria y Supabase. |
| Adaptadores | `lib/shared/adapters/order_adapters.dart` | Pegan los puertos con los controladores viejos. |
| Presentación | `lib/features/orders/bloc/` | `OrdersBloc`, eventos y estado. |
| Composición | `lib/app/di/` (GetIt) | Único lugar donde se decide qué implementación se usa. |

---

## 3. Capa de dominio

### 3.1 `OrderResult` (`order_repository.dart`)
El "sobre" con el que vuelve **toda** operación, igual en demo y con servidor.

- `code`: `ok`, `invalid_state`, `already_assigned`, `wrong_code`, `network`…
  Es el mismo vocabulario que devuelven las funciones SQL.
- `order`: el pedido afectado, si aplica.
- `ok`: atajo para `code == 'ok'`.
- `message`: texto en español listo para mostrar. Nunca se enseña el código crudo.
- `isTransportError`: `true` si falló la red (el servidor pudo o no haber procesado).
- `OrderResult.validation(msg)`: error detectado en el celular antes de llamar al servidor.

### 3.2 `PlaceOrderRequest`
Paquete con todo lo necesario para crear un pedido: comprador, restaurante,
dirección, pago, líneas, totales calculados, distancia, ETA, pago al repartidor
y `clientKey`. El caso de uso lo arma; el repositorio lo consume.

### 3.3 `OrderRepository` (la interfaz)
Define **qué** se puede hacer con pedidos, sin decir **cómo**.

| Miembro | Para qué sirve |
|---|---|
| `all` | Lista de pedidos visibles, más reciente primero. Lectura síncrona sobre una caché. |
| `byId(id)` | Busca por código visible (`BF-2041`) o por id interno. |
| `changes` | `Stream` que avisa "la caché cambió". El Bloc lo escucha. |
| `isRemote` | `true` si hay servidor. Cambia el comportamiento: con servidor, él mueve Gotas y cupones. |
| `refresh()` | Relee desde la fuente. Nunca lanza. |
| `place(request)` | Crea el pedido. |
| `accept / reject / markReady` | Acciones del restaurante. |
| `cancelByBuyer` | El comprador cancela. |
| `acceptOffer / declineOffer / confirmPickup / deliver` | Acciones del repartidor. |
| `insertSeed` | Solo para datos de demostración. |

### 3.4 Puertos (`ports/order_ports.dart`)
Los casos de uso necesitan cosas de otras partes de la app (catálogo, sesión,
notificaciones). En vez de importarlas, el dominio **declara lo que necesita** y
alguien más lo implementa.

- `OrderCatalogPort`: `dishById`, `restaurantById`, `branchesOf`, `recordSale`.
- `OrderBuyerPort`: `verifiedUniversityId`, `gotasOf`, `currentPoint` (datos que afectan el precio).
- `OrderWalletPort`: `spendGotas`, `creditGotas`, `setCouponUsed` (solo demo) y `syncBalance` (releer saldo del servidor).
- `OrderNotifier`: un método por hito: `placed`, `accepted`, `rejected`, `ready`, `assigned`, `pickedUp`, `delivered`, `buyerCancelled`.

### 3.5 Casos de uso (`usecases/orders/`)
Cada clase hace **una** cosa y se invoca como función (`call`).

**`checkout_draft.dart`**
- `CheckoutDraft`: datos crudos de la pantalla (comprador, restaurante, líneas, dirección, pago, propina, Gotas, cupón, nota).
- `newClientKey()`: genera 16 bytes aleatorios en hexadecimal. Es la **clave de idempotencia**: si reintentas con la misma clave, el servidor no duplica el pedido.

**`checkout.dart`**
- `PreviewCheckout.call(draft)`: calcula totales (subtotal, descuento de campus, domicilio, cupón, Gotas, propina) llamando a `computeTotals`, la función pura de `pricing.dart`.
- `PreviewCheckout.lines(draft)`: convierte el carrito en `OrderLine` con precio unitario.
- `ValidateCheckout.call(draft)`: devuelve la lista de errores en español: sin sesión, carrito vacío, fuera de zona (`isReachable`), plato agotado o sin porciones, restaurante cerrado, horario programado inválido, cupón usado. Con servidor además exige que dirección y cupón tengan uuid real.

**`place_order.dart` → `PlaceOrder.call(draft, {clientKey})`**
1. Valida. Si hay errores, devuelve `OrderResult.validation`.
2. Calcula punto, distancia, líneas, totales, ETA y pago al repartidor.
3. Llama `repo.place(PlaceOrderRequest(...))`.
4. Si salió bien, `_applyEffects`: con servidor solo relee el saldo (la base ya descontó las Gotas); en demo descuenta localmente. Marca el cupón, suma ventas del día y notifica.

**`order_commands.dart`** — todas heredan de `_OrderCommand`, que comparte el repositorio y los puertos:
- `refund(order)`: con servidor, solo relee saldo; en demo devuelve Gotas y libera el cupón.
- `CancelOrder`: cancela, devuelve Gotas/cupón y avisa al restaurante.
- `AcceptOrder`, `MarkOrderReady`: llaman al repositorio y, si salió bien, notifican.
- `RejectOrder`: exige motivo no vacío, rechaza, devuelve Gotas/cupón y avisa.
- `AcceptOffer`: asignación atómica; si otro repartidor ganó, vuelve `already_assigned`.
- `DeclineOffer`: registra el rechazo de la oferta.
- `ConfirmPickup`: exige los tres checks (código, bolsa sellada, productos) antes de llamar.
- `CompleteDelivery`: valida estado local, con servidor exige foto, llama a `deliver`, y en demo acredita Gotas.

**`order_queries.dart` → `OrderQueries`** (solo lectura): `forBuyer`, `forBusiness` (por sedes del negocio), `activeForCourier`, `deliveredBy`, `availableOffers` (listos, sin repartidor, que no rechazó, compatibles con zona y vehículo).

**`order_usecases.dart` → `OrderUseCases`**: ensambla todos los casos de uso con sus dependencias. Es el "paquete" que recibe el Bloc. `syncWallet()` relee el saldo.

### 3.6 `order_errors.dart`
- `orderErrorMessage(code, data)`: traduce cada `result` a español (con precios esperados, nombre del plato, etc.).
- `isTransportError(code)`: `network`, `server_error`, `upload_failed`.

---

## 4. Capa de datos

### 4.1 `InMemoryOrderRepository` (demo y tests)
Guarda la lista en memoria y simula las reglas del servidor.
- `place`: crea el pedido con códigos de 4 dígitos; usa `_byClientKey` para que un reintento con la misma clave devuelva el mismo pedido.
- `_transition(id, estado, actor)`: valida con `canTransition` (tabla `kAllowedTransitions`) y mueve el estado.
- `deliver`: exige estar `onTheWay`, ser el repartidor asignado, código correcto y evidencia.
- `_emit()`: avisa por `changes`.

### 4.2 `SupabaseOrderRepository` (real)
- `place`: arma el payload (`_placePayload`) **sin precios unitarios**: manda qué quiere y lo que *cree* que pagará; el servidor recalcula y rechaza si no coincide.
- `_command(fn, id)`: busca el uuid del pedido y llama la función SQL correspondiente (`restaurant_accept`, `courier_accept`…). Si no tiene uuid, devuelve `not_synced`.
- `_rpc(fn, params)`: llama la función con **timeout de 20 s**; traduce errores a `server_error` o `network` (nunca expone el mensaje crudo) y **siempre recarga**, porque el servidor tiene la última palabra.
- `refresh()`: junta varias peticiones simultáneas en una sola recarga para no pisar datos nuevos con respuestas viejas. `_refreshOnce` lee pedidos, líneas, eventos, rechazos y `order_secrets` (el código de entrega, que solo ve el comprador).
- `deliver`: sube la foto al bucket `delivery-evidence` y luego llama `courier_deliver`. Si la subida falla, no entrega (`upload_failed`).
- `_subscribe`: Realtime sobre `orders` y `order_events`, más un sondeo cada 30 s por si Realtime falla.

### 4.3 Adaptadores (`shared/adapters/order_adapters.dart`)
- `CatalogOrderAdapter` → implementa `OrderCatalogPort` sobre `CatalogController`.
- `SessionOrderAdapter` → implementa `OrderBuyerPort` y `OrderWalletPort` sobre `SessionController` (`syncBalance` llama `syncGotas`).
- `NotificationOrderAdapter` → implementa `OrderNotifier` sobre `NotificationCenter`: cada hito construye los avisos para comprador, restaurante y repartidor.

Existen porque el catálogo, la sesión y las notificaciones **todavía** son
`ChangeNotifier`. Cuando se migren, solo cambian estos adaptadores.

---

## 5. Capa de presentación: el Bloc

### 5.1 Eventos (`orders_event.dart`)
`sealed class OrdersEvent`: la UI solo despacha estos.

| Evento | Quién | Significado |
|---|---|---|
| `OrdersChanged` | interno | El repositorio cambió: refrescar la lista. |
| `OrderPlaced(draft, clientKey)` | comprador | Confirmar pedido. |
| `OrderCancelled(id)` | comprador | Cancelar. |
| `OrderAccepted(id)` / `OrderRejected(id, motivo)` / `OrderMarkedReady(id)` | restaurante | Aceptar, rechazar, listo. |
| `OfferAccepted(id, courier, vehicle)` / `OfferDeclined(id, courierId)` | repartidor | Tomar o descartar oferta. |
| `PickupConfirmed(...)` | repartidor | Recogida con los tres checks. |
| `DeliveryCompleted(id, courierId, code, evidence, bytes)` | repartidor | Entregar. |

Al ser `sealed`, el compilador obliga a manejar todos en un `switch`.

### 5.2 Estado (`orders_state.dart`)
- `OrdersState.orders`: lista de pedidos.
- `revision`: contador que sube con cada refresco. Existe porque los `Order` son **objetos mutables** que el repositorio modifica en sitio; sin esto, Flutter vería la misma lista y no repintaría.
- `outcome`: el resultado de la última acción.
- `OrderOutcome(id, action, result, orderId)`: `id` crece en cada resultado, así un `BlocListener` reacciona **una sola vez** (mostrar aviso, navegar, confeti).
- `OrderAction`: enum de acciones (`place`, `cancel`, `accept`, …).

### 5.3 `OrdersBloc` (`orders_bloc.dart`)
**Constructor.** Registra un `on<Evento>` por cada evento; casi todos llaman a `_run`. Al final se suscribe a `repo.changes` y por cada cambio hace `add(OrdersChanged())`.

**`_run(emit, action, orderId, operation)`** — el corazón:
1. Arma la llave `accion:idPedido` y, si ya está en `_inFlight`, **ignora** (evita el doble toque).
2. Ejecuta el caso de uso.
3. Si lanza una excepción, la convierte en `OrderResult('server_error')` en vez de mostrar la excepción.
4. Saca la llave de `_inFlight`.
5. Emite estado nuevo: pedidos actualizados, `revision + 1` y un `OrderOutcome`.

**`_onChanged`**: emite la lista nueva. Con servidor, además relee el saldo de Gotas (`_syncingWallet` evita lecturas simultáneas).

**`request(event)`** — para pantallas que necesitan el resultado en el mismo `onPressed` (confirmar → navegar, entregar → confeti):
1. Calcula qué acción y pedido esperar (`_describe`).
2. Se suscribe al `stream` y espera un `outcome` con `id` mayor al último, misma acción y mismo pedido.
3. Despacha el evento con `add`.
4. Devuelve el resultado; si pasan 60 s, devuelve `network`.

Sigue siendo Bloc (el evento entra por `add`, la respuesta sale del estado), pero evita tener que partir cada flujo secuencial en un `BlocListener`.

**Atajos de lectura** (`all`, `byId`, `forBuyer`, `forBusiness`, `activeForCourier`, `deliveredBy`, `availableOffers`, `preview`, `validate`, `isRemote`): delegan a `useCases.queries`/`preview`/`validate`. Son síncronos porque leen la caché del repositorio.

**`close`**: cancela la suscripción a `changes`.

### 5.4 Cómo la usa una pantalla
Ejemplo real, `checkout_screen.dart`:
```dart
final outcome = await orders.request(OrderPlaced(draft, clientKey: _clientKey));
if (outcome.result.ok) { cart.clear(); context.go('/pedido/${outcome.orderId}'); }
else { showSnack(context, outcome.result.message, error: true); }
```
- Se reutiliza `_clientKey` si falló la red (reintento seguro) y se descarta si el servidor rechazó el pedido.
- Para listas y estados: `context.watch<OrdersBloc>()` y leer `bloc.forBuyer(...)`.
- `app.dart` escucha `orders.stream` y muestra un aviso global cuando falla aceptar, rechazar, marcar listo o descartar oferta.

---

## 6. Composición (GetIt, `lib/app/di/`)

`_buildOrders` es el único lugar donde se decide con qué se arma todo:

```dart
OrdersBloc(OrderUseCases(
  repo: repo,                              // en memoria o Supabase
  catalog: CatalogOrderAdapter(catalog),
  buyers: sessionAdapter, wallet: sessionAdapter,
  notifier: NotificationOrderAdapter(notifications, demo: demo),
  clock: clock,
))
```
Sin credenciales, `data_module.dart` registra el repositorio en memoria; con ellas registra
el de Supabase. El resto del código no se entera. El Bloc se publica con
`BlocProvider<OrdersBloc>.value`.

---

## 7. Cómo se hace cumplir (`test/architecture_test.dart`)
1. `lib/domain` no importa `data`, `features`, `shared`, `app`, ni Flutter, Bloc, Supabase, Provider o GoRouter.
2. `lib/features/orders` no importa `data`, `shared` ni nada de Supabase.
3. Los dos repositorios de pedidos contienen `implements OrderRepository` y lo importan desde el dominio.
4. Ninguna pantalla de `lib/features` importa repositorios de pedidos.

---

## 8. Recorrido completo: "Diego confirma un pedido"
1. `CheckoutScreen._place` crea el `CheckoutDraft` y llama `bloc.request(OrderPlaced)`.
2. `OrdersBloc` ejecuta `_run` → `PlaceOrder.call`.
3. `ValidateCheckout` revisa; `PreviewCheckout` calcula totales.
4. `SupabaseOrderRepository.place` manda el payload a `place_order`.
5. El servidor recalcula precios y descuentos, crea el pedido, el código en `order_secrets` y el evento `pending`, y descuenta Gotas y cupón.
6. El repositorio inserta el pedido en caché, emite `changes` y recarga.
7. `PlaceOrder._applyEffects` relee el saldo, suma ventas y notifica.
8. `_run` emite un `OrderOutcome`; `request` lo devuelve y la pantalla navega al seguimiento.
9. Qbano y Andrés ven el cambio por Realtime (o por el sondeo de 30 s).

---

## 9. Qué quedó fuera (honestidad)
- **Pedidos, autenticación y carrito ya usan Bloc.** Además de `OrdersBloc` hay `LoginCubit`, `RegisterCubit`, `UniversityVerificationCubit` (Campus), `CartCubit` (reemplaza a `CartController`) y `CheckoutCubit`. Sesión, catálogo y notificaciones siguen siendo `ChangeNotifier` registrados en GetIt, y se migrarían de a un slice.
- **Las entidades `Order` son mutables.** Por eso existe `revision`. En Bloc "puro" el estado sería inmutable.
- **`request()` es una conveniencia propia**, no una API estándar de Bloc.
- **Tras el merge con `dev`**, sesión, direcciones y verificación universitaria son los de `dev` (`SessionController` + `SupabaseProfileRepository`); el pedido solo consume `Address.serverId`.
- Falta la prueba real con los tres roles contra tu Supabase.

---

## 10. Pruebas
- `test/unit/order_usecases_test.dart` y `order_usecases_remote_test.dart`: casos de uso con repositorio en memoria y con un `FakeOrderRepository` que simula el servidor.
- `test/unit/orders_bloc_test.dart`: doble toque, `request`, excepciones, outcome.
- `test/unit/order_errors_test.dart`: cada código del servidor tiene mensaje en español.
- `test/architecture_test.dart`: las reglas de dependencia.
- `test/widget/*` e `integration/full_flow_test.dart`: el flujo de tres roles por la interfaz.
