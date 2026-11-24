-- ============================================================================
-- HU-4 · Notificaciones generadas por la base
-- ============================================================================
-- Corre dentro de una transacción y hace rollback: no deja datos.
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hu4_notificaciones.sql
-- ============================================================================

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'ana.hu4@icesi.edu.co',     '{"role":"buyer","full_name":"Ana"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'beto.hu4@icesi.edu.co',    '{"role":"buyer","full_name":"Beto"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'local.hu4@demo.biffy.co',  '{"role":"restaurant","full_name":"Local"}'),
  ('00000000-0000-0000-0000-0000000000d4', 'repa.hu4@demo.biffy.co',   '{"role":"courier","full_name":"Repa"}'),
  ('00000000-0000-0000-0000-0000000000e5', 'bici.hu4@demo.biffy.co',   '{"role":"courier","full_name":"Bici"}'),
  ('00000000-0000-0000-0000-0000000000f6', 'pie.hu4@demo.biffy.co',    '{"role":"courier","full_name":"Pie"}'),
  ('00000000-0000-0000-0000-0000000000f7', 'dormido.hu4@demo.biffy.co','{"role":"courier","full_name":"Dormido"}');

insert into public.courier_profiles (user_id, full_name, doc_number, vehicle, online) values
  ('00000000-0000-0000-0000-0000000000d4', 'Repa',    '1', 'moto',    true),
  ('00000000-0000-0000-0000-0000000000e5', 'Bici',    '2', 'bicycle', true),
  ('00000000-0000-0000-0000-0000000000f6', 'Pie',     '3', 'walking', true),
  ('00000000-0000-0000-0000-0000000000f7', 'Dormido', '4', 'moto',    false)
on conflict (user_id) do update set vehicle = excluded.vehicle, online = excluded.online;

insert into public.businesses (id, owner_id, brand) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000c3', 'Local HU4');
insert into public.branches (id, business_id, name, campus_id, lat, lng) values
  ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-00000000b001', 'Local HU4 Icesi', 'icesi', 3.3640, -76.5305);  -- ~2,5 km del punto
insert into public.dishes (id, branch_id, category_id, name, price) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b101', 'sandwich', 'Sándwich', 12000);
insert into public.addresses (id, user_id, point_id, line, label) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a1', 'icesi-biblioteca', 'Biblioteca', 'Biblioteca');

create function pg_temp.como(p_user uuid, p_sql text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  execute 'select ' || p_sql into r;
  reset role;
  return r;
exception when others then
  reset role;
  return jsonb_build_object('result', 'error', 'sqlstate', sqlstate, 'message', sqlerrm);
end $$;

create function pg_temp.intentar(p_user uuid, p_sql text)
returns jsonb language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  execute p_sql;
  get diagnostics n = row_count;
  reset role;
  return jsonb_build_object('result', 'ok', 'n', n);
exception when others then
  reset role;
  return jsonb_build_object('result', 'error', 'sqlstate', sqlstate, 'message', sqlerrm);
end $$;

create function pg_temp.ok(p_user uuid, p_sql text) returns jsonb language plpgsql as $$
declare r jsonb;
begin
  r := pg_temp.como(p_user, p_sql);
  if r ->> 'result' <> 'ok' then raise exception 'FALLA %: %', p_sql, r; end if;
  return r;
end $$;

create function pg_temp.pedir() returns uuid language plpgsql as $$
begin
  return (pg_temp.ok('00000000-0000-0000-0000-0000000000a1', format('public.place_order(%L::jsonb)', jsonb_build_object(
    'branch_id', '00000000-0000-0000-0000-00000000b101',
    'address_id', '00000000-0000-0000-0000-00000000a001',
    'payment', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('dish_id', '00000000-0000-0000-0000-00000000d001', 'qty', 2))))) -> 'order' ->> 'id')::uuid;
end $$;

-- Avisos de un usuario para un pedido, en orden.
create function pg_temp.avisos(p_user uuid, p_order uuid) returns text[] language sql as $$
  select coalesce(array_agg(title order by created_at, title), '{}')
    from public.notifications where user_id = p_user and order_id = p_order
$$;

create function pg_temp.tiene(p_caso text, p_user uuid, p_order uuid, p_title text)
returns void language plpgsql as $$
begin
  if not (p_title = any (pg_temp.avisos(p_user, p_order))) then
    raise exception 'FALLA [%]: falta "%"; tiene %', p_caso, p_title, pg_temp.avisos(p_user, p_order);
  end if;
  raise notice 'ok · %', p_caso;
