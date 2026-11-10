-- ============================================================================
-- HU-4 · Gotas: el ledger es la única fuente del saldo
-- ============================================================================
-- Corre dentro de una transacción y hace rollback: no deja datos.
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hu4_gotas.sql
-- ============================================================================

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'ana.hu4@icesi.edu.co',    '{"role":"buyer","full_name":"Ana"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'local.hu4@demo.biffy.co', '{"role":"restaurant","full_name":"Local"}'),
  ('00000000-0000-0000-0000-0000000000d4', 'repa.hu4@demo.biffy.co',  '{"role":"courier","full_name":"Repa"}');

insert into public.courier_profiles (user_id, full_name, doc_number, online)
values ('00000000-0000-0000-0000-0000000000d4', 'Repa', '123', true)
on conflict (user_id) do update set online = true;

insert into public.businesses (id, owner_id, brand)
values ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000c3', 'Local HU4');
insert into public.branches (id, business_id, name, campus_id, lat, lng)
values ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-00000000b001', 'Local HU4 Icesi', 'icesi', 3.3416, -76.5304);
insert into public.dishes (id, branch_id, category_id, name, price)
values ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b101', 'sandwich', 'Sándwich', 12000);
insert into public.addresses (id, user_id, point_id, line, label)
values ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a1', 'icesi-biblioteca', 'Biblioteca', 'U');

-- Ejecuta una expresión como el usuario autenticado `p_user`.
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

-- Ejecuta una sentencia como `p_user`; devuelve filas afectadas o el error.
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

create function pg_temp.cuadra(p_user uuid, p_caso text)
returns void language plpgsql as $$
declare v_saldo int; v_suma int;
begin
  select gotas into v_saldo from public.profiles where id = p_user;
  select coalesce(sum(amount), 0) into v_suma from public.gotas_ledger where user_id = p_user;
  if v_saldo is distinct from v_suma then
    raise exception 'FALLA [%]: profiles.gotas = %, suma del ledger = %', p_caso, v_saldo, v_suma;
  end if;
  raise notice 'ok · % (saldo % = ledger)', p_caso, v_saldo;
end $$;

do $t$
declare
  ana uuid := '00000000-0000-0000-0000-0000000000a1';
  local uuid := '00000000-0000-0000-0000-0000000000c3';
  repa uuid := '00000000-0000-0000-0000-0000000000d4';
  r jsonb;
  pedido uuid;
  codigo text;
  n int;
