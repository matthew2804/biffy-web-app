-- ============================================================================
-- HU-4 · Reglas del servidor (0027): horario, repartidores y sold_today
-- ============================================================================
-- Corre dentro de una transacción y hace rollback: no deja datos.
-- El runner fija `biffy.now` al mediodía de Colombia; aquí se mueve a mano
-- para probar el horario.
-- ============================================================================

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000027a1', 'ana.reglas@icesi.edu.co',    '{"role":"buyer","full_name":"Ana"}'),
  ('00000000-0000-0000-0000-0000000027c3', 'local.reglas@demo.biffy.co', '{"role":"restaurant","full_name":"Local"}'),
  ('00000000-0000-0000-0000-0000000027d4', 'rita.reglas@icesi.edu.co',   '{"role":"courier","full_name":"Rita"}');

insert into public.businesses (id, owner_id, brand)
values ('00000000-0000-0000-0000-00000027b001', '00000000-0000-0000-0000-0000000027c3', 'Local Reglas');
-- El guard de perfiles solo deja fijar el negocio en escrituras internas.
select set_config('biffy.internal', '1', true);
update public.profiles set business_id = '00000000-0000-0000-0000-00000027b001'
 where id = '00000000-0000-0000-0000-0000000027c3';
select set_config('biffy.internal', '0', true);

-- Sede de 08:00 a 22:00, cerrada los domingos (isodow 7), con 3 porciones.
insert into public.branches (id, business_id, name, campus_id, lat, lng,
                             open_hour, close_hour, closed_weekdays, couriers_nearby)
values ('00000000-0000-0000-0000-00000027b101', '00000000-0000-0000-0000-00000027b001',
        'Local Reglas Icesi', 'icesi', 3.3416, -76.5304, 8, 22, '{7}', 99);

insert into public.dishes (id, branch_id, category_id, name, price, portion_limit, sold_today)
values ('00000000-0000-0000-0000-00000027d001', '00000000-0000-0000-0000-00000027b101',
        'sandwich', 'Sándwich', 12000, 3, 50);

insert into public.addresses (id, user_id, point_id, line, label) values
  ('00000000-0000-0000-0000-00000027a001', '00000000-0000-0000-0000-0000000027a1',
   'icesi-biblioteca', 'Biblioteca', 'U');

insert into public.courier_profiles (user_id, full_name, doc_number, online)
values ('00000000-0000-0000-0000-0000000027d4', 'Rita', '27', false);

