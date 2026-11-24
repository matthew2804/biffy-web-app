# Manual de prueba · Biffy (tres roles)

Recorrido paso a paso para probar la app **de principio a fin con datos
reales** (Supabase). Lo puede seguir cualquier persona, sin saber de código.
Cada paso dice qué hacer y **qué debería pasar**.

> Tiempo estimado: 20 a 25 minutos. Se necesitan **tres sesiones abiertas a la
> vez** (una por rol): tres celulares, o un celular y dos pestañas del
> navegador, o tres ventanas en modo incógnito.

---

## 0. Antes de empezar

### Cómo abrir la app con datos reales

| Opción | Cómo |
|---|---|
| Android | Instala el APK que deja el CI (pestaña **Actions** → última ejecución → artefacto `biffy-android`). Si es para Supabase, compílalo con `flutter build apk --release --dart-define-from-file=env.json`. |
| Navegador | `flutter run -d chrome --dart-define-from-file=env.json` |
| Emulador | `flutter run --dart-define-from-file=env.json` |

`env.json` se copia de `env.example.json`. **Sin ese archivo la app abre en
modo demo** (datos de memoria, sin red): sirve para probar sin internet, pero
no es la prueba real.

### Cuentas (contraseña de todas: `biffy123`)

| Rol | Correo |
|---|---|
| Comprador | `diego.demo@icesi.edu.co` |
| Restaurante | `qbano@demo.biffy.co` |
| Repartidor | `andres.repartidor@demo.biffy.co` |

### Datos de pago de prueba (Wompi sandbox, no mueve dinero)

| Escenario | Dato |
|---|---|
| Tarjeta aprobada | `4917 4800 0000 0057`, cualquier fecha futura y cualquier CVV |
| Tarjeta rechazada | `4917 4800 0000 0008` |
| Nequi aprobado | `3991111111` |

Más datos en [`GUIA_SANDBOX_WOMPI.md`](../GUIA_SANDBOX_WOMPI.md).

### Si una prueba es fuera del horario de los restaurantes

Las sedes atienden de **7:00 a 22:00**. Fuera de ese horario el servidor no
deja pedir "Ahora". En la cuenta del comprador, **Perfil → Configuración →
Horario de demostración (12:00)** lo simula, también en el servidor.

---

## 1. Registro y login

| # | Haz esto | Debe pasar |
|---|---|---|
| 1.1 | En la pantalla de entrada toca **Crear cuenta**, elige **Comprador** y llena nombre, correo y contraseña (usa un correo tuyo de prueba). | Entras a la app con tu nombre y **450 Gotas** de bienvenida. |
| 1.2 | **Perfil → Cerrar sesión**. Vuelve a entrar con el mismo correo. | Vuelves con el mismo nombre, las mismas Gotas y las mismas direcciones. |
| 1.3 | Intenta entrar con una contraseña equivocada. | Mensaje en español: credenciales inválidas. No se cae la app. |
| 1.4 | Cierra sesión y entra con las tres cuentas de la tabla, una en cada dispositivo. | Cada una abre en su panel: inicio del comprador, panel del negocio o inicio del repartidor. |

---

## 2. Repartidor: conectarse (hazlo primero)

Sin un repartidor conectado, el comprador **no ve restaurantes**: el servidor
cuenta los repartidores reales (`0027`).

| # | Haz esto | Debe pasar |
|---|---|---|
| 2.1 | Con **Andrés**, en el inicio, revisa el interruptor de disponibilidad. | Dice **CONECTADO** (se conecta solo al entrar). |
| 2.2 | Desconéctalo. Mira el inicio del comprador (Diego). | En segundos Diego ve **"🛵 No hay repartidores conectados ahora"**. |
| 2.3 | Vuelve a conectar a Andrés. | Los restaurantes reaparecen en el inicio de Diego, sin recargar. |

---

## 3. Comprador: catálogo, carrito y pago

| # | Haz esto | Debe pasar |
|---|---|---|
| 3.1 | Con **Diego**, en el inicio, entra a **Qbano · Icesi**. | Ves el menú con precios y fotos o emojis. |
| 3.2 | Agrega 2 productos (cambia tamaño o extras en uno). | El carrito suma bien y muestra el descuento de campus si aplica. |
| 3.3 | En el carrito elige **Ahora** y una dirección. Elige pago con **tarjeta**. Toca **Confirmar pedido**. | Abre la pantalla **Pago** con el botón **Abrir checkout de Wompi**. |
| 3.4 | Paga con la **tarjeta rechazada**. | Vuelves con un aviso rojo y el motivo en español. **El restaurante NO ve el pedido.** |
| 3.5 | Toca **Reintentar pago** y paga con la **tarjeta aprobada**. | El pago queda aprobado y pasa al seguimiento del pedido. No se crea un pedido duplicado. |
| 3.6 | Mira el seguimiento. | Estado **Pendiente** y el **Código de entrega** de 4 dígitos (anótalo). |

