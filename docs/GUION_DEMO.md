# Guion de la demostración final (10 minutos)

Qué mostrar, en qué orden y qué decir. Está pensado para que cualquier
integrante lo presente.

## Preparación (antes de empezar, no cuenta en los 10 min)

- [ ] Tres sesiones abiertas con datos reales (`--dart-define-from-file=env.json`):
      Diego (comprador), Qbano (restaurante) y Andrés (repartidor), una al lado
      de la otra en pantalla.
- [ ] Andrés **conectado**. Si es fuera de las 7:00–22:00, Diego con
      **Horario de demostración** activo.
- [ ] VS Code abierto con estas pestañas, en este orden:
      1. `lib/app/di/injection.dart`
      2. `lib/app/di/modules/data_module.dart`
      3. `lib/features/orders/bloc/orders_bloc.dart`
      4. `lib/domain/usecases/orders/place_order.dart`
      5. `lib/domain/repositories/order_repository.dart`
      6. `test/architecture_test.dart`
      7. `supabase/migrations/0027_server_guards.sql`
- [ ] `docs/ARQUITECTURA.md` abierto en vista previa (diagramas).
- [ ] La pestaña **Actions** de GitHub con la última ejecución en verde.
- [ ] Datos de Wompi a mano: tarjeta aprobada `4917 4800 0000 0057` y
      rechazada `4917 4800 0000 0008`.

---

## Minuto 0–1 · Qué es Biffy

> "Biffy es una app de domicilios universitarios con tres roles: comprador,
> restaurante y repartidor. Todo lo que van a ver corre contra Supabase real:
> pagos en el sandbox de Wompi, avisos en vivo y reglas validadas en el
> servidor."

Muestra el diagrama de capas de `docs/ARQUITECTURA.md` (sección 1).

## Minuto 1–3 · Código: GetIt, Clean y Bloc

1. **`injection.dart`**: "Hay un solo punto de registro, por módulos: núcleo,
   datos, dominio y presentación."
2. **`data_module.dart`**: "Esta es la única decisión de entorno: con
   `hasSupabase` se registran los repositorios de Supabase; sin él, los de
   memoria. Siempre se registran por la interfaz del dominio."
3. **`orders_bloc.dart`**: "La pantalla solo despacha eventos. El Bloc llama a
   los casos de uso y publica el resultado."
4. **`place_order.dart`** y **`order_repository.dart`**: "El caso de uso
   depende de una interfaz. El dominio es Dart puro: no conoce Flutter, GetIt
   ni Supabase."
5. **`architecture_test.dart`**: "Estas reglas se prueban: si alguien importa
   Supabase desde un widget, el CI falla."

## Minuto 3–7 · Flujo completo en vivo

| Tiempo | Quién | Qué hacer | Qué decir |
|---|---|---|---|
| 3:00 | Diego | Entra a Qbano, agrega 2 platos, elige tarjeta → **Confirmar pedido** | "El servidor recalcula el total. Si la app manda otro, lo rechaza." |
| 3:40 | Diego | Paga con la **tarjeta rechazada** | "Rechazado, con el motivo en español. Qbano no ve el pedido: solo llega con el pago aprobado." |
| 4:10 | Diego | **Reintentar pago** con la tarjeta aprobada | "Mismo pedido, sin duplicar: clave de idempotencia." |
| 4:40 | Qbano | El aviso llega solo → **Aceptar** → **Marcar como listo** | "La base crea el aviso y Realtime lo entrega en el otro dispositivo." |
| 5:20 | Andrés | **Aceptar oferta** → **Confirmar recogida** | |
| 5:50 | Andrés | Código equivocado (falla), luego el código de Diego + foto → **Entregar** | "El código lo valida el servidor; el repartidor nunca lo ve." |
| 6:30 | Diego | Abre el pedido: **foto de evidencia** → califica con 5 estrellas | "La foto está en un bucket privado; se ve con una URL firmada de una hora." |

## Minuto 7–8 · Reglas del servidor

1. Desconecta a Andrés: en el inicio de Diego aparece **"No hay repartidores
   conectados ahora"**. Vuelve a conectarlo.
2. Abre `0027_server_guards.sql`: "El horario, los repartidores cercanos y las
   porciones vendidas hoy ahora los valida la base con triggers, así que no se
   pueden saltar desde la app."

## Minuto 8–9 · Calidad

- La pestaña **Actions** en verde: análisis, 269 tests de Flutter, 238
  casos SQL, integración contra Supabase y builds web y Android.
- Una prueba de `bloc_test` (`test/unit/delivery_evidence_cubit_test.dart`):
  caso exitoso, caso vacío y error con reintento.

## Minuto 9–10 · Cierre y preguntas

> "Los tres roles funcionan de punta a punta con datos reales, sin pantallas
> vacías: cada lista tiene carga, vacío y error con reintento. La
> documentación (arquitectura, despliegue y manual de prueba) está en `docs/`."

---

## Plan B (si algo falla en vivo)

| Problema | Qué hacer |
|---|---|
| Sin internet | Abre la app **sin** `env.json` (modo demo): el mismo flujo corre en memoria, y se explica que es la misma app con otro repositorio inyectado por GetIt. |
| Wompi no responde | Usa **Efectivo** con un billete de $50.000 y muestra la evidencia del pago aprobado `BF-2046` en `GUIA_SANDBOX_WOMPI.md`. |
| No llega un aviso en vivo | Toca **Reintentar** o recarga. Muestra que la prueba `hu4_servidor_test.dart` lo comprueba con tres sesiones reales. |
| Sede cerrada | Activa **Horario de demostración** en la cuenta de Diego. |