-- Pide como Ana. Las excepciones `biffy:<código>` de los triggers se
-- devuelven como `result` (igual que hace la app con PostgrestException).
create function pg_temp.pedido(p_qty int default 1, p_when timestamptz default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000027a1', true);
  set local role authenticated;
  begin
    r := public.place_order(jsonb_strip_nulls(jsonb_build_object(
      'branch_id', '00000000-0000-0000-0000-00000027b101',
      'address_id', '00000000-0000-0000-0000-00000027a001',
      'payment', 'cash',
      'lines', jsonb_build_array(jsonb_build_object(
        'dish_id', '00000000-0000-0000-0000-00000027d001', 'qty', p_qty)),
      'scheduled_for', p_when
    )));
  exception when others then
    r := jsonb_build_object('result', replace(sqlerrm, 'biffy:', ''));
  end;
  reset role;
  return r;
end $$;

-- Ejecuta un RPC como el usuario dado.
create function pg_temp.como(p_user uuid, p_sql text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  execute p_sql into r;
  reset role;
  return r;
end $$;

create function pg_temp.esperar(p_caso text, p_res jsonb, p_result text)
returns void language plpgsql as $$
begin
  if p_res ->> 'result' is distinct from p_result then
    raise exception 'FALLA [%]: esperaba %, llegó %', p_caso, p_result, p_res;
  end if;
  raise notice 'ok · %', p_caso;
end $$;

create function pg_temp.igual(p_caso text, p_valor anyelement, p_esperado anyelement)
returns void language plpgsql as $$
begin
  if p_valor is distinct from p_esperado then
    raise exception 'FALLA [%]: esperaba %, llegó %', p_caso, p_esperado, p_valor;
  end if;
  raise notice 'ok · %', p_caso;
end $$;

do $t$
declare
  ana uuid := '00000000-0000-0000-0000-0000000027a1';
  local_ uuid := '00000000-0000-0000-0000-0000000027c3';
  rita uuid := '00000000-0000-0000-0000-0000000027d4';
  sede uuid := '00000000-0000-0000-0000-00000027b101';
  plato uuid := '00000000-0000-0000-0000-00000027d001';
  base int;
  r jsonb;
begin
  -- ------------------------------------------------ Datos que no manda el cliente
  perform pg_temp.igual('sold_today del alta lo fija el servidor en 0',
    (select sold_today from public.dishes where id = plato), 0);
  base := (select couriers_nearby from public.branches where id = sede);
  perform pg_temp.igual('couriers_nearby del alta sale de los repartidores reales',
    base, public.couriers_nearby_for('icesi'));

  -- ------------------------------------------------------ Repartidores cercanos
  r := pg_temp.como(rita, 'select public.courier_set_online(true)');
  perform pg_temp.esperar('repartidor se conecta', r, 'ok');
  perform pg_temp.igual('conectarse suma un repartidor a la sede',
    (select couriers_nearby from public.branches where id = sede), base + 1);

  r := pg_temp.como(rita, 'select public.courier_set_online(true, ''campus'')');
  perform pg_temp.esperar('zona campus sin verificación se rechaza', r, 'not_verified');

  r := pg_temp.como(rita, 'select public.courier_set_online(false)');
  perform pg_temp.igual('desconectarse resta el repartidor',
    (select couriers_nearby from public.branches where id = sede), base);

  r := pg_temp.como(ana, 'select public.courier_set_online(true)');
  perform pg_temp.esperar('un comprador no puede conectarse como repartidor', r, 'no_profile');

  -- Sin nadie conectado, el pedido se rechaza aunque el radio alcance.
  update public.courier_profiles set online = false;
  perform pg_temp.igual('sin repartidores la sede queda en 0',
    (select couriers_nearby from public.branches where id = sede), 0);
  perform pg_temp.esperar('sin repartidores no se puede pedir', pg_temp.pedido(), 'out_of_zone');

  perform set_config('request.jwt.claim.sub', local_::text, true);
  set local role authenticated;
  update public.branches set couriers_nearby = 50 where id = sede;
  reset role;
  perform pg_temp.igual('el restaurante no puede inventar repartidores',
    (select couriers_nearby from public.branches where id = sede), 0);

  perform pg_temp.como(rita, 'select public.courier_set_online(true)');

  -- ----------------------------------------------------------------- Horario
  perform set_config('biffy.now', '2026-11-25 23:00:00-05', true);  -- miércoles 23:00
  perform pg_temp.esperar('pedido inmediato con la sede cerrada', pg_temp.pedido(), 'branch_closed');

  insert into public.app_settings (user_id, demo_lunch) values (ana, true)
  on conflict (user_id) do update set demo_lunch = true;
  r := pg_temp.pedido();
  perform pg_temp.esperar('«Horario de demostración» simula las 12:00', r, 'ok');
  perform public.buyer_cancel((r #>> '{order,id}')::uuid);
  update public.app_settings set demo_lunch = false where user_id = ana;

  perform pg_temp.esperar('programado a las 23:00 se rechaza',
    pg_temp.pedido(1, '2026-11-26 23:00:00-05'), 'invalid_schedule');
  perform pg_temp.esperar('programado un domingo se rechaza',
    pg_temp.pedido(1, '2026-11-29 12:00:00-05'), 'invalid_schedule');
  perform pg_temp.esperar('programado en el pasado se rechaza',
    pg_temp.pedido(1, '2026-11-25 12:00:00-05'), 'invalid_schedule');
  r := pg_temp.pedido(1, '2026-11-26 13:00:00-05');
  perform pg_temp.esperar('programado dentro del horario se acepta', r, 'ok');
  perform public.buyer_cancel((r #>> '{order,id}')::uuid);

  perform set_config('biffy.now', '2026-11-29 12:00:00-05', true);  -- domingo
  perform pg_temp.esperar('día cerrado de la sede', pg_temp.pedido(), 'branch_closed');

  -- -------------------------------------------------------------- sold_today
  perform set_config('biffy.now', '2026-11-25 12:00:00-05', true);
  -- Los pedidos de demo y programados de arriba se cancelaron: el conteo
  -- del día debe haber vuelto a 0 sin tocar nada a mano.
  perform pg_temp.igual('los pedidos cancelados no dejan porciones ocupadas',
    public.dish_sold_today((select d from public.dishes d where d.id = plato)), 0);

  r := pg_temp.pedido(2);
  perform pg_temp.esperar('pedido de 2 porciones', r, 'ok');
  perform pg_temp.igual('sold_today sube con el pedido',
    (select sold_today from public.dishes where id = plato), 2);
  perform pg_temp.igual('sold_on queda en el día de Colombia',
    (select sold_on from public.dishes where id = plato), date '2026-11-25');

  perform pg_temp.esperar('no se pasa del límite de porciones',
    pg_temp.pedido(2), 'no_portions');

  perform set_config('request.jwt.claim.sub', local_::text, true);
  set local role authenticated;
  update public.dishes set sold_today = 0 where id = plato;
  reset role;
  perform pg_temp.igual('el restaurante no puede reiniciar sold_today a mano',
    (select sold_today from public.dishes where id = plato), 2);

  perform pg_temp.como(ana, format('select public.buyer_cancel(%L::uuid)', r #>> '{order,id}'));
  perform pg_temp.igual('cancelar devuelve las porciones',
    (select sold_today from public.dishes where id = plato), 0);

  r := pg_temp.pedido(3);
  perform pg_temp.esperar('tras cancelar vuelven a alcanzar las 3 porciones', r, 'ok');

  -- Día siguiente: el conteo de ayer no cuenta.
  perform set_config('biffy.now', '2026-11-26 12:00:00-05', true);
  perform pg_temp.igual('reset_sold_today limpia el día anterior', public.reset_sold_today(), 1);
  perform pg_temp.esperar('al otro día hay porciones de nuevo', pg_temp.pedido(1), 'ok');
  perform pg_temp.igual('el día nuevo empieza a contar desde 1',
    (select sold_today from public.dishes where id = plato), 1);
end $t$;

rollback;
