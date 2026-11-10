-- ============================================================================
-- HU-4 · Reseñas (rate_order) y promedio de la sede
-- ============================================================================
-- Corre dentro de una transacción y hace rollback: no deja datos.
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hu4_resenas.sql
-- ============================================================================

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'ana.hu4@icesi.edu.co',    '{"role":"buyer","full_name":"Ana"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'beto.hu4@icesi.edu.co',   '{"role":"buyer","full_name":"Beto"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'local.hu4@demo.biffy.co', '{"role":"restaurant","full_name":"Local"}'),
  ('00000000-0000-0000-0000-0000000000d4', 'repa.hu4@demo.biffy.co',  '{"role":"courier","full_name":"Repa"}');

insert into public.courier_profiles (user_id, full_name, doc_number, online)
values ('00000000-0000-0000-0000-0000000000d4', 'Repa', '123', true)
on conflict (user_id) do update set online = true;

insert into public.businesses (id, owner_id, brand) values
  ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000c3', 'Local HU4');
insert into public.branches (id, business_id, name, campus_id, lat, lng) values
  ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-00000000b001', 'Sede A', 'icesi', 3.3416, -76.5304),
  ('00000000-0000-0000-0000-00000000b102', '00000000-0000-0000-0000-00000000b001', 'Sede B', 'icesi', 3.3416, -76.5304);
insert into public.dishes (id, branch_id, category_id, name, price) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b101', 'sandwich', 'Sándwich', 12000);
insert into public.addresses (id, user_id, point_id, line, label) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a1', 'icesi-biblioteca', 'Biblioteca', 'U');

create function pg_temp.como(p_user uuid, p_sql text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), true);
  perform set_config('request.jwt.claim.role', case when p_user is null then 'anon' else 'authenticated' end, true);
  if p_user is null then set local role anon; else set local role authenticated; end if;
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

create function pg_temp.pedir() returns uuid language plpgsql as $$
declare r jsonb;
begin
  r := pg_temp.como('00000000-0000-0000-0000-0000000000a1', format('public.place_order(%L::jsonb)', jsonb_build_object(
    'branch_id', '00000000-0000-0000-0000-00000000b101',
    'address_id', '00000000-0000-0000-0000-00000000a001',
    'payment', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('dish_id', '00000000-0000-0000-0000-00000000d001', 'qty', 1)))));
  if r ->> 'result' <> 'ok' then raise exception 'FALLA place_order: %', r; end if;
  return (r -> 'order' ->> 'id')::uuid;
end $$;

create function pg_temp.entregar(p_order uuid) returns void language plpgsql as $$
declare
  local uuid := '00000000-0000-0000-0000-0000000000c3';
  repa uuid := '00000000-0000-0000-0000-0000000000d4';
  codigo text := (select delivery_code from public.order_secrets where order_id = p_order);
  r jsonb;
  paso text;
begin
  foreach paso in array array[
    format('public.restaurant_accept(%L)', p_order),
    format('public.restaurant_ready(%L)', p_order)
  ] loop
    r := pg_temp.como(local, paso);
    if r ->> 'result' <> 'ok' then raise exception 'FALLA %: %', paso, r; end if;
  end loop;
  insert into storage.objects (bucket_id, name, owner)
  values ('delivery-evidence', p_order || '/foto.jpg', repa);
  foreach paso in array array[
    format('public.courier_accept(%L)', p_order),
    format('public.courier_pickup(%L)', p_order),
    format('public.courier_deliver(%L, %L, %L)', p_order, codigo, p_order || '/foto.jpg')
  ] loop
    r := pg_temp.como(repa, paso);
    if r ->> 'result' <> 'ok' then raise exception 'FALLA %: %', paso, r; end if;
  end loop;
end $$;

create function pg_temp.calificar(p_user uuid, p_order uuid, p_rating text, p_extra jsonb default '{}')
returns jsonb language sql as $$
  select pg_temp.como(p_user, format('public.rate_order(%L::jsonb)',
    jsonb_build_object('order_id', p_order, 'rating', p_rating) || p_extra))
$$;

create function pg_temp.esperar(p_caso text, p_res jsonb, p_result text)
returns void language plpgsql as $$
begin
  if p_res ->> 'result' is distinct from p_result then
    raise exception 'FALLA [%]: esperaba %, llegó %', p_caso, p_result, p_res;
  end if;
  raise notice 'ok · %', p_caso;
end $$;

do $t$
declare
  ana uuid := '00000000-0000-0000-0000-0000000000a1';
  beto uuid := '00000000-0000-0000-0000-0000000000b2';
  local uuid := '00000000-0000-0000-0000-0000000000c3';
  sede_a uuid := '00000000-0000-0000-0000-00000000b101';
  sede_b uuid := '00000000-0000-0000-0000-00000000b102';
  p1 uuid;
  p2 uuid;
  r jsonb;
