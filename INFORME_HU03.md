# Informe HU-3 · Ciclo completo del pedido

> Comprador → Restaurante → Repartidor, con datos reales en Supabase.
> Todas las rutas son enlaces: haz clic (o `Ctrl+clic` en VS Code) para abrir el archivo en la línea indicada.

---

## 1. Estado en una mirada

| Pieza | Estado |
|---|---|
| Código Flutter (Clean + Bloc) | ✅ Hecho · `flutter analyze` sin avisos · **166 tests en verde** |
| Migración SQL `0012` | ✅ Escrita y **probada en un Postgres local** (87 comprobaciones) · ⏳ **NO aplicada en tu Supabase real** |
| Dependencias de otras HU | ✅ Eliminadas las que bloqueaban el flujo (direcciones, verificación universitaria) |
| Prueba con los 3 roles contra Supabase real | ⏳ Pendiente: depende de aplicar la migración |

### Por qué no apliqué la migración yo mismo
Me autorizaste, pero **no tengo con qué ejecutarla**: en el proyecto solo existe la clave *publicable* de Supabase (`env.example.json`), que por diseño no puede modificar el esquema. No hay contraseña de la base, ni `service_role`, ni un token del CLI, y no tengo conectada ninguna herramienta de Supabase ni de navegador. No busqué credenciales fuera del proyecto. Lo único que falta es **un pegado y un clic** tuyo (sección 2).

---

## 2. Cómo aplicar la migración (1 paso)

1. Abre <https://supabase.com/dashboard/project/jwdzpwsfwtkdeeuceaco/sql/new> (inicia sesión con la cuenta dueña del proyecto).
2. En VS Code abre [supabase/aplicar_hu03.sql](supabase/aplicar_hu03.sql) → `Ctrl+A` → `Ctrl+C`.
3. Vuelve al navegador, haz clic en el recuadro grande → `Ctrl+V` → pulsa **Run** (botón verde, abajo a la derecha).
4. Si sale una ventana de "destructive operations", pulsa **Run this query** (el script reemplaza funciones y políticas; no borra datos de tus tablas).
5. **Éxito** = no hay recuadro rojo. Debe aparecer el aviso `Biffy OK · 28 tablas · 35 políticas RLS · 63 funciones`.

Ese archivo es `0012_order_cycle.sql` + `0099_verify.sql` pegados en orden. Es **idempotente** (si algo falla se puede volver a ejecutar) y lo probé sobre una base con exactamente tus migraciones 0000–0011.

Opcional: para correr la prueba, pega [supabase/tests/hu3_order_cycle.sql](supabase/tests/hu3_order_cycle.sql). Todo ocurre dentro de una transacción con `ROLLBACK`, no deja datos. Si falla al crear usuarios de prueba, es una diferencia con mi Postgres local; pásame el mensaje.

---

## 3. Base de datos · [supabase/migrations/0012_order_cycle.sql](supabase/migrations/0012_order_cycle.sql) (919 líneas)

