# Arquitectura de Biffy

Biffy es una app Flutter para tres roles (comprador, restaurante y
repartidor) sobre un backend Supabase. El código sigue **Clean Architecture**:
cada capa solo conoce a la de adentro. El estado de las pantallas vive en
**Bloc/Cubit** y todas las piezas se conectan con **GetIt**.

> Los diagramas son Mermaid: GitHub y VS Code (con la extensión de Mermaid)
> los dibujan solos.

---

## 1. Capas y dirección de las dependencias

```mermaid
flowchart TB
  subgraph P["Presentación · lib/features/**"]
    W["Pantallas (widgets)"]
    B["Blocs y Cubits"]
  end
  subgraph D["Dominio · lib/domain/** (Dart puro)"]
    UC["Casos de uso"]
    E["Entidades y reglas puras<br/>(pricing, catalog_rules, order_rules…)"]
    I["Interfaces de repositorio<br/>y puertos"]
  end
  subgraph DA["Datos · lib/data/repositories/**"]
    MEM["InMemory… (demo y pruebas)"]
    SB["Supabase… (backend real)"]
  end
  subgraph AD["Adaptadores · lib/shared/adapters/**"]
    A["Implementan los puertos"]
  end
  DI["GetIt · lib/app/di/<br/>(única raíz de composición)"]

  W -- "eventos / lee estado" --> B
  B -- "llama" --> UC
  UC --> E
  UC -- "depende de" --> I
  MEM -. "implementa" .-> I
  SB -. "implementa" .-> I
  A -. "implementa" .-> I
  DI -- "registra y resuelve" --> B
  DI -- "registra y resuelve" --> UC
  DI -- "elige demo o Supabase" --> DA
```

Las reglas que **no se negocian** (las verifica `test/architecture_test.dart`):

| Regla | Por qué |
|---|---|
| `lib/domain` no importa Flutter, Supabase, GetIt ni otras capas | Las reglas de negocio se prueban sin app ni red. |
| Solo `lib/app/di/` conoce las implementaciones concretas | Cambiar demo ↔ Supabase no toca pantallas. |
| Solo la capa de datos y el módulo de datos importan Supabase | Ningún widget llama a la base directamente. |
| La única decisión de entorno (`AppConfig.hasSupabase`) está en el módulo de datos | Un solo interruptor para toda la app. |
| Sin `provider` ni `AppServices` | Todo sale de GetIt. |

---

## 2. GetIt: qué se registra y cómo

`configureDependencies()` (`lib/app/di/injection.dart`) registra cuatro
módulos en orden. Nada se crea hasta que alguien lo pide.

```mermaid
flowchart LR
  C["core_module<br/>Clock"] --> DA["data_module<br/>repositorios"]
  DA --> DO["domain_module<br/>casos de uso + puertos"]
  DO --> PR["presentation_module<br/>Blocs, Cubits y controladores"]

  DA --> Q{"AppConfig.hasSupabase"}
  Q -- "sí" --> S["Supabase… (SingletonAsync / LazySingleton)"]
  Q -- "no" --> M["InMemory… (LazySingleton)"]
```

| Módulo | Qué registra | Ciclo de vida |
|---|---|---|
| `core_module` | `Clock` | `LazySingleton` |
| `data_module` | `AuthRepository`, `CatalogRepository`, `OrderRepository`, `PaymentRepository`, `ProfileRepository`, `NotificationRepository`, `ReviewRepository`, `RewardsRepository`, `MerchantBoxesRepository` (tipados por la interfaz) | `LazySingleton` (los que hidratan caché con Supabase: `SingletonAsync`) |
| `domain_module` | Casos de uso: `OrderUseCases`, `RateOrder`, `GetDeliveryEvidence`, `GetCourierEarnings`, `StartPayment`, `CheckPaymentStatus`, `RetryPayment`, `LoadRewards`, `RedeemReward`, cajas del restaurante. Puertos: `OrderCatalogPort`, `OrderBuyerPort`, `OrderWalletPort`, `OrderNotifier`, `BranchRatingPort`, `ReviewNotifier` | Casos de uso `Factory`; puertos `LazySingleton` |
| `presentation_module` | `OrdersBloc` y `CartCubit` (globales); `PaymentBloc`, `RateOrderCubit`, `DeliveryEvidenceCubit`, `EarningsCubit` (con parámetro); `LoginCubit`, `RegisterCubit`, `UniversityVerificationCubit`, `CheckoutCubit`, `RewardsCubit`, `NotificationsCubit`, `MerchantBoxesCubit` | Globales `LazySingleton`; de pantalla `Factory` / `FactoryParam` |

Una pantalla pide su Cubit así (ejemplo real: foto de evidencia):

```dart
BlocProvider(
  create: (_) => getIt<DeliveryEvidenceCubit>(param1: order.id),
  child: _EvidenceBody(order: order),
)
```

Las pruebas no tienen constructores especiales: hacen `getIt.reset()`,
registran dobles (`FakeOrderRepository`, etc.) y piden las piezas igual que la
app (`test/helpers.dart`).

> **Pendiente de HU-2:** `SessionController`, `CatalogController` y
> `NotificationCenter` siguen siendo `ChangeNotifier`, registrados en GetIt.
> Se están migrando a `AuthBloc`, `CatalogBloc` y `NotificationsCubit`.