end $$;

do $t$
declare
  ana uuid := '00000000-0000-0000-0000-0000000000a1';
  beto uuid := '00000000-0000-0000-0000-0000000000b2';
  local uuid := '00000000-0000-0000-0000-0000000000c3';
  repa uuid := '00000000-0000-0000-0000-0000000000d4';
  bici uuid := '00000000-0000-0000-0000-0000000000e5';
  pie uuid := '00000000-0000-0000-0000-0000000000f6';
  dormido uuid := '00000000-0000-0000-0000-0000000000f7';
  p uuid;
  code text;
  oferta text;
  km numeric;
  r jsonb;
  n int;
begin
  p := pg_temp.pedir();
  code := (select o.code from public.orders o where o.id = p);

  perform pg_temp.tiene('el comprador sabe que su pedido se creó', ana, p, 'Pedido ' || code || ' creado');
  perform pg_temp.tiene('el restaurante recibe el pedido nuevo', local, p, 'Nuevo pedido ' || code);
  if (select body from public.notifications where user_id = local and order_id = p) <> '2× Sándwich' then
    raise exception 'FALLA: el aviso del restaurante no trae los platos';
  end if;

  perform pg_temp.ok(local, format('public.restaurant_accept(%L)', p));
  perform pg_temp.tiene('el comprador sabe que lo están preparando', ana, p, 'Pedido en preparación 👩‍🍳');

  perform pg_temp.ok(local, format('public.restaurant_ready(%L)', p));
  select 'Oferta disponible · ' || public.cop(o.courier_pay + o.tip), o.distance_km
    into oferta, km from public.orders o where o.id = p;
  if km not between 2 and 3 then
    raise exception 'FALLA: la sede debía quedar a ~2,5 km, quedó a % km', km;
  end if;
  perform pg_temp.tiene('el comprador sabe que está listo', ana, p, 'Pedido listo 🛍️');
  perform pg_temp.tiene('repartidor en moto recibe la oferta', repa, p, oferta);
  perform pg_temp.tiene('repartidor en bici (4 km) recibe la oferta', bici, p, oferta);
  if cardinality(pg_temp.avisos(pie, p)) > 0 then
    raise exception 'FALLA: el repartidor a pie (1,5 km) recibió una oferta de 2,5 km';
  end if;
  if cardinality(pg_temp.avisos(dormido, p)) > 0 then
    raise exception 'FALLA: el repartidor desconectado recibió la oferta';
  end if;
  raise notice 'ok · ni el repartidor a pie ni el desconectado reciben la oferta';

  perform pg_temp.ok(repa, format('public.courier_accept(%L)', p));
  perform pg_temp.tiene('el comprador sabe quién lo recoge', ana, p, 'Repartidor asignado 🛵');
  perform pg_temp.tiene('el restaurante sabe quién lo recoge', local, p, 'Repartidor asignado a ' || code);
  perform pg_temp.tiene('el repartidor recibe la asignación', repa, p, 'Pedido ' || code || ' asignado');
  if (select read_at from public.notifications where user_id = bici and order_id = p) is null then
    raise exception 'FALLA: la oferta de los demás repartidores sigue sin leer';
  end if;
  raise notice 'ok · la oferta se cierra para los demás repartidores';

  perform pg_temp.ok(repa, format('public.courier_pickup(%L)', p));
  perform pg_temp.tiene('el comprador sabe que va en camino', ana, p, 'Pedido en camino 🛵');

  insert into storage.objects (bucket_id, name, owner)
  values ('delivery-evidence', p || '/foto.jpg', repa);
  perform pg_temp.ok(repa, format('public.courier_deliver(%L, %L, %L)', p,
    (select delivery_code from public.order_secrets where order_id = p), p || '/foto.jpg'));
  perform pg_temp.tiene('el comprador sabe que se entregó', ana, p, 'Pedido entregado ✅');
  perform pg_temp.tiene('el restaurante sabe que se entregó', local, p, 'Pedido ' || code || ' entregado');
  if (select body from public.notifications where user_id = ana and order_id = p and title = 'Pedido entregado ✅')
     not like '%Ganaste 24 Gotas%' then
    raise exception 'FALLA: el aviso de entrega no dice las Gotas ganadas';
  end if;

  perform pg_temp.ok(ana, format('public.rate_order(%L::jsonb)', jsonb_build_object('order_id', p, 'rating', 5)));
  perform pg_temp.tiene('el restaurante recibe la calificación', local, p, 'Nueva calificación ⭐');

  -- Todos los avisos llevan rol y audiencia coherentes
  if exists (
    select 1 from public.notifications n
     where n.order_id = p
       and (n.role is null
         or (n.role = 'buyer' and n.audience <> 'user:' || n.user_id)
         or (n.role = 'courier' and n.audience <> 'courier:' || n.user_id)
         or (n.role = 'restaurant' and n.audience <> 'business:00000000-0000-0000-0000-00000000b001'))
  ) then
    raise exception 'FALLA: hay avisos sin rol o con audiencia equivocada';
  end if;
  raise notice 'ok · cada aviso guarda usuario, rol y audiencia';

  -- Rechazo del restaurante y cancelación del comprador
  p := pg_temp.pedir();
  perform pg_temp.ok(local, format('public.restaurant_reject(%L, %L)', p, 'Sin pan'));
  perform pg_temp.tiene('el comprador sabe que lo rechazaron', ana, p,
    'Pedido ' || (select o.code from public.orders o where o.id = p) || ' rechazado');
  if (select body from public.notifications where user_id = ana and order_id = p and title like '%rechazado')
     not like 'Motivo: Sin pan.%' then
    raise exception 'FALLA: el rechazo no trae el motivo';
  end if;

  p := pg_temp.pedir();
  perform pg_temp.ok(ana, format('public.buyer_cancel(%L)', p));
  perform pg_temp.tiene('el restaurante sabe que el cliente canceló', local, p,
    'Pedido ' || (select o.code from public.orders o where o.id = p) || ' cancelado por el cliente');

  -- Privacidad: cada quien ve solo lo suyo
  r := pg_temp.como(beto, $$ jsonb_build_object('n', (select count(*) from public.notifications)) $$);
  if (r ->> 'n')::int <> 0 then raise exception 'FALLA: Beto ve % avisos ajenos', r ->> 'n'; end if;
  r := pg_temp.como(ana, $$ jsonb_build_object('n', (select count(*) from public.notifications
        where user_id <> auth.uid())) $$);
  if (r ->> 'n')::int <> 0 then raise exception 'FALLA: Ana ve avisos ajenos'; end if;
  r := pg_temp.como(repa, $$ jsonb_build_object('n', (select count(*) from public.notifications
        where role <> 'courier')) $$);
  if (r ->> 'n')::int <> 0 then raise exception 'FALLA: el repartidor ve avisos de otros roles'; end if;
  raise notice 'ok · cada usuario ve solo sus avisos';

  -- Marcar como leída: solo las propias y solo read_at
  r := pg_temp.intentar(ana, $$ update public.notifications set read_at = now()
        where user_id = auth.uid() and read_at is null $$);
  if r ->> 'result' <> 'ok' or (r ->> 'n')::int = 0 then raise exception 'FALLA: Ana no pudo marcar leídas: %', r; end if;
  r := pg_temp.intentar(beto, format($$ update public.notifications set read_at = now() where user_id = %L $$, local));
  if r ->> 'result' = 'ok' and (r ->> 'n')::int > 0 then raise exception 'FALLA: Beto marcó avisos ajenos'; end if;
  r := pg_temp.intentar(ana, $$ update public.notifications set title = 'hackeado' where user_id = auth.uid() $$);
  if r ->> 'result' <> 'error' then raise exception 'FALLA: Ana reescribió un aviso'; end if;
  r := pg_temp.intentar(ana, format($$ insert into public.notifications (user_id, audience, title)
        values (%L, %L, 'falso') $$, beto, 'user:' || beto));
  if r ->> 'result' <> 'error' then raise exception 'FALLA: Ana creó un aviso para Beto'; end if;
  r := pg_temp.intentar(ana, $$ select public.notify(auth.uid(), 'buyer', 'all', 'x', 'y', null, null) $$);
  if r ->> 'result' <> 'error' then raise exception 'FALLA: Ana llamó notify()'; end if;
  raise notice 'ok · solo se marcan como leídas las propias; nadie reescribe ni falsifica avisos';

  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and tablename = 'notifications') then
    raise exception 'FALLA: notifications no está en Realtime';
  end if;
  raise notice 'ok · notifications está publicada en Realtime';
end $t$;

rollback;