### 3.1 Historial de eventos
| Líneas | Qué hace |
|---|---|
| [24-26](supabase/migrations/0012_order_cycle.sql#L24-L26) | Agrega `order_events.from_status`: de qué estado venía cada evento. |
| [28-38](supabase/migrations/0012_order_cycle.sql#L28-L38) | Rellena `from_status` en los eventos que ya existían (usa el evento anterior del mismo pedido). |
| [40](supabase/migrations/0012_order_cycle.sql#L40) | Borra la versión vieja de `order_event` (3 parámetros) para no tener dos. |
| [42-56](supabase/migrations/0012_order_cycle.sql#L42-L56) | Crea `order_event(pedido, estado, etiqueta, desde)`: inserta el evento con quién lo hizo (`auth.uid()`), cuándo (por defecto `now()`) y de qué estado a cuál. |

### 3.2 Código de entrega secreto
| Líneas | Qué hace |
|---|---|
| [59-63](supabase/migrations/0012_order_cycle.sql#L59-L63) | Tabla `order_secrets` (pedido, comprador, código). El código ya no vive en `orders`. |
| [65-69](supabase/migrations/0012_order_cycle.sql#L65-L69) | RLS: **solo el comprador** puede leer su código. El repartidor no, así `wrong_code` protege de verdad. |
| [72-76](supabase/migrations/0012_order_cycle.sql#L72-L76) | Mueve a `order_secrets` los códigos de pedidos existentes. |
| [78-80](supabase/migrations/0012_order_cycle.sql#L78-L80) | Deja `orders.delivery_code` vacío (por defecto y en filas viejas) para que no se filtre. |

### 3.3 Idempotencia
| Líneas | Qué hace |
|---|---|
| [84](supabase/migrations/0012_order_cycle.sql#L84) | Columna `orders.client_key`: clave que manda la app por intento de compra. |
| [86-88](supabase/migrations/0012_order_cycle.sql#L86-L88) | Índice único (comprador, clave): la misma clave nunca crea dos pedidos. |

### 3.4 Funciones auxiliares
| Líneas | Qué hace |
|---|---|
| [93-107](supabase/migrations/0012_order_cycle.sql#L93-L107) | `distance_km`: distancia Haversine en km (misma fórmula que `geo.dart`). |
| [109-135](supabase/migrations/0012_order_cycle.sql#L109-L135) | `refund_order`: devuelve las Gotas ([116-121](supabase/migrations/0012_order_cycle.sql#L116-L121)) **y el cupón** ([123-134](supabase/migrations/0012_order_cycle.sql#L123-L134): vuelve a "sin usar" y baja `used_count`). |
| [139-153](supabase/migrations/0012_order_cycle.sql#L139-L153) | `order_json`: el pedido en JSON, con el código de entrega solo si lo pide su comprador. |

### 3.5 `place_order` ([157-526](supabase/migrations/0012_order_cycle.sql#L157-L526)): crear el pedido
Todo el cálculo ocurre en el servidor; lo que mande el cliente solo sirve para comparar.

| Líneas | Qué hace |
|---|---|
| [164-202](supabase/migrations/0012_order_cycle.sql#L164-L202) | Variables y comprobación de sesión (`not_authenticated`). |
| [204-215](supabase/migrations/0012_order_cycle.sql#L204-L215) | **Reintento**: si ya hay un pedido con esa `client_key`, lo devuelve (`duplicate: true`) sin crear otro. |
| [217-226](supabase/migrations/0012_order_cycle.sql#L217-L226) | Bloquea el perfil (`for update`) para que dos pedidos simultáneos no gasten las mismas Gotas; valida perfil (`no_profile`) y método de pago (`invalid_payment`). |
| [228-250](supabase/migrations/0012_order_cycle.sql#L228-L250) | Valida sede (`branch_not_found`, `branch_paused`), dirección **del propio comprador** (`address_not_found`) y punto de entrega (`point_not_found`). |
| [252-263](supabase/migrations/0012_order_cycle.sql#L252-L263) | Regla de alcance (espejo de `isReachable`): solo-campus, repartidores cerca y radio → `out_of_zone`. |
| [265-267](supabase/migrations/0012_order_cycle.sql#L265-L267) | Carrito vacío → `empty_cart`. |
| [269-349](supabase/migrations/0012_order_cycle.sql#L269-L349) | **Líneas**: valida cantidad 1-50, plato activo y con porciones; el precio sale de `dishes` + `dish_options` (tamaño [301-310](supabase/migrations/0012_order_cycle.sql#L301-L310), acompañante [312-321](supabase/migrations/0012_order_cycle.sql#L312-L321), extras [323-333](supabase/migrations/0012_order_cycle.sql#L323-L333)). **Ignora cualquier `unit_price` del cliente.** |
| [351-357](supabase/migrations/0012_order_cycle.sql#L351-L357) | Descuento de campus: solo si el perfil está verificado en esa universidad. |
| [359-364](supabase/migrations/0012_order_cycle.sql#L359-L364) | Tarifa: $1.500 dentro del campus, $3.500 fuera. |
| [366-386](supabase/migrations/0012_order_cycle.sql#L366-L386) | Cupón: del usuario, vigente, sin usar y con usos disponibles; se bloquea la fila para evitar doble uso. |
| [388-395](supabase/migrations/0012_order_cycle.sql#L388-L395) | Gotas: no más que el saldo (`insufficient_gotas`) ni que lo que falta por pagar (`invalid_gotas`). |
| [397-400](supabase/migrations/0012_order_cycle.sql#L397-L400) | Propina: máximo 20 % del subtotal (`invalid_tip`). |
| [402-405](supabase/migrations/0012_order_cycle.sql#L402-L405) | Total calculado por el servidor. |
| [406-424](supabase/migrations/0012_order_cycle.sql#L406-L424) | **Antimanipulación**: si el cliente declaró otro subtotal/total → `subtotal_mismatch` / `total_mismatch` (con el total correcto) y **no se crea nada**. |
| [426-432](supabase/migrations/0012_order_cycle.sql#L426-L432) | Tiempo estimado y pago al repartidor calculados aquí; códigos de entrega y recogida aleatorios de 4 dígitos. |
| [434-467](supabase/migrations/0012_order_cycle.sql#L434-L467) | Inserta el pedido y guarda el código en `order_secrets`. |
| [469-481](supabase/migrations/0012_order_cycle.sql#L469-L481) | Inserta las líneas con los precios calculados. |
| [483](supabase/migrations/0012_order_cycle.sql#L483) | Primer evento: `pending` (sin estado de origen). |
| [485-499](supabase/migrations/0012_order_cycle.sql#L485-L499) | Descuenta Gotas y marca el cupón como usado. |
| [501-503](supabase/migrations/0012_order_cycle.sql#L501-L503) | Responde `ok` con el pedido (incluye el código solo para su comprador). |
| [505-526](supabase/migrations/0012_order_cycle.sql#L505-L526) | Errores: carrera de la misma clave → devuelve el ganador; datos mal formados → `invalid_payload` (nunca un error crudo). |

### 3.6 Acciones por rol
Todas: bloquean la fila del pedido (`for update`), validan **quién eres** (`forbidden`) y **el estado** (`invalid_state`) y escriben el evento con su estado de origen.

| Función | Líneas | Qué hace |
|---|---|---|
| `restaurant_accept` | [530-558](supabase/migrations/0012_order_cycle.sql#L530-L558) | Solo el dueño de la sede; `pending → preparing`. |
| `restaurant_reject` | [560-595](supabase/migrations/0012_order_cycle.sql#L560-L595) | `pending → cancelled`, guarda el motivo y llama a `refund_order` ([591](supabase/migrations/0012_order_cycle.sql#L591)). |
| `restaurant_ready` | [597-625](supabase/migrations/0012_order_cycle.sql#L597-L625) | `preparing → ready` (publica la oferta). |
| `buyer_cancel` | [627-659](supabase/migrations/0012_order_cycle.sql#L627-L659) | Solo el comprador dueño; `pending → cancelled` + reembolso. |
| `courier_accept` | [661-728](supabase/migrations/0012_order_cycle.sql#L661-L728) | Asignación **atómica**: bloquea al repartidor ([672](supabase/migrations/0012_order_cycle.sql#L672)) → `busy` ([685](supabase/migrations/0012_order_cycle.sql#L685)); bloquea el pedido ([688](supabase/migrations/0012_order_cycle.sql#L688)) → `already_assigned` ([695](supabase/migrations/0012_order_cycle.sql#L695)); `out_of_range` según el vehículo ([698](supabase/migrations/0012_order_cycle.sql#L698)); `out_of_zone` para zona campus ([701-707](supabase/migrations/0012_order_cycle.sql#L701-L707)); `declined_before` ([709-714](supabase/migrations/0012_order_cycle.sql#L709-L714)). |
| `courier_decline` | [730-752](supabase/migrations/0012_order_cycle.sql#L730-L752) | Registra el rechazo (solo si la oferta sigue disponible). |
| `courier_pickup` | [754-782](supabase/migrations/0012_order_cycle.sql#L754-L782) | Solo el repartidor asignado; `ready → on_the_way`. |
| `courier_deliver` | [784-850](supabase/migrations/0012_order_cycle.sql#L784-L850) | Compara el código con `order_secrets` ([812](supabase/migrations/0012_order_cycle.sql#L812)); exige que la foto exista en Storage **dentro de la carpeta de ese pedido** ([815-823](supabase/migrations/0012_order_cycle.sql#L815-L823)); entrega y acredita Gotas. |

### 3.7 Storage, lectura y permisos
| Líneas | Qué hace |
|---|---|
| [852-856](supabase/migrations/0012_order_cycle.sql#L852-L856) | Bucket `delivery-evidence`: máx. 5 MB y solo jpeg/png/webp. |
| [858-869](supabase/migrations/0012_order_cycle.sql#L858-L869) | Solo el repartidor asignado puede subir fotos, y solo mientras el pedido va `on_the_way`. |
| [875-893](supabase/migrations/0012_order_cycle.sql#L875-L893) | `can_read_order`: las ofertas "listas sin repartidor" solo las ven **repartidores** (antes, cualquier usuario). |
| [895-903](supabase/migrations/0012_order_cycle.sql#L895-L903) | Misma regla en la política de lectura de `orders`. |
| [907-914](supabase/migrations/0012_order_cycle.sql#L907-L914) | Revoca `insert/update/delete/truncate` sobre las tablas de pedidos: solo se escribe por RPC. |
| [916-919](supabase/migrations/0012_order_cycle.sql#L916-L919) | Funciones internas (`refund_order`, `order_json`, **`credit_gotas`**, `order_event`) no llamables por clientes. Esto cierra el hueco por el que cualquier usuario podía regalarse Gotas. |

### 3.8 Archivos relacionados
| Archivo | Para qué sirve |
|---|---|
| [supabase/aplicar_hu03.sql](supabase/aplicar_hu03.sql) | `0012` + `0099` en un solo pegado (generado). |
| [supabase/apply_all.sql](supabase/apply_all.sql) | Instalación completa desde cero (0000-0099), regenerado. |
| [supabase/migrations/0099_verify.sql](supabase/migrations/0099_verify.sql) | Ahora también comprueba `order_secrets`, `from_status`, `client_key` y las funciones nuevas ([líneas 24, 30 y 36](supabase/migrations/0099_verify.sql#L24-L36)). |
| [supabase/tests/hu3_order_cycle.sql](supabase/tests/hu3_order_cycle.sql) | Prueba de punta a punta (507 líneas, 87 `PASS`): precios, manipulación, idempotencia, reembolsos, permisos, carrera de repartidores, código y foto, escrituras directas bloqueadas. |
| [supabase/README.md](supabase/README.md) | Documentación de RPC, seguridad y resultados posibles. |

---

## 4. Flutter · Clean Architecture + Bloc (pedidos)

```
Pantalla ──evento──▶ OrdersBloc ──▶ Caso de uso ──▶ OrderRepository (interfaz, dominio)
                                                        ▲                ▲
                                         InMemoryOrderRepository   SupabaseOrderRepository
```

### 4.1 Dominio (Dart puro: no importa Flutter, Supabase ni `data`)
| Archivo | Qué hace |
|---|---|
| [lib/domain/entities/](lib/domain/entities/) | Entidades movidas aquí: `order`, `address`, `cart`, `catalog`, `user`. |
| [lib/domain/repositories/order_repository.dart](lib/domain/repositories/order_repository.dart) | `OrderResult` ([15](lib/domain/repositories/order_repository.dart#L15): código + pedido + mensaje en español), `PlaceOrderRequest` ([45](lib/domain/repositories/order_repository.dart#L45): todo lo necesario para crear un pedido) y la interfaz `OrderRepository` ([86-131](lib/domain/repositories/order_repository.dart#L86-L131)): lecturas, `place`, y una operación por acción. |
| [lib/domain/ports/order_ports.dart](lib/domain/ports/order_ports.dart) | Qué necesita el dominio del resto de la app: catálogo ([7](lib/domain/ports/order_ports.dart#L7)), comprador ([19](lib/domain/ports/order_ports.dart#L19)), billetera de Gotas ([31](lib/domain/ports/order_ports.dart#L31)) y avisos ([42](lib/domain/ports/order_ports.dart#L42)). |
| [lib/domain/order_errors.dart](lib/domain/order_errors.dart) | `orderErrorMessage` ([8](lib/domain/order_errors.dart#L8)): traduce cada `result` a un mensaje en español, nunca el código crudo. |
| [lib/domain/usecases/orders/checkout_draft.dart](lib/domain/usecases/orders/checkout_draft.dart) | `CheckoutDraft` ([11](lib/domain/usecases/orders/checkout_draft.dart#L11)) y `newClientKey` ([39](lib/domain/usecases/orders/checkout_draft.dart#L39), clave aleatoria de 32 caracteres). |
| [lib/domain/usecases/orders/checkout.dart](lib/domain/usecases/orders/checkout.dart) | `PreviewCheckout` ([12](lib/domain/usecases/orders/checkout.dart#L12): totales y líneas) y `ValidateCheckout` ([64](lib/domain/usecases/orders/checkout.dart#L64): carrito, zona, horario, porciones, y con servidor exige dirección/cupón con uuid). |
| [lib/domain/usecases/orders/place_order.dart](lib/domain/usecases/orders/place_order.dart) | `PlaceOrder` ([18](lib/domain/usecases/orders/place_order.dart#L18)): valida → arma la petición ([36-71](lib/domain/usecases/orders/place_order.dart#L36-L71)) → llama al repositorio → aplica efectos ([73-86](lib/domain/usecases/orders/place_order.dart#L73-L86): con servidor solo relee el saldo; en demo descuenta Gotas). |
| [lib/domain/usecases/orders/order_commands.dart](lib/domain/usecases/orders/order_commands.dart) | Un caso de uso por acción: `CancelOrder` ([40](lib/domain/usecases/orders/order_commands.dart#L40)), `AcceptOrder` ([56](lib/domain/usecases/orders/order_commands.dart#L56)), `RejectOrder` ([67](lib/domain/usecases/orders/order_commands.dart#L67)), `MarkOrderReady` ([84](lib/domain/usecases/orders/order_commands.dart#L84)), `AcceptOffer` ([99](lib/domain/usecases/orders/order_commands.dart#L99)), `DeclineOffer` ([116](lib/domain/usecases/orders/order_commands.dart#L116)), `ConfirmPickup` ([124](lib/domain/usecases/orders/order_commands.dart#L124): exige los 3 checks), `CompleteDelivery` ([151](lib/domain/usecases/orders/order_commands.dart#L151): con servidor exige foto antes de molestar al servidor). |
| [lib/domain/usecases/orders/order_queries.dart](lib/domain/usecases/orders/order_queries.dart) | Consultas de lectura por rol (`forBuyer`, `forBusiness`, `availableOffers`…). |
| [lib/domain/usecases/orders/order_usecases.dart](lib/domain/usecases/orders/order_usecases.dart) | `OrderUseCases` ([18](lib/domain/usecases/orders/order_usecases.dart#L18)): ensambla todos los casos de uso. |

### 4.2 Datos (implementan la interfaz del dominio)
| Archivo | Qué hace |
|---|---|
| [lib/data/repositories/in_memory_order_repository.dart](lib/data/repositories/in_memory_order_repository.dart) | "Servidor falso" de la demo. Mismas reglas y mismos códigos que los RPC: `place` ([72](lib/data/repositories/in_memory_order_repository.dart#L72)), `cancelByBuyer` ([111](lib/data/repositories/in_memory_order_repository.dart#L111)), `acceptOffer` ([147](lib/data/repositories/in_memory_order_repository.dart#L147): `busy`/`already_assigned`/`out_of_range`), `deliver` ([191](lib/data/repositories/in_memory_order_repository.dart#L191): `wrong_code`/`missing_evidence`). |
| [lib/data/repositories/supabase_order_repository.dart](lib/data/repositories/supabase_order_repository.dart) | Real. `place` ([241](lib/data/repositories/supabase_order_repository.dart#L241)) arma el payload ([258-287](lib/data/repositories/supabase_order_repository.dart#L258-L287): **solo lo que se compra y lo que se espera pagar**); `_command` ([293](lib/data/repositories/supabase_order_repository.dart#L293)) llama a cada RPC; `_rpc` ([348](lib/data/repositories/supabase_order_repository.dart#L348)) con tiempo límite de 20 s y recarga después; `deliver` ([373](lib/data/repositories/supabase_order_repository.dart#L373)) sube la foto y confirma; `refresh` ([89](lib/data/repositories/supabase_order_repository.dart#L89)) agrupa recargas; Realtime + sondeo cada 30 s ([409-431](lib/data/repositories/supabase_order_repository.dart#L409-L431)); mapeo de filas ([446-560](lib/data/repositories/supabase_order_repository.dart#L446-L560)). |
| [lib/data/repositories/rpc_result.dart](lib/data/repositories/rpc_result.dart) | Respuesta normalizada de un RPC; una respuesta rara nunca lanza, es `server_error`. |

### 4.3 Bloc · [lib/features/orders/bloc/](lib/features/orders/bloc/)
| Archivo | Qué hace |
|---|---|
| [orders_event.dart](lib/features/orders/bloc/orders_event.dart) | 10 eventos: `OrderPlaced`, `OrderCancelled`, `OrderAccepted`, `OrderRejected`, `OrderMarkedReady`, `OfferAccepted`, `OfferDeclined`, `PickupConfirmed`, `DeliveryCompleted`, `OrdersChanged`. |
| [orders_state.dart](lib/features/orders/bloc/orders_state.dart) | `OrdersState` ([37](lib/features/orders/bloc/orders_state.dart#L37): `orders`, `revision`, `outcome`) y `OrderOutcome` ([19](lib/features/orders/bloc/orders_state.dart#L19): resultado de la última acción con id creciente). |
| [orders_bloc.dart](lib/features/orders/bloc/orders_bloc.dart) | Cada evento → su caso de uso ([22-110](lib/features/orders/bloc/orders_bloc.dart#L22-L110)); lecturas ([125-149](lib/features/orders/bloc/orders_bloc.dart#L125-L149)); `request` ([158](lib/features/orders/bloc/orders_bloc.dart#L158): despacha y espera el resultado); `_onChanged` ([198](lib/features/orders/bloc/orders_bloc.dart#L198): refresca y relee Gotas); `_run` ([208](lib/features/orders/bloc/orders_bloc.dart#L208): ignora el doble toque y convierte cualquier excepción en `server_error`). |

### 4.4 Composición y adaptadores
| Archivo | Qué hace |
|---|---|
| [lib/shared/state/app_services.dart](lib/shared/state/app_services.dart) | Único lugar que decide demo o Supabase: `demo` ([40](lib/shared/state/app_services.dart#L40)), `supabase` ([78](lib/shared/state/app_services.dart#L78)), `_buildOrders` ([111](lib/shared/state/app_services.dart#L111): repositorio → casos de uso → Bloc). |
| [lib/shared/adapters/order_adapters.dart](lib/shared/adapters/order_adapters.dart) | Conectan los puertos con `CatalogController` ([11](lib/shared/adapters/order_adapters.dart#L11)), `SessionController` ([30](lib/shared/adapters/order_adapters.dart#L30)) y las notificaciones ([63](lib/shared/adapters/order_adapters.dart#L63)). |
| [lib/data/mock/seed_state.dart](lib/data/mock/seed_state.dart) | El seed de la demo ahora recibe el repositorio ([17](lib/data/mock/seed_state.dart#L17), inserta en [179](lib/data/mock/seed_state.dart#L179)). |

### 4.5 Quitar dependencias de otras HU
| Archivo | Qué hace |
|---|---|
| [lib/shared/state/session_controller.dart](lib/shared/state/session_controller.dart) | **Verificación del servidor**: al iniciar sesión lee `profiles.verified` ([254](lib/shared/state/session_controller.dart#L254)); sin esto la app y `place_order` calcularían descuentos distintos y rechazarían el pedido de Diego. `verifyUniversityAsync` ([358](lib/shared/state/session_controller.dart#L358)) usa el RPC. **Direcciones**: `saveAddressAsync` ([430](lib/shared/state/session_controller.dart#L430)) guarda en la cuenta y adopta el uuid real, `deleteAddressAsync` ([481](lib/shared/state/session_controller.dart#L481)), `setDefaultAddressAsync` ([500](lib/shared/state/session_controller.dart#L500)). `syncGotas` ([535](lib/shared/state/session_controller.dart#L535)) relee el saldo. |
| [lib/data/repositories/auth_repository.dart](lib/data/repositories/auth_repository.dart) | Contrato nuevo: `verifiedUniversity` ([59](lib/data/repositories/auth_repository.dart#L59)), `verifyUniversity` ([64](lib/data/repositories/auth_repository.dart#L64)), `saveAddress` ([68](lib/data/repositories/auth_repository.dart#L68)), `deleteAddress` ([75](lib/data/repositories/auth_repository.dart#L75)), `setDefaultAddress` ([78](lib/data/repositories/auth_repository.dart#L78)). |
| [lib/data/repositories/supabase_auth_repository.dart](lib/data/repositories/supabase_auth_repository.dart) | Implementación real: lectura de verificación ([141](lib/data/repositories/supabase_auth_repository.dart#L141)), RPC `verify_university` ([156](lib/data/repositories/supabase_auth_repository.dart#L156)), insertar/actualizar dirección ([171](lib/data/repositories/supabase_auth_repository.dart#L171)), borrado lógico ([216](lib/data/repositories/supabase_auth_repository.dart#L216)), principal única ([229-244](lib/data/repositories/supabase_auth_repository.dart#L229-L244)). |
| [lib/core/utils/ids.dart](lib/core/utils/ids.dart) | `isUuid` ([7](lib/core/utils/ids.dart#L7)): distingue filas del servidor de ids locales. |

### 4.6 Pantallas migradas (despachan eventos al Bloc)
| Pantalla | Qué cambió |
|---|---|
| [checkout_screen.dart](lib/features/buyer/cart/checkout_screen.dart) | `_place` ([202](lib/features/buyer/cart/checkout_screen.dart#L202)): clave de reintento ([208](lib/features/buyer/cart/checkout_screen.dart#L208)) y `OrderPlaced` ([209](lib/features/buyer/cart/checkout_screen.dart#L209)); la clave se conserva solo si fue corte de red ([230](lib/features/buyer/cart/checkout_screen.dart#L230)). |
| [reorder_flow.dart](lib/features/buyer/orders/reorder_flow.dart) | "Pedir ya" usa `OrderPlaced` ([145](lib/features/buyer/orders/reorder_flow.dart#L145)). |
| [tracking_screen.dart](lib/features/buyer/tracking/tracking_screen.dart) | Cancelar: `OrderCancelled` ([245](lib/features/buyer/tracking/tracking_screen.dart#L245)); `invalid_state` → "El restaurante ya lo aceptó" ([253](lib/features/buyer/tracking/tracking_screen.dart#L253)). |
| [merchant_orders_screen.dart](lib/features/restaurant_owner/orders/merchant_orders_screen.dart) | Aceptar ([188](lib/features/restaurant_owner/orders/merchant_orders_screen.dart#L188)), listo ([213](lib/features/restaurant_owner/orders/merchant_orders_screen.dart#L213)), rechazar ([246](lib/features/restaurant_owner/orders/merchant_orders_screen.dart#L246)). |
| [offer_widgets.dart](lib/features/courier/offers/offer_widgets.dart) | Aceptar oferta ([19-43](lib/features/courier/offers/offer_widgets.dart#L19-L43)) y rechazar ([45-48](lib/features/courier/offers/offer_widgets.dart#L45-L48)). |
| [pickup_screen.dart](lib/features/courier/pickup/pickup_screen.dart) | Confirmar recogida con `PickupConfirmed` ([154](lib/features/courier/pickup/pickup_screen.dart#L154)). |
| [delivery_screen.dart](lib/features/courier/delivery/delivery_screen.dart) | `_complete` ([262](lib/features/courier/delivery/delivery_screen.dart#L262)): bloquea el botón mientras sube ([31](lib/features/courier/delivery/delivery_screen.dart#L31), [245](lib/features/courier/delivery/delivery_screen.dart#L245)); con servidor oculta "evidencia demo" ([217](lib/features/courier/delivery/delivery_screen.dart#L217)). |
| [addresses_screen.dart](lib/features/buyer/addresses/addresses_screen.dart) | Guardar ([288](lib/features/buyer/addresses/addresses_screen.dart#L288)), eliminar ([133](lib/features/buyer/addresses/addresses_screen.dart#L133)) y principal ([90](lib/features/buyer/addresses/addresses_screen.dart#L90)) pasan por la cuenta; si falla, aviso claro. |
| [campus_screen.dart](lib/features/buyer/campus/campus_screen.dart) | Verificar correo con el servidor ([121](lib/features/buyer/campus/campus_screen.dart#L121)); sin red, "Intenta de nuevo" ([135](lib/features/buyer/campus/campus_screen.dart#L135)). |
| [lib/app/app.dart](lib/app/app.dart) | Aviso global de errores ([35-61](lib/app/app.dart#L35-L61)) para aceptar/rechazar/listo/rechazar oferta, que no muestran el error por su cuenta. |

---

## 5. Pruebas

| Archivo | Qué prueba |
|---|---|
| [test/architecture_test.dart](test/architecture_test.dart) | Reglas de dependencia: el dominio no importa `data`/UI/Flutter/Supabase; el Bloc no conoce Supabase; las pantallas no usan repositorios. |
| [test/unit/order_usecases_test.dart](test/unit/order_usecases_test.dart) | Casos de uso en demo: creación, transiciones, repartidores, reembolsos, entrega e idempotencia. |
| [test/unit/order_usecases_remote_test.dart](test/unit/order_usecases_remote_test.dart) | Con servidor simulado: el servidor manda, errores en español, sin efectos locales cuando rechaza, foto antes de molestar al servidor. |
| [test/unit/orders_bloc_test.dart](test/unit/orders_bloc_test.dart) | Resultado por acción, ids crecientes, doble toque, excepciones sin exponerse. |
| [test/unit/session_remote_test.dart](test/unit/session_remote_test.dart) | Verificación hidratada del servidor, direcciones con uuid real, fallos sin red, saldo de Gotas. |
| [test/unit/order_errors_test.dart](test/unit/order_errors_test.dart) | Los 34 códigos tienen mensaje en español y ninguno muestra el código crudo. |
| [test/fakes/fake_order_repository.dart](test/fakes/fake_order_repository.dart) | Servidor falso configurable para las pruebas. |
| [test/integration/full_flow_test.dart](test/integration/full_flow_test.dart) | Flujo completo comprador → restaurante → repartidor por la UI real. |

**Resultados:** `flutter analyze` sin avisos · `flutter test` **166/166** · SQL **87/87**, aplicado dos veces sin errores.

---

## 6. Lo que NO está hecho (y por qué)

| Pendiente | Motivo |
|---|---|
| Aplicar `0012` en tu Supabase | No tengo credenciales de administración (sección 1). |
| Probar los 3 roles contra Supabase real | Depende del punto anterior; los pasos están en [HANDOFF.md](HANDOFF.md) §7. |
| Cupones con pedidos reales | Los cupones salen de canjear Gotas (HU de recompensas) y hoy son locales. Con servidor se avisa "quita el cupón". El flujo funciona sin cupón. |
| Avisos entre dispositivos | Las notificaciones siguen en memoria (HU de datos personales). El **estado** del pedido sí llega en vivo por Realtime y sondeo cada 30 s. |
| Ver la foto de evidencia | Necesita URL firmada; hoy solo se sube y se verifica. |
| Horario del restaurante y repartidores cercanos reales en el servidor | Siguen validándose solo en la app (backlog de [HANDOFF.md](HANDOFF.md)). |
| Migrar sesión, catálogo, carrito y notificaciones a Bloc | Acordado: solo el ciclo de pedidos en esta etapa. |