begin
  -- Bienvenida
  if (select gotas from public.profiles where id = ana) <> 450 then
    raise exception 'FALLA: la bienvenida no dio 450 Gotas';
  end if;
  if (select count(*) from public.gotas_ledger where user_id = ana) <> 1 then
    raise exception 'FALLA: la bienvenida debe ser un solo movimiento';
  end if;
  perform pg_temp.cuadra(ana, 'bienvenida de 450');

  -- El cliente no puede tocar el ledger ni su saldo
  r := pg_temp.intentar(ana, $$ insert into public.gotas_ledger (user_id, amount, reason)
        values (auth.uid(), 1000, 'trampa') $$);
  if r ->> 'result' <> 'error' then raise exception 'FALLA: el cliente insertó en gotas_ledger: %', r; end if;
  raise notice 'ok · el cliente no puede insertar movimientos (%)', r ->> 'message';

  r := pg_temp.intentar(ana, $$ update public.gotas_ledger set amount = 99999 where user_id = auth.uid() $$);
  if r ->> 'result' = 'ok' and (r ->> 'n')::int > 0 then raise exception 'FALLA: el cliente editó gotas_ledger'; end if;
  raise notice 'ok · el cliente no puede editar movimientos (%)', coalesce(r ->> 'message', 'filas: ' || (r ->> 'n'));

  r := pg_temp.intentar(ana, $$ delete from public.gotas_ledger where user_id = auth.uid() $$);
  if r ->> 'result' = 'ok' and (r ->> 'n')::int > 0 then raise exception 'FALLA: el cliente borró gotas_ledger'; end if;
  raise notice 'ok · el cliente no puede borrar movimientos (%)', coalesce(r ->> 'message', 'filas: ' || (r ->> 'n'));

  r := pg_temp.intentar(ana, $$ update public.profiles set gotas = 99999 where id = auth.uid() $$);
  if (select gotas from public.profiles where id = ana) <> 450 then
    raise exception 'FALLA: el cliente cambió su saldo directo';
  end if;
  raise notice 'ok · el cliente no puede cambiar profiles.gotas (%)', coalesce(r ->> 'message', 'filas: ' || (r ->> 'n'));
  r := pg_temp.intentar(ana, $$ select public.credit_gotas(auth.uid(), 1000, 'trampa', null) $$);
  if r ->> 'result' <> 'error' then raise exception 'FALLA: el cliente llamó credit_gotas'; end if;
  raise notice 'ok · el cliente no puede llamar credit_gotas (%)', r ->> 'message';
  perform pg_temp.cuadra(ana, 'después de los intentos');

  -- Pedido pagando 100 Gotas (100 × 10 = 1.000 COP)
  r := pg_temp.como(ana, format($$ public.place_order(%L::jsonb) $$, jsonb_build_object(
    'branch_id', '00000000-0000-0000-0000-00000000b101',
    'address_id', '00000000-0000-0000-0000-00000000a001',
    'payment', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('dish_id', '00000000-0000-0000-0000-00000000d001', 'qty', 1)),
    'subtotal', 12000, 'delivery_fee', 2000, 'gotas_used', 100, 'total', 13000)));
  if r ->> 'result' <> 'ok' then raise exception 'FALLA place_order: %', r; end if;
  pedido := (r -> 'order' ->> 'id')::uuid;
  codigo := r -> 'order' ->> 'delivery_code';
  if not exists (select 1 from public.gotas_ledger
                  where user_id = ana and amount = -100 and order_id = pedido and reason <> '') then
    raise exception 'FALLA: el gasto de Gotas no quedó con motivo y pedido';
  end if;
  perform pg_temp.cuadra(ana, 'gasto de 100 en el pedido');

  -- Flujo hasta entregar
  r := pg_temp.como(local, format('public.restaurant_accept(%L)', pedido));
  if r ->> 'result' <> 'ok' then raise exception 'FALLA restaurant_accept: %', r; end if;
  r := pg_temp.como(local, format('public.restaurant_ready(%L)', pedido));
  if r ->> 'result' <> 'ok' then raise exception 'FALLA restaurant_ready: %', r; end if;
  r := pg_temp.como(repa, format('public.courier_accept(%L)', pedido));
  if r ->> 'result' <> 'ok' then raise exception 'FALLA courier_accept: %', r; end if;
  r := pg_temp.como(repa, format('public.courier_pickup(%L)', pedido));
  if r ->> 'result' <> 'ok' then raise exception 'FALLA courier_pickup: %', r; end if;
  r := pg_temp.como(repa, format('public.courier_deliver(%L, %L, %L)', pedido, codigo, pedido || '/foto.jpg'));
  if r ->> 'result' <> 'ok' then raise exception 'FALLA courier_deliver: %', r; end if;

  select count(*) into n from public.gotas_ledger
   where user_id = ana and order_id = pedido and amount > 0;
  if n <> 1 then raise exception 'FALLA: la entrega debía acreditar 1 vez, acreditó %', n; end if;
  if not exists (select 1 from public.gotas_ledger
                  where user_id = ana and order_id = pedido and amount = 12 and reason <> '') then
    raise exception 'FALLA: la entrega debía acreditar 12 Gotas con motivo';
  end if;
  raise notice 'ok · la entrega acredita 12 Gotas una vez, con motivo y pedido';

  -- Repetir la entrega no duplica
  r := pg_temp.como(repa, format('public.courier_deliver(%L, %L, %L)', pedido, codigo, pedido || '/foto.jpg'));
  if r ->> 'result' = 'ok' then raise exception 'FALLA: se pudo entregar dos veces'; end if;
  select count(*) into n from public.gotas_ledger
   where user_id = ana and order_id = pedido and amount > 0;
  if n <> 1 then raise exception 'FALLA: repetir la entrega duplicó Gotas'; end if;
  raise notice 'ok · repetir la entrega no duplica (%)', r ->> 'result';
  perform pg_temp.cuadra(ana, 'después de la entrega');

  -- Todos los movimientos tienen motivo
  if exists (select 1 from public.gotas_ledger where coalesce(trim(reason), '') = '') then
    raise exception 'FALLA: hay movimientos sin motivo';
  end if;
  raise notice 'ok · todos los movimientos tienen motivo';
end $t$;

rollback;