> **Efectivo:** repite con **Efectivo** y un billete de $50.000. El pedido
> llega de inmediato al restaurante con "Paga con $50.000 · Vueltas $…".

---

## 4. Restaurante: aceptar, preparar y marcar listo

| # | Haz esto | Debe pasar |
|---|---|---|
| 4.1 | Con **Qbano**, mira las notificaciones y **Pedidos**. | Llegó **"Nuevo pedido BF-…"** en vivo, sin recargar. |
| 4.2 | Toca **Aceptar**. | Diego ve "Preparando" en su seguimiento y recibe el aviso. |
| 4.3 | Toca **Marcar como listo**. | Diego ve "Listo"; a Andrés le aparece la oferta. |

### Menú y cajas

| # | Haz esto | Debe pasar |
|---|---|---|
| 4.4 | **Menú → Nuevo producto**: crea un plato con precio y foto. | Aparece en el menú y Diego lo ve en Qbano. |
| 4.5 | Marca un plato **Agotado**. | Diego no lo puede agregar. Vuelve a **Disponible**. |
| 4.6 | **Menú → Cajas con Gotas**: mete un plato en una caja. | El plato queda listado en la caja. |

---

## 5. Repartidor: oferta, recogida y entrega

| # | Haz esto | Debe pasar |
|---|---|---|
| 5.1 | Con **Andrés**, abre la oferta → **Aceptar oferta**. | Pasa a la pantalla de recogida. El pago online dice "ya pagado". |
| 5.2 | **Confirmar recogida**. | Diego ve "En camino". |
| 5.3 | En la entrega escribe un código **equivocado**. | "El código del cliente es incorrecto". El pedido sigue en camino. |
| 5.4 | Escribe el **código de Diego** (paso 3.6), toma una foto con **Cámara** o **Galería** y toca **Entregar BF-…**. | "¡Entregado! Ganas $…". Diego ve "Entregado". |
| 5.5 | Abre **Ganancias**. | La entrega aparece en las ganancias de hoy. |

---

## 6. Comprador: evidencia y calificación

| # | Haz esto | Debe pasar |
|---|---|---|
| 6.1 | Con **Diego**, abre el pedido entregado. | La tarjeta **Evidencia de entrega** muestra la foto que tomó Andrés. |
| 6.2 | En **Califica tu pedido**, pon 5 estrellas y un comentario → **Enviar calificación**. | La calificación queda guardada; Qbano recibe el aviso. |
| 6.3 | Revisa tus **Gotas**. | Subieron por el pedido entregado. |

---

## 7. Gotas, cajas y cupones

| # | Haz esto | Debe pasar |
|---|---|---|
| 7.1 | **Gotas** → canjea **Envío gratis** (5 Gotas). | Se descuentan 5 Gotas y aparece el cupón. |
| 7.2 | Arma otro pedido y en el carrito elige el cupón 🎟️. | El envío queda en $0 en el resumen. |
| 7.3 | Confirma y luego **cancela** el pedido. | Vuelven las Gotas usadas y el cupón queda disponible otra vez. |
| 7.4 | Abre una **caja** de Gotas. | Sale un premio. Si es un plato, muestra un código de 6 caracteres. |
| 7.5 | Con **Qbano** → **Cajas con Gotas**, valida ese código. | El premio queda canjeado y no se puede usar dos veces. |

---

## 8. Errores que deben verse bien

| # | Haz esto | Debe pasar |
|---|---|---|
| 8.1 | Apaga el wifi y abre **Mis pedidos** o el inicio. | Si no hay datos guardados: "No pudimos cargar…" con **Reintentar**. Nunca una pantalla en blanco. |
| 8.2 | Prende el wifi y toca **Reintentar**. | Carga normal. |
| 8.3 | Con el horario de demostración apagado y fuera de las 7:00–22:00, intenta pedir **Ahora**. | "El restaurante está cerrado a esta hora. Programa tu pedido…" |
| 8.4 | Toca dos veces seguidas **Confirmar pedido**. | Se crea un solo pedido. |

---

## 9. Comprobaciones en la base (opcional)

En el **SQL Editor** de Supabase:

```sql
select code, status, payment_status, total from orders order by created_at desc limit 5;
select status, created_at from order_events order by created_at desc limit 8;
select title, role, created_at from notifications order by created_at desc limit 6;
select reference, status, amount_in_cents from payments order by created_at desc limit 3;
```

---

## 10. Pruebas automáticas que respaldan este manual

| Qué | Comando |
|---|---|
| App completa en demo (260+ casos, incluye el flujo de los 3 roles) | `flutter test` |
| Reglas de la base (RLS, RPC, pagos, horario, porciones) | `tool/test_supabase_sql.sh` |
| Contra el Supabase real (perfiles, RLS, avisos en vivo, cupones) | `flutter test test/integration/hu4_servidor_test.dart --dart-define-from-file=env.json` |
