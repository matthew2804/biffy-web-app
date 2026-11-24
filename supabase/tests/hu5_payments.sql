-- ============================================================================
-- HU-5 · Prueba de pagos (Wompi + efectivo) en SQL
-- ============================================================================
-- Uso: Supabase Dashboard -> SQL Editor -> pegar todo -> Run.
--
-- Requisitos: migraciones aplicadas hasta 0026 y las 3 cuentas demo
--   diego.demo@icesi.edu.co · andres.repartidor@demo.biffy.co · qbano@demo.biffy.co
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja
-- pedidos, Gotas ni pagos de prueba en la base. Cada comprobación imprime
-- `PASS · ...`; la primera que falle aborta con `FALLO · ...`.
-- ============================================================================

begin;

-- ---------------------------------------------------------------- Utilidades

create or replace function pg_temp.expect(p_name text, p_ok boolean)
returns void language plpgsql as $$
begin
  if p_ok is not true then
    raise exception 'FALLO · %', p_name;
  end if;
  raise notice 'PASS · %', p_name;
end $$;

-- Cambia la sesión a un usuario como lo hace PostgREST con su JWT.
create or replace function pg_temp.as_user(p_key text)
returns void language plpgsql as $$
begin
  reset role;
  perform set_config(
    'request.jwt.claims',
    json_build_object(
      'sub', current_setting('t.' || p_key), 'role', 'authenticated'
    )::text,
    true
  );
  perform set_config('request.jwt.claim.sub', current_setting('t.' || p_key), true);
  set local role authenticated;
end $$;

-- Vuelve al rol administrador (service_role / postgres).
create or replace function pg_temp.admin()
returns void language plpgsql as $$
begin
  reset role;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.jwt.claim.sub', '', true);
end $$;

-- ------------------------------------------------------------------- Fixture

do $$
declare
  v_branch public.branches;
  v_dish public.dishes;
  v_coupon uuid;
begin
  perform set_config('biffy.internal', '1', true);

  perform set_config(
    't.diego',
    (select id::text from public.profiles where email = 'diego.demo@icesi.edu.co'),
    false
  );
  perform set_config(
    't.andres',
    (select id::text from public.profiles where email = 'andres.repartidor@demo.biffy.co'),
    false
  );
  perform set_config(
    't.qbano',
    (select id::text from public.profiles where email = 'qbano@demo.biffy.co'),
    false
  );
  if current_setting('t.diego', true) is null
     or current_setting('t.andres', true) is null
     or current_setting('t.qbano', true) is null then
    raise exception 'FALLO · faltan las cuentas demo';
  end if;

  -- Sede de Qbano apta para el pedido.
  select b.* into v_branch
    from public.branches b
    join public.businesses bu on bu.id = b.business_id
   where bu.owner_id = current_setting('t.qbano')::uuid
     and b.deleted_at is null
   order by b.created_at
   limit 1;
  if not found then
    raise exception 'FALLO · Qbano no tiene sede';
  end if;
  update public.branches
     set paused = false,
         couriers_nearby = 2,
         radius_km = 3,
         campus_id = 'icesi',
         student_discount = 0.10,
         campus_delivery_only = false,
         lat = 3.3410,
         lng = -76.5300
   where id = v_branch.id;
  perform set_config('t.branch', v_branch.id::text, false);

  -- Plato de prueba: 10.000 + 2.000 (tamaño) + 1.500 (extra) = 13.500.
  insert into public.dishes (branch_id, name, price, category_id, prep_min)
  values (v_branch.id, 'TEST pago', 10000, 'sandwich', 10)
  returning * into v_dish;
  insert into public.dish_options (dish_id, kind, label, price_delta)
  values (v_dish.id, 'size', 'Grande', 2000);
  insert into public.dish_options (dish_id, kind, label, price_delta)
  values (v_dish.id, 'extra', 'Queso', 1500);
  perform set_config('t.dish', v_dish.id::text, false);
  perform set_config(
    't.opt_size',
    (select id::text from public.dish_options
      where dish_id = v_dish.id and kind = 'size'),
    false
  );
  perform set_config(
    't.opt_extra',
    (select id::text from public.dish_options
      where dish_id = v_dish.id and kind = 'extra'),
    false
  );

  -- Diego verificado y con dirección en el campus.
  update public.profiles
     set verified = true,
         university_id = 'icesi',
         university_email = 'diego@icesi.edu.co',
         university_status = 'active',
         university_verified_at = now(),
         university_expires_at = now() + interval '30 days'
   where id = current_setting('t.diego')::uuid;
  update public.addresses set is_default = false
   where user_id = current_setting('t.diego')::uuid;
  insert into public.addresses (user_id, label, line, point_id, is_default)
  values (
    current_setting('t.diego')::uuid, 'TEST pago', 'Plazoleta',
    'icesi-plazoleta', true
  );
  perform set_config(
    't.addr',
    (select id::text from public.addresses
      where user_id = current_setting('t.diego')::uuid and label = 'TEST pago'),
    false
  );

  -- Cupón de $2.000 para probar la devolución.
  insert into public.coupons (code, title, kind, amount)
  values ('TESTPAY2000', 'Cupón pago', 'fixed', 2000)
  returning id into v_coupon;
  insert into public.user_coupons (user_id, coupon_id)
  values (current_setting('t.diego')::uuid, v_coupon);
  perform set_config('t.coupon', v_coupon::text, false);

  perform set_config('biffy.internal', '0', true);
