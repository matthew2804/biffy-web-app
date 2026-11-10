-- ============================================================================
-- HU-3 · Prueba del ciclo completo del pedido (SQL)
-- ============================================================================
-- Uso: Supabase Dashboard -> SQL Editor -> pegar todo -> Run.
--
-- Requisitos: migraciones aplicadas hasta 0019 y las 3 cuentas demo
--   diego.demo@icesi.edu.co · andres.repartidor@demo.biffy.co · qbano@demo.biffy.co
--
-- Todo corre dentro de una transacción que termina en ROLLBACK: no deja
-- pedidos, Gotas ni usuarios de prueba en la base. Cada comprobación imprime
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
    json_build_object('sub', current_setting('t.' || p_key), 'role', 'authenticated')::text,
    true
  );
  perform set_config('request.jwt.claim.sub', current_setting('t.' || p_key), true);
  set local role authenticated;
end $$;

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
  v_biz uuid;
begin
  perform set_config('biffy.internal', '1', true);

  perform set_config('t.diego',  (select id::text from public.profiles where email = 'diego.demo@icesi.edu.co'), false);
  perform set_config('t.andres', (select id::text from public.profiles where email = 'andres.repartidor@demo.biffy.co'), false);
  perform set_config('t.qbano',  (select id::text from public.profiles where email = 'qbano@demo.biffy.co'), false);
  if current_setting('t.diego', true) is null or current_setting('t.andres', true) is null
     or current_setting('t.qbano', true) is null then
    raise exception 'FALLO · faltan las cuentas demo';
  end if;

  -- Usuarios extra para probar permisos ajenos y la carrera de repartidores.
  insert into auth.users (id, email, raw_user_meta_data) values
    (gen_random_uuid(), 'test.otro.comprador@test.local',   '{"role":"buyer"}'),
    (gen_random_uuid(), 'test.otro.repartidor@test.local',  '{"role":"courier","full_name":"Otro repartidor"}'),
    (gen_random_uuid(), 'test.otro.restaurante@test.local', '{"role":"restaurant"}');
  perform set_config('t.otro_comprador',  (select id::text from public.profiles where email = 'test.otro.comprador@test.local'), false);
  perform set_config('t.otro_repartidor', (select id::text from public.profiles where email = 'test.otro.repartidor@test.local'), false);
  perform set_config('t.otro_rest',       (select id::text from public.profiles where email = 'test.otro.restaurante@test.local'), false);

  insert into public.businesses (owner_id, brand)
  values (current_setting('t.otro_rest')::uuid, 'Otro negocio');

  -- Sede de Qbano: visible, dentro de Icesi, con repartidores y descuento.
  select b.* into v_branch
    from public.branches b
    join public.businesses bu on bu.id = b.business_id
   where bu.owner_id = current_setting('t.qbano')::uuid and b.deleted_at is null
   order by b.created_at limit 1;
  if not found then raise exception 'FALLO · Qbano no tiene sede'; end if;
  update public.branches
     set paused = false, couriers_nearby = 2, radius_km = 3,
         campus_id = 'icesi', student_discount = 0.10, campus_delivery_only = false,
         lat = 3.3410, lng = -76.5300
   where id = v_branch.id;
  perform set_config('t.branch', v_branch.id::text, false);

  -- Plato de prueba con opciones, propio de la transacción.
  insert into public.dishes (branch_id, name, price, category_id, prep_min)
  values (v_branch.id, 'TEST plato', 10000, 'sandwich', 10)
  returning * into v_dish;
  perform set_config('t.dish', v_dish.id::text, false);

  insert into public.dish_options (dish_id, kind, label, price_delta)
  values (v_dish.id, 'size', 'Grande', 2000);
  perform set_config('t.opt_size', (select id::text from public.dish_options where dish_id = v_dish.id and kind = 'size'), false);
  insert into public.dish_options (dish_id, kind, label, price_delta)
  values (v_dish.id, 'extra', 'Queso', 1500);
  perform set_config('t.opt_extra', (select id::text from public.dish_options where dish_id = v_dish.id and kind = 'extra'), false);

  -- Diego: verificado en Icesi, dirección en el campus y otra lejana.
  update public.profiles set verified = true, university_id = 'icesi'
   where id = current_setting('t.diego')::uuid;
  update public.addresses set is_default = false
   where user_id = current_setting('t.diego')::uuid;
  insert into public.addresses (user_id, label, line, point_id, is_default)
  values (current_setting('t.diego')::uuid, 'TEST campus', 'Plazoleta', 'icesi-plazoleta', true);
  perform set_config('t.addr', (select id::text from public.addresses where label = 'TEST campus'), false);
  insert into public.addresses (user_id, label, line, point_id)
  values (current_setting('t.diego')::uuid, 'TEST lejos', 'Bogotá', 'chapinero');
  perform set_config('t.addr_far', (select id::text from public.addresses where label = 'TEST lejos'), false);

  -- Repartidores: Andrés en moto/campus Icesi; el otro en bicicleta/general.
  update public.courier_profiles
     set vehicle = 'moto', zone = 'campus', university_id = 'icesi', online = true
   where user_id = current_setting('t.andres')::uuid;
  insert into public.courier_profiles (user_id, full_name, doc_number, vehicle, zone)
  values (current_setting('t.otro_repartidor')::uuid, 'Otro repartidor', '999', 'bicycle', 'general');

  -- Cupón de $2.000 asignado a Diego.
  insert into public.coupons (code, title, kind, amount)
  values ('TEST2000', 'Cupón de prueba', 'fixed', 2000);
  perform set_config('t.coupon', (select id::text from public.coupons where code = 'TEST2000'), false);
  insert into public.user_coupons (user_id, coupon_id)
  values (current_setting('t.diego')::uuid, current_setting('t.coupon')::uuid);

  perform set_config('biffy.internal', '0', true);