begin
  p1 := pg_temp.pedir();
  perform pg_temp.esperar('no se califica un pedido sin entregar',
    pg_temp.calificar(ana, p1, '5'), 'invalid_state');

  perform pg_temp.entregar(p1);

  perform pg_temp.esperar('no se califica un pedido ajeno',
    pg_temp.calificar(beto, p1, '1'), 'forbidden');
  perform pg_temp.esperar('calificación 0 se rechaza',
    pg_temp.calificar(ana, p1, '0'), 'invalid_rating');
  perform pg_temp.esperar('calificación 6 se rechaza',
    pg_temp.calificar(ana, p1, '6'), 'invalid_rating');
  perform pg_temp.esperar('calificación no numérica se rechaza',
    pg_temp.calificar(ana, p1, '4.5'), 'invalid_rating');
  perform pg_temp.esperar('comentario de más de 500 se rechaza',
    pg_temp.calificar(ana, p1, '4', jsonb_build_object('comment', repeat('a', 501))), 'comment_too_long');

  r := pg_temp.intentar(ana, format($$ insert into public.reviews (order_id, user_id, branch_id, rating)
        values (%L, %L, %L, 5) $$, p1, ana, sede_b));
  if r ->> 'result' <> 'error' then raise exception 'FALLA: se insertó una reseña directa a otra sede'; end if;
  raise notice 'ok · no se puede insertar una reseña directo (%)', r ->> 'message';

  r := pg_temp.calificar(ana, p1, '4', '{"comment":"  Muy rico  "}');
  perform pg_temp.esperar('el comprador califica su pedido entregado', r, 'ok');
  if (select branch_id from public.reviews where order_id = p1) <> sede_a then
    raise exception 'FALLA: la reseña no quedó en la sede del pedido';
  end if;
  if (select comment from public.reviews where order_id = p1) <> 'Muy rico' then
    raise exception 'FALLA: el comentario no se guardó limpio';
  end if;
  if (select rating from public.branches where id = sede_a) <> 4.0
     or (r ->> 'branch_rating')::numeric <> 4.0 then
    raise exception 'FALLA: el promedio de la sede debía ser 4.0, es %',
      (select rating from public.branches where id = sede_a);
  end if;
  raise notice 'ok · la reseña queda en la sede del pedido y el promedio pasa a 4.0';

  perform pg_temp.esperar('no se califica dos veces',
    pg_temp.calificar(ana, p1, '1'), 'already_rated');
  if (select count(*) from public.reviews where order_id = p1) <> 1 then
    raise exception 'FALLA: quedaron dos reseñas del mismo pedido';
  end if;

  p2 := pg_temp.pedir();
  perform pg_temp.entregar(p2);
  perform pg_temp.esperar('segundo pedido calificado con 5',
    pg_temp.calificar(ana, p2, '5'), 'ok');
  if (select rating from public.branches where id = sede_a) <> 4.5 then
    raise exception 'FALLA: el promedio debía ser 4.5, es %', (select rating from public.branches where id = sede_a);
  end if;
  raise notice 'ok · el promedio se actualiza a 4.5';

  if (select rating from public.branches where id = sede_b) <> 4.5 then
    raise exception 'FALLA: la sede B cambió sin reseñas';
  end if;
  raise notice 'ok · una sede sin reseñas conserva su valor';

  r := pg_temp.como(local, format($$ (select jsonb_build_object('n', count(*)) from public.reviews where branch_id = %L) $$, sede_a));
  if (r ->> 'n')::int <> 2 then raise exception 'FALLA: el restaurante no ve sus reseñas: %', r; end if;
  r := pg_temp.como(null, format($$ (select jsonb_build_object('n', count(*)) from public.reviews where branch_id = %L) $$, sede_a));
  if (r ->> 'n')::int <> 2 then raise exception 'FALLA: las reseñas no son públicas: %', r; end if;
  raise notice 'ok · el restaurante y el público ven las reseñas';

  r := pg_temp.intentar(ana, format($$ update public.reviews set rating = 1 where order_id = %L $$, p1));
  if r ->> 'result' = 'ok' and (r ->> 'n')::int > 0 then raise exception 'FALLA: se editó una reseña'; end if;
  r := pg_temp.intentar(local, format($$ delete from public.reviews where branch_id = %L $$, sede_a));
  if r ->> 'result' = 'ok' and (r ->> 'n')::int > 0 then raise exception 'FALLA: el restaurante borró reseñas'; end if;
  raise notice 'ok · nadie edita ni borra reseñas desde la app';
end $t$;

rollback;