end $$;

-- Payload base: 13.500 de subtotal + 1.500 de envío - 1.350 de campus = 13.650.
create or replace function pg_temp.payload(p_extra jsonb default '{}'::jsonb)
returns jsonb language sql as $$
  select jsonb_build_object(
    'branch_id', current_setting('t.branch'),
    'address_id', current_setting('t.addr'),
    'payment', 'cash',
    'cash_tendered', 20000,
    'lines', jsonb_build_array(jsonb_build_object(
      'dish_id', current_setting('t.dish'),
      'qty', 1,
      'selection', jsonb_build_object(
        'sizeId', current_setting('t.opt_size'),
        'extraIds', jsonb_build_array(current_setting('t.opt_extra'))
      )
    ))
  ) || p_extra
$$;

-- ==================================================== 1 · Efectivo con billete
do $$
declare
  r jsonb;
  v_order uuid;
  v_total int;
begin
  perform pg_temp.as_user('diego');

  r := public.place_order(pg_temp.payload());
  perform pg_temp.expect('efectivo: pedido creado', r ->> 'result' = 'ok');
  v_order := (r #>> '{order,id}')::uuid;
  v_total := (r #>> '{order,total}')::int;
  perform pg_temp.expect('efectivo: total 13.650', v_total = 13650);
  perform pg_temp.expect(
    'efectivo: pago aprobado sin pasarela',
    r #>> '{order,payment_status}' = 'approved'
  );
  perform pg_temp.expect(
    'efectivo: guarda el billete',
    (r #>> '{order,cash_tendered}')::int = 20000
  );
  perform pg_temp.expect(
    'efectivo: calcula las vueltas',
    (r #>> '{order,cash_change}')::int = 20000 - v_total
  );
  perform set_config('t.o_cash', v_order::text, false);

  -- El restaurante lo ve y lo acepta de inmediato.
  perform pg_temp.as_user('qbano');
  perform pg_temp.expect(
    'efectivo: el restaurante ve el pedido',
    exists (select 1 from public.orders where id = v_order)
  );
  perform pg_temp.expect(
    'efectivo: restaurant_accept funciona',
    public.restaurant_accept(v_order) ->> 'result' = 'ok'
  );

  perform pg_temp.admin();
  perform pg_temp.expect(
    'efectivo: queda auditoría en payments',
    exists (
      select 1 from public.payments
       where order_id = v_order and method = 'cash' and status = 'approved'
    )
  );

  -- Compatibilidad: sin billete explícito se asume pago exacto.
  perform pg_temp.as_user('diego');
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'cash_tendered', null
  )));
  perform pg_temp.expect(
    'efectivo: sin billete asume pago exacto',
    r ->> 'result' = 'ok'
      and (r #>> '{order,cash_tendered}')::int = (r #>> '{order,total}')::int
      and (r #>> '{order,cash_change}')::int = 0
  );
  perform pg_temp.admin();
end $$;

-- ============================================= 2 · Efectivo con billete corto
do $$
declare
  r jsonb;
begin
  perform pg_temp.as_user('diego');
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'cash_tendered', 1000
  )));
  perform pg_temp.expect(
    'efectivo: billete menor al total → invalid_cash',
    r ->> 'result' = 'invalid_cash'
  );
  perform pg_temp.admin();
end $$;

-- ==================================== 3 · Online: pendiente, gating y aprobado
do $$
declare
  r jsonb;
  v_order uuid;
  v_pay jsonb;
  v_pid uuid;