end $$;

-- Payload base: 1× plato grande + queso = 10.000 + 2.000 + 1.500 = 13.500.
create or replace function pg_temp.payload(p_extra jsonb default '{}'::jsonb)
returns jsonb language sql as $$
  select jsonb_build_object(
    'branch_id', current_setting('t.branch'),
    'address_id', current_setting('t.addr'),
    'payment', 'cash',
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

-- ============================================================ 1 · Precios
do $$
declare
  r jsonb;
  v_order public.orders;
begin
  perform pg_temp.as_user('diego');

  -- Subtotal 13.500; campus 10% = 1.350; envío campus 1.500 → total 13.650.
  r := public.place_order(pg_temp.payload());
  perform pg_temp.expect('place_order calcula sin que el cliente mande totales', r ->> 'result' = 'ok');
  perform pg_temp.expect('subtotal 13.500 desde dishes + opciones', (r #>> '{order,subtotal}')::int = 13500);
  perform pg_temp.expect('descuento de campus 1.350', (r #>> '{order,campus_discount}')::int = 1350);
  perform pg_temp.expect('envío dentro del campus 1.500', (r #>> '{order,delivery_fee}')::int = 1500);
  perform pg_temp.expect('total 13.650', (r #>> '{order,total}')::int = 13650);
  perform pg_temp.expect('el comprador recibe su código de entrega (4 dígitos)', (r #>> '{order,delivery_code}') ~ '^[0-9]{4}$');
  perform pg_temp.expect('el código de pedido sigue el formato BF-n', (r #>> '{order,code}') ~ '^BF-[0-9]+$');
  perform set_config('t.o_price', r #>> '{order,id}', false);

  -- unit_price manipulado: el servidor lo ignora.
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'lines', jsonb_build_array(jsonb_build_object(
      'dish_id', current_setting('t.dish'), 'qty', 1, 'unit_price', 1)))));
  perform pg_temp.expect('unit_price manipulado se ignora (cobra 10.000)',
    r ->> 'result' = 'ok' and (r #>> '{order,subtotal}')::int = 10000);

  -- Totales declarados que no coinciden: se rechaza y no se crea nada.
  r := public.place_order(pg_temp.payload(jsonb_build_object('subtotal', 1)));
  perform pg_temp.expect('subtotal manipulado → subtotal_mismatch', r ->> 'result' = 'subtotal_mismatch');
  r := public.place_order(pg_temp.payload(jsonb_build_object('subtotal', 13500, 'total', 1)));
  perform pg_temp.expect('total manipulado → total_mismatch', r ->> 'result' = 'total_mismatch');
  perform pg_temp.expect('total_mismatch informa el total esperado', (r ->> 'expected')::int = 13650);
  r := public.place_order(pg_temp.payload(jsonb_build_object('subtotal', 13500, 'total', 13650)));
  perform pg_temp.expect('totales correctos declarados → ok', r ->> 'result' = 'ok');

  -- Opción inventada, dirección ajena/lejana, pago inválido.
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'lines', jsonb_build_array(jsonb_build_object(
      'dish_id', current_setting('t.dish'), 'qty', 1,
      'selection', jsonb_build_object('sizeId', gen_random_uuid()))))));
  perform pg_temp.expect('opción inexistente → invalid_option', r ->> 'result' = 'invalid_option');
  r := public.place_order(pg_temp.payload(jsonb_build_object('address_id', current_setting('t.addr_far'))));
  perform pg_temp.expect('dirección fuera del radio → out_of_zone', r ->> 'result' = 'out_of_zone');
  r := public.place_order(pg_temp.payload(jsonb_build_object('payment', 'bitcoin')));
  perform pg_temp.expect('pago inválido → invalid_payment', r ->> 'result' = 'invalid_payment');
  r := public.place_order(pg_temp.payload(jsonb_build_object('lines', '[]'::jsonb)));
  perform pg_temp.expect('carrito vacío → empty_cart', r ->> 'result' = 'empty_cart');
  r := public.place_order(pg_temp.payload(jsonb_build_object('gotas_used', 99999)));
  perform pg_temp.expect('más Gotas que el saldo → insufficient_gotas', r ->> 'result' = 'insufficient_gotas');
  r := public.place_order(pg_temp.payload(jsonb_build_object('coupon_id', gen_random_uuid())));
  perform pg_temp.expect('cupón ajeno/inexistente → coupon_unavailable', r ->> 'result' = 'coupon_unavailable');
  r := public.place_order(pg_temp.payload(jsonb_build_object('branch_id', 'no-es-uuid')));
  perform pg_temp.expect('payload mal formado → invalid_payload (sin error crudo)', r ->> 'result' = 'invalid_payload');

  perform pg_temp.as_user('otro_comprador');
  r := public.place_order(pg_temp.payload());
  perform pg_temp.expect('dirección de otro usuario → address_not_found', r ->> 'result' = 'address_not_found');

  perform pg_temp.admin();
  perform pg_temp.expect('los pedidos rechazados no crearon filas',
    (select count(*) from public.orders where buyer_id = current_setting('t.diego')::uuid) = 3);
end $$;

-- ====================================================== 2 · Idempotencia
do $$
declare
  a jsonb; b jsonb;
begin
  perform pg_temp.as_user('diego');
  a := public.place_order(pg_temp.payload(jsonb_build_object('client_key', 'clave-1')));
  b := public.place_order(pg_temp.payload(jsonb_build_object('client_key', 'clave-1')));
  perform pg_temp.expect('misma client_key → mismo pedido',
    a #>> '{order,id}' = b #>> '{order,id}' and (b ->> 'duplicate')::boolean);
  perform pg_temp.expect('el reintento conserva el código de entrega',
    a #>> '{order,delivery_code}' = b #>> '{order,delivery_code}');
  perform pg_temp.admin();
  perform pg_temp.expect('solo se creó un pedido con esa clave',
    (select count(*) from public.orders where client_key = 'clave-1') = 1);
end $$;

-- ============================ 3 · Gotas + cupón y su reembolso al rechazar
do $$
declare
  r jsonb; v_id uuid;
  v_gotas0 int; v_gotas1 int;
begin
  perform pg_temp.admin();
  select gotas into v_gotas0 from public.profiles where id = current_setting('t.diego')::uuid;

  perform pg_temp.as_user('diego');
  -- 13.500 − 1.350 (campus) − 2.000 (cupón) = 10.150 → hasta 1.015 Gotas; usa 10.
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'coupon_id', current_setting('t.coupon'), 'gotas_used', 10)));
  perform pg_temp.expect('pedido con cupón y 10 Gotas → ok', r ->> 'result' = 'ok');
  perform pg_temp.expect('cupón aplicado (2.000)', (r #>> '{order,coupon_discount}')::int = 2000);
  perform pg_temp.expect('total = 10.150 − 100 + 1.500 = 11.550', (r #>> '{order,total}')::int = 11550);
  v_id := (r #>> '{order,id}')::uuid;

  perform pg_temp.admin();
  select gotas into v_gotas1 from public.profiles where id = current_setting('t.diego')::uuid;
  perform pg_temp.expect('las Gotas se descontaron', v_gotas1 = v_gotas0 - 10);
  perform pg_temp.expect('el cupón quedó usado',
    (select used_at is not null from public.user_coupons
      where user_id = current_setting('t.diego')::uuid and coupon_id = current_setting('t.coupon')::uuid));

  perform pg_temp.as_user('diego');
  r := public.place_order(pg_temp.payload(jsonb_build_object('coupon_id', current_setting('t.coupon'))));
  perform pg_temp.expect('cupón ya usado no se puede reusar', r ->> 'result' = 'coupon_unavailable');

  -- Restaurante ajeno no puede rechazarlo; el dueño sí.
  perform pg_temp.as_user('otro_rest');
  r := public.restaurant_reject(v_id, 'x');
  perform pg_temp.expect('restaurante ajeno → forbidden', r ->> 'result' = 'forbidden');
  perform pg_temp.as_user('qbano');
  r := public.restaurant_reject(v_id, 'Sin stock');
  perform pg_temp.expect('restaurante dueño rechaza → ok', r ->> 'result' = 'ok');

  perform pg_temp.admin();
  perform pg_temp.expect('reembolso de Gotas',
    (select gotas from public.profiles where id = current_setting('t.diego')::uuid) = v_gotas0);
  perform pg_temp.expect('reembolso del cupón',
    (select used_at is null from public.user_coupons
      where user_id = current_setting('t.diego')::uuid and coupon_id = current_setting('t.coupon')::uuid));
  perform pg_temp.expect('used_count del cupón vuelve a 0',
    (select used_count from public.coupons where id = current_setting('t.coupon')::uuid) = 0);
  perform pg_temp.expect('el rechazo guarda el motivo',
    (select reject_reason from public.orders where id = v_id) = 'Sin stock');

  -- buyer_cancel también reembolsa.
  perform pg_temp.as_user('diego');
  r := public.place_order(pg_temp.payload(jsonb_build_object(
    'coupon_id', current_setting('t.coupon'), 'gotas_used', 5)));
  v_id := (r #>> '{order,id}')::uuid;
  perform pg_temp.as_user('otro_comprador');
  perform pg_temp.expect('comprador ajeno no cancela → forbidden',
    public.buyer_cancel(v_id) ->> 'result' = 'forbidden');
  perform pg_temp.as_user('diego');
  perform pg_temp.expect('el comprador cancela su pedido pendiente',
    public.buyer_cancel(v_id) ->> 'result' = 'ok');
  perform pg_temp.expect('cancelar dos veces → invalid_state',
    public.buyer_cancel(v_id) ->> 'result' = 'invalid_state');
  perform pg_temp.admin();
  perform pg_temp.expect('buyer_cancel devolvió Gotas y cupón',
    (select gotas from public.profiles where id = current_setting('t.diego')::uuid) = v_gotas0
    and (select used_at is null from public.user_coupons
          where user_id = current_setting('t.diego')::uuid and coupon_id = current_setting('t.coupon')::uuid));
end $$;

-- ======================================== 4 · Ciclo completo de un pedido
do $$
declare
  r jsonb; v_id uuid; v_id2 uuid;
  v_code text; v_gotas0 int;
  v_events text;
begin
  perform pg_temp.admin();
  select gotas into v_gotas0 from public.profiles where id = current_setting('t.diego')::uuid;

  perform pg_temp.as_user('diego');
  r := public.place_order(pg_temp.payload());
  v_id := (r #>> '{order,id}')::uuid;
  v_code := r #>> '{order,delivery_code}';

  -- Transiciones fuera de orden.
  perform pg_temp.as_user('qbano');
  perform pg_temp.expect('listo antes de aceptar → invalid_state', public.restaurant_ready(v_id) ->> 'result' = 'invalid_state');
  perform pg_temp.as_user('andres');
  perform pg_temp.expect('repartidor no acepta un pedido pendiente → not_available', public.courier_accept(v_id) ->> 'result' = 'not_available');
  perform pg_temp.expect('repartidor no es restaurante → forbidden', public.restaurant_accept(v_id) ->> 'result' = 'forbidden');
  perform pg_temp.as_user('diego');
  perform pg_temp.expect('comprador no es restaurante → forbidden', public.restaurant_accept(v_id) ->> 'result' = 'forbidden');
  perform pg_temp.as_user('otro_rest');
  perform pg_temp.expect('restaurante ajeno no acepta → forbidden', public.restaurant_accept(v_id) ->> 'result' = 'forbidden');
  perform pg_temp.as_user('diego');
  perform pg_temp.expect('el comprador no es repartidor → forbidden', public.courier_accept(v_id) ->> 'result' = 'forbidden');

  perform pg_temp.as_user('qbano');
  perform pg_temp.expect('restaurante acepta', public.restaurant_accept(v_id) ->> 'result' = 'ok');
  perform pg_temp.expect('aceptar dos veces → invalid_state', public.restaurant_accept(v_id) ->> 'result' = 'invalid_state');
  perform pg_temp.as_user('diego');
  perform pg_temp.expect('cancelar tras aceptar → invalid_state', public.buyer_cancel(v_id) ->> 'result' = 'invalid_state');

  -- Aún en preparación: ningún repartidor lo ve.
  perform pg_temp.as_user('otro_repartidor');
  perform pg_temp.expect('en preparación no es oferta',
    (select count(*) from public.orders where id = v_id) = 0);

  perform pg_temp.as_user('qbano');
  perform pg_temp.expect('restaurante marca listo', public.restaurant_ready(v_id) ->> 'result' = 'ok');

  -- Oferta visible para los repartidores disponibles.
  perform pg_temp.as_user('otro_repartidor');
  perform pg_temp.expect('listo y sin repartidor = oferta visible',
    (select count(*) from public.orders where id = v_id) = 1);
  perform pg_temp.expect('la oferta no revela el código de entrega',
    (select delivery_code from public.orders where id = v_id) = '');
  perform pg_temp.expect('order_secrets es ilegible para el repartidor',
    (select count(*) from public.order_secrets) = 0);

  -- Distancia mayor al alcance de la bicicleta (4 km): out_of_range.
  perform pg_temp.admin();
  update public.orders set distance_km = 6 where id = v_id;
  perform pg_temp.as_user('otro_repartidor');
  perform pg_temp.expect('bicicleta no cubre 6 km → out_of_range', public.courier_accept(v_id) ->> 'result' = 'out_of_range');
  perform pg_temp.admin();
  update public.orders set distance_km = 0.5 where id = v_id;

  -- Repartidor de zona campus Icesi sí; el de zona general también.
  perform pg_temp.as_user('andres');
  r := public.courier_accept(v_id);
  perform pg_temp.expect('el primer repartidor gana', r ->> 'result' = 'ok');
  perform pg_temp.as_user('otro_repartidor');
  perform pg_temp.expect('el segundo → already_assigned', public.courier_accept(v_id) ->> 'result' = 'already_assigned');
  perform pg_temp.expect('con repartidor asignado la oferta desaparece',
    (select count(*) from public.orders where id = v_id) = 0);

  -- busy: Andrés ya tiene un pedido activo.
  perform pg_temp.as_user('diego');
  v_id2 := (public.place_order(pg_temp.payload()) #>> '{order,id}')::uuid;
  perform pg_temp.as_user('qbano');
  perform public.restaurant_accept(v_id2);
  perform public.restaurant_ready(v_id2);
  perform pg_temp.as_user('andres');
  perform pg_temp.expect('con una entrega activa → busy', public.courier_accept(v_id2) ->> 'result' = 'busy');
  perform pg_temp.as_user('otro_repartidor');
  perform pg_temp.expect('rechazar una oferta queda registrado', public.courier_decline(v_id2) ->> 'result' = 'ok');
  perform pg_temp.expect('tras rechazar no puede aceptarla', public.courier_accept(v_id2) ->> 'result' = 'declined_before');
  perform pg_temp.as_user('diego');
  perform pg_temp.expect('el comprador no puede rechazar ofertas → forbidden', public.courier_decline(v_id2) ->> 'result' = 'forbidden');

  -- Recogida y entrega.
  perform pg_temp.as_user('otro_repartidor');
  perform pg_temp.expect('repartidor ajeno no recoge → forbidden', public.courier_pickup(v_id) ->> 'result' = 'forbidden');
  perform pg_temp.as_user('andres');
  perform pg_temp.expect('entregar sin recoger → invalid_state', public.courier_deliver(v_id, v_code, 'x') ->> 'result' = 'invalid_state');
  perform pg_temp.expect('el repartidor recoge', public.courier_pickup(v_id) ->> 'result' = 'ok');

  perform pg_temp.expect('el repartidor no puede leer el código de entrega',
    (select delivery_code from public.orders where id = v_id) = '');
  perform pg_temp.as_user('diego');
  perform pg_temp.expect('el comprador sí lo lee en order_secrets',
    (select delivery_code from public.order_secrets where order_id = v_id) = v_code);

  perform pg_temp.as_user('andres');
  perform pg_temp.expect('código incorrecto → wrong_code', public.courier_deliver(v_id, '0000x', 'x') ->> 'result' = 'wrong_code');
  perform pg_temp.expect('sin evidencia → missing_evidence', public.courier_deliver(v_id, v_code, '') ->> 'result' = 'missing_evidence');
  perform pg_temp.expect('evidencia que no existe en Storage → missing_evidence',
    public.courier_deliver(v_id, v_code, v_id || '/fantasma.jpg') ->> 'result' = 'missing_evidence');

  -- Storage: solo el repartidor asignado sube a la carpeta del pedido.
  perform pg_temp.as_user('otro_repartidor');
  begin
    insert into storage.objects (bucket_id, name) values ('delivery-evidence', v_id || '/intruso.jpg');
    perform pg_temp.expect('un repartidor ajeno no puede subir evidencia', false);
  exception when insufficient_privilege or check_violation then
    perform pg_temp.expect('un repartidor ajeno no puede subir evidencia (RLS de Storage)', true);
  end;
  perform pg_temp.as_user('andres');
  insert into storage.objects (bucket_id, name) values ('delivery-evidence', v_id || '/foto.jpg');
  perform pg_temp.expect('evidencia en la carpeta de OTRO pedido → missing_evidence',
    public.courier_deliver(v_id, v_code, v_id2 || '/foto.jpg') ->> 'result' = 'missing_evidence');

  r := public.courier_deliver(v_id, v_code, v_id || '/foto.jpg');
  perform pg_temp.expect('entrega con código y foto → ok', r ->> 'result' = 'ok');
  perform pg_temp.expect('entregar dos veces → invalid_state',
    public.courier_deliver(v_id, v_code, v_id || '/foto.jpg') ->> 'result' = 'invalid_state');

  -- Gotas y libro.
  perform pg_temp.admin();
  perform pg_temp.expect('Gotas por entrega = subtotal/1000 (+13) en un solo abono',
    (select gotas from public.profiles where id = current_setting('t.diego')::uuid) = v_gotas0 + 13);
  perform pg_temp.expect('el libro registra el abono del pedido',
    (select count(*) from public.gotas_ledger where order_id = v_id and amount = 13) = 1);

  -- Historial: quién, cuándo y de qué estado a cuál.
  -- Se compara como conjunto: dentro de una transacción de prueba todos los
  -- eventos comparten `now()`; en producción cada RPC es su propia transacción.
  select string_agg(coalesce(from_status::text, '·') || '>' || status || '@' || actor_label, ' | ' order by 1)
    into v_events from public.order_events where order_id = v_id;
  raise notice 'Eventos: %', v_events;
  perform pg_temp.expect('6 eventos con estado de origen y actor',
    (select count(*) from public.order_events where order_id = v_id) = 6
    and (select count(*) from public.order_events where order_id = v_id and (
      (from_status is null and status = 'pending' and actor_label = 'Comprador') or
      (from_status = 'pending' and status = 'preparing' and actor_label = 'Restaurante') or
      (from_status = 'preparing' and status = 'ready' and actor_label = 'Restaurante') or
      (from_status = 'ready' and status = 'ready' and actor_label = 'Repartidor') or
      (from_status = 'ready' and status = 'on_the_way' and actor_label = 'Repartidor') or
      (from_status = 'on_the_way' and status = 'delivered' and actor_label = 'Repartidor')
    )) = 6);
  perform pg_temp.expect('todos los eventos tienen actor_id',
    (select count(*) from public.order_events where order_id = v_id and actor_id is null) = 0);
end $$;

-- ====================================== 5 · Escrituras directas bloqueadas
do $$
declare
  v_id uuid;
begin
  perform pg_temp.admin();
  select id into v_id from public.orders limit 1;

  perform pg_temp.as_user('diego');
  begin
    update public.orders set status = 'delivered' where id = v_id;
    perform pg_temp.expect('update directo a orders debe fallar', false);
  exception when insufficient_privilege then
    perform pg_temp.expect('update directo a orders → insufficient_privilege', true);
  end;
  begin
    insert into public.orders (buyer_id, branch_id, payment_method, subtotal, total, delivery_code)
    values (current_setting('t.diego')::uuid, current_setting('t.branch')::uuid, 'cash', 0, 0, '1');
    perform pg_temp.expect('insert directo a orders debe fallar', false);
  exception when insufficient_privilege then
    perform pg_temp.expect('insert directo a orders → insufficient_privilege', true);
  end;
  begin
    delete from public.order_events;
    perform pg_temp.expect('delete en order_events debe fallar', false);
  exception when insufficient_privilege then
    perform pg_temp.expect('delete en order_events → insufficient_privilege', true);
  end;
  begin
    update public.order_secrets set delivery_code = '0000';
    perform pg_temp.expect('update en order_secrets debe fallar', false);
  exception when insufficient_privilege then
    perform pg_temp.expect('update en order_secrets → insufficient_privilege', true);
  end;
  begin
    perform public.credit_gotas(current_setting('t.diego')::uuid, 1000000, 'regalo');
    perform pg_temp.expect('credit_gotas no debe ser llamable por clientes', false);
  exception when insufficient_privilege then
    perform pg_temp.expect('credit_gotas no es llamable por clientes (RPC)', true);
  end;
end $$;

-- Un comprador y un restaurante ajenos no ven pedidos de Diego, ni siquiera
-- los «listos sin repartidor» (esos son solo para repartidores).
select pg_temp.as_user('otro_comprador');
select pg_temp.expect('un comprador ajeno no ve ningún pedido de Diego',
  (select count(*) from public.orders) = 0);
select pg_temp.expect('un comprador ajeno no ve sus eventos ni sus líneas',
  (select count(*) from public.order_events) = 0
  and (select count(*) from public.order_items) = 0);
select pg_temp.as_user('otro_rest');
select pg_temp.expect('un restaurante ajeno no ve pedidos de otras sedes',
  (select count(*) from public.orders) = 0);
select pg_temp.as_user('otro_repartidor');
select pg_temp.expect('un repartidor sí ve la oferta pendiente (ready sin repartidor)',
  (select count(*) from public.orders where status = 'ready' and courier_id is null) >= 1);

reset role;
rollback;

-- Si llegaste aquí sin `FALLO`, el ciclo del pedido cumple la HU-3 a nivel de base.