---

## 3. Un flujo completo: el comprador confirma su pedido

```mermaid
sequenceDiagram
  actor U as Comprador
  participant S as CheckoutScreen
  participant C as CheckoutCubit
  participant OB as OrdersBloc
  participant UC as PlaceOrder (caso de uso)
  participant R as SupabaseOrderRepository
  participant DB as Supabase (place_order + triggers)
  participant RT as Realtime
  participant M as App del restaurante

  U->>S: toca «Confirmar»
  S->>C: submit()
  C->>OB: request(OrderPlaced)
  OB->>UC: placeOrder(draft, clientKey)
  UC->>R: place(PlaceOrderRequest)
  R->>DB: rpc place_order
  Note over DB: El servidor recalcula precios, cupón y Gotas,<br/>valida horario, repartidores y porciones (0027)<br/>y deja un order_event
  DB-->>R: {result: ok, order}
  R-->>OB: OrderResult(ok) → OrdersState.outcome
  OB-->>S: BlocListener navega al seguimiento
  DB->>RT: INSERT en notifications (trigger 0022)
  RT-->>M: «Nuevo pedido BF-…» en vivo
```

Si el servidor rechaza, el `result` (por ejemplo `branch_closed` o
`no_portions`) se traduce a español en `lib/domain/order_errors.dart` y la
pantalla lo muestra. Nunca se ve un código crudo.

---

## 4. Ciclo del pedido y quién lo mueve

```mermaid
stateDiagram-v2
  [*] --> pending: comprador · place_order<br/>(online: solo con pago aprobado)
  pending --> preparing: restaurante · restaurant_accept
  pending --> cancelled: comprador · buyer_cancel<br/>restaurante · restaurant_reject<br/>pago rechazado o vencido
  preparing --> ready: restaurante · restaurant_ready
  ready --> on_the_way: repartidor · courier_accept + courier_pickup
  on_the_way --> delivered: repartidor · courier_deliver<br/>(código del cliente + foto en Storage)
  delivered --> [*]: comprador califica · rate_order
  cancelled --> [*]: se devuelven Gotas, cupón y porciones
```

Con Supabase **el servidor decide**: la app llama al RPC y el estado nuevo
llega en la recarga o por Realtime. En la demo, el repositorio en memoria aplica
las mismas transiciones (`kAllowedTransitions` en `lib/domain/order_rules.dart`).

---

## 5. Backend (Supabase)

```mermaid
flowchart LR
  APP["App Flutter<br/>(llave publicable)"] -- "RPC / select (RLS)" --> PG[("Postgres + PostGIS")]
  APP -- "fotos" --> ST["Storage<br/>dish-images (público)<br/>delivery-evidence (privado, URL firmada)"]
  PG -- "cambios" --> RT["Realtime<br/>orders, order_events,<br/>branches, dishes, notifications"]
  RT -- "en vivo" --> APP
  APP -- "iniciar pago" --> EF["Edge Functions<br/>create-payment, wompi-webhook,<br/>expire-payments, refund-payment"]
  EF -- "llave privada" --> WO["Wompi (sandbox)"]
  WO -- "webhook firmado" --> EF
  EF --> PG
  CRON["pg_cron / GitHub Actions"] --> PG
```

| Pieza | Dónde | Qué garantiza |
|---|---|---|
| RLS | `0004`, `0019`, `0022`, `0026` | Cada usuario ve solo lo suyo; los pedidos solo cambian por RPC. |
| `place_order` | `0019` → `0025` → `0026` | Precios, descuentos, cupón, Gotas e idempotencia (`client_key`) en el servidor. |
| Reglas del servidor | `0027_server_guards.sql` | Horario de la sede, repartidores conectados reales y `sold_today` por día (triggers). |
| Avisos | `0022_order_notifications.sql` | La base crea una notificación por destinatario en cada transición; Realtime la entrega. |
| Pagos | `0026_payments.sql` + Edge Functions | El pedido solo llega al restaurante con el pago aprobado; webhook firmado e idempotente. |
| Verificación | `0099_verify.sql` | Falla con un mensaje claro si falta algo; si no, imprime `Biffy OK`. |

---

## 6. Dónde mirar en el código (para la sustentación)

| Tema | Archivo |
|---|---|
| Composición con GetIt | `lib/app/di/injection.dart`, `lib/app/di/modules/*.dart` |
| Bloc global de pedidos | `lib/features/orders/bloc/orders_bloc.dart` |
| Caso de uso de ejemplo | `lib/domain/usecases/orders/place_order.dart` |
| Interfaz de repositorio | `lib/domain/repositories/order_repository.dart` |
| Implementación real | `lib/data/repositories/supabase_order_repository.dart` |
| Implementación demo | `lib/data/repositories/in_memory_order_repository.dart` |
| Regla pura con pruebas | `lib/domain/catalog_rules.dart` ↔ `test/unit/catalog_rules_test.dart` |
| Cubit con `bloc_test` | `lib/features/buyer/tracking/delivery_evidence_cubit.dart` ↔ `test/unit/delivery_evidence_cubit_test.dart` |
| Reglas de arquitectura | `test/architecture_test.dart` |
| Reglas del servidor | `supabase/migrations/0027_server_guards.sql` ↔ `supabase/tests/hu4_reglas_servidor.sql` |