begin
  perform pg_temp.as_user('diego');
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'payment', 'nequi',
    'cash_tendered', null
  )));
  perform pg_temp.expect('online: pedido creado', r ->> 'result' = 'ok');
  v_order := (r #>> '{order,id}')::uuid;
  perform pg_temp.expect(
    'online: nace pendiente de pago',
    r #>> '{order,payment_status}' = 'pending'
  );
  perform set_config('t.o_online', v_order::text, false);

  -- El restaurante no lo ve ni lo puede aceptar.
  perform pg_temp.as_user('qbano');
  perform pg_temp.expect(
    'online: el restaurante NO ve el pedido',
    not exists (select 1 from public.orders where id = v_order)
  );
  perform pg_temp.expect(
    'online: restaurant_accept → payment_pending',
    public.restaurant_accept(v_order) ->> 'result' = 'payment_pending'
  );
  perform pg_temp.admin();

  -- El servidor crea el intento por el monto del pedido.
  v_pay := public.payment_begin(
    v_order, current_setting('t.diego')::uuid, 'nequi', 'key-online-1'
  );
  perform pg_temp.expect('online: payment_begin ok', v_pay ->> 'result' = 'ok');
  v_pid := (v_pay ->> 'payment_id')::uuid;
  perform pg_temp.expect(
    'online: monto tomado de orders.total',
    (v_pay ->> 'amount')::int =
      (select total from public.orders where id = v_order)
  );
  perform set_config('t.pay1', v_pid::text, false);

  -- Reutiliza el intento: no cobra dos veces.
  perform pg_temp.expect(
    'online: payment_begin reutiliza el intento',
    public.payment_begin(
      v_order, current_setting('t.diego')::uuid, 'nequi', 'key-online-2'
    ) ->> 'payment_id' = v_pid::text
  );

  -- Wompi confirma el pago.
  r := public.payment_apply(v_pid, 'approved', 'TX-ONLINE-1', 'accredited');
  perform pg_temp.expect('online: payment_apply approved', r ->> 'result' = 'ok');
  perform pg_temp.expect(
    'online: el pedido queda aprobado',
    (select payment_status::text from public.orders where id = v_order) = 'approved'
  );
  perform pg_temp.expect(
    'online: el webhook repetido es idempotente',
    public.payment_apply(v_pid, 'approved', 'TX-ONLINE-1', 'accredited')
      ->> 'result' = 'duplicate'
  );

  -- Ahora sí el restaurante lo ve y lo acepta.
  perform pg_temp.as_user('qbano');
  perform pg_temp.expect(
    'online: el restaurante lo ve tras aprobar',
    exists (select 1 from public.orders where id = v_order)
  );
  perform pg_temp.expect(
    'online: restaurant_accept ok tras aprobar',
    public.restaurant_accept(v_order) ->> 'result' = 'ok'
  );
  perform pg_temp.admin();
end $$;

-- ========================================= 4 · Rechazo y reintento del pago
do $$
declare
  r jsonb;
  v_order uuid;
  v_pay jsonb;
  v_pid uuid;
begin
  perform pg_temp.as_user('diego');
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'payment', 'card',
    'cash_tendered', null
  )));
  v_order := (r #>> '{order,id}')::uuid;
  perform pg_temp.admin();

  v_pay := public.payment_begin(
    v_order, current_setting('t.diego')::uuid, 'card', 'key-card-1'
  );
  v_pid := (v_pay ->> 'payment_id')::uuid;
  r := public.payment_apply(
    v_pid, 'rejected', 'TX-CARD-1', 'cc_rejected_insufficient_amount'
  );
  perform pg_temp.expect('rechazo: payment_apply ok', r ->> 'result' = 'ok');
  perform pg_temp.expect(
    'rechazo: el pedido sigue pendiente (no se cancela)',
    (select status::text from public.orders where id = v_order) = 'pending'
  );
  perform pg_temp.expect(
    'rechazo: payment_status = rejected',
    (select payment_status::text from public.orders where id = v_order) = 'rejected'
  );

  perform pg_temp.as_user('qbano');
  perform pg_temp.expect(
    'rechazo: el restaurante sigue sin verlo',
    not exists (select 1 from public.orders where id = v_order)
  );
  perform pg_temp.admin();

  -- Reintento: nuevo intento sobre el mismo pedido.
  v_pay := public.payment_begin(
    v_order, current_setting('t.diego')::uuid, 'card', 'key-card-2'
  );
  perform pg_temp.expect(
    'reintento: crea el intento 2',
    (v_pay ->> 'attempt')::int = 2
  );
  v_pid := (v_pay ->> 'payment_id')::uuid;
  r := public.payment_apply(v_pid, 'approved', 'TX-CARD-2', 'accredited');
  perform pg_temp.expect('reintento: aprobado', r ->> 'result' = 'ok');
  perform pg_temp.expect(
    'reintento: el pedido queda aprobado',
    (select payment_status::text from public.orders where id = v_order) = 'approved'
  );
end $$;

-- ============================== 5 · Expiración: cancela y devuelve todo
do $$
declare
  r jsonb;
  v_order uuid;
  v_gotas int;
  v_coupon uuid;
begin
  perform pg_temp.as_user('diego');
  v_gotas := (select gotas from public.profiles
               where id = current_setting('t.diego')::uuid);
  v_coupon := current_setting('t.coupon')::uuid;

  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'payment', 'pse',
    'cash_tendered', null,
    'gotas_used', 10,
    'coupon_id', v_coupon
  )));
  perform pg_temp.expect('expira: pedido creado', r ->> 'result' = 'ok');
  v_order := (r #>> '{order,id}')::uuid;
  perform pg_temp.expect(
    'expira: descuenta las Gotas',
    (select gotas from public.profiles
      where id = current_setting('t.diego')::uuid) = v_gotas - 10
  );
  perform pg_temp.as_user('qbano');
  perform pg_temp.expect(
    'expira: el restaurante no lo ve antes de pagar',
    not exists (select 1 from public.orders where id = v_order)
  );
  perform pg_temp.admin();

  perform public.payment_begin(
    v_order, current_setting('t.diego')::uuid, 'pse', 'key-pse-1'
  );
  -- Simula que pasaron los 30 minutos.
  update public.orders
     set payment_expires_at = now() - interval '1 minute'
   where id = v_order;

  perform pg_temp.expect(
    'expira: el cron cancela al menos 1',
    public.expire_pending_payments() >= 1
  );
  perform pg_temp.expect(
    'expira: pedido cancelado',
    (select status::text from public.orders where id = v_order) = 'cancelled'
  );
  perform pg_temp.expect(
    'expira: payment_status = expired',
    (select payment_status::text from public.orders where id = v_order) = 'expired'
  );
  perform pg_temp.expect(
    'expira: devuelve las Gotas',
    (select gotas from public.profiles
      where id = current_setting('t.diego')::uuid) = v_gotas
  );
  perform pg_temp.expect(
    'expira: devuelve el cupón',
    (select used_at from public.user_coupons
      where user_id = current_setting('t.diego')::uuid
        and coupon_id = v_coupon) is null
  );
  perform pg_temp.expect(
    'expira: deja auditoría del intento',
    exists (
      select 1 from public.payments
       where order_id = v_order and status = 'expired'
    )
  );
end $$;

-- ========================================= 6 · RLS de payments por rol
do $$
begin
  perform pg_temp.as_user('diego');
  perform pg_temp.expect(
    'RLS: el comprador ve sus pagos',
    (select count(*) from public.payments) > 0
  );

  perform pg_temp.as_user('qbano');
  perform pg_temp.expect(
    'RLS: el restaurante no ve intentos pendientes',
    (select count(*) from public.payments where status = 'pending') = 0
  );
  perform pg_temp.expect(
    'RLS: el restaurante ve los aprobados de su sede',
    (select count(*) from public.payments where status = 'approved') > 0
  );

  perform pg_temp.as_user('andres');
  perform pg_temp.expect(
    'RLS: el repartidor no ve pagos',
    (select count(*) from public.payments) = 0
  );
  perform pg_temp.admin();
end $$;

-- ================================= 7 · Idempotencia del webhook (event_id)
do $$
declare
  v_pid uuid := current_setting('t.pay1')::uuid;
begin
  insert into public.payment_events (payment_id, event_id, signature_valid, result)
  values (v_pid, 'evt-1', true, 'ok');

  begin
    insert into public.payment_events (payment_id, event_id, signature_valid, result)
    values (v_pid, 'evt-1', true, 'ok');
    perform pg_temp.expect('webhook: evento repetido se rechaza', false);
  exception when unique_violation then
    perform pg_temp.expect('webhook: evento repetido se rechaza', true);
  end;
end $$;

-- ============================== 8 · Consulta del pago según el usuario
do $$
begin
  perform pg_temp.as_user('diego');
  perform pg_temp.expect(
    'consulta: el dueño ve su pago',
    public.payment_for_order(current_setting('t.o_online')::uuid)
      ->> 'result' = 'ok'
  );

  perform pg_temp.as_user('andres');
  perform pg_temp.expect(
    'consulta: un tercero no ve el pago',
    public.payment_for_order(current_setting('t.o_online')::uuid)
      ->> 'result' = 'forbidden'
  );
  perform pg_temp.admin();
end $$;

rollback;
