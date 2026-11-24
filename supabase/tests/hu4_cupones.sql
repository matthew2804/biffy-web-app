-- ============================================================================
-- HU-4 · Cupones en place_order
-- ============================================================================
-- Corre dentro de una transacción y hace rollback: no deja datos.
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hu4_cupones.sql
-- Si una verificación falla, el script corta con el mensaje del caso.
-- ============================================================================

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'ana.hu4@icesi.edu.co',   '{"role":"buyer","full_name":"Ana"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'beto.hu4@icesi.edu.co',  '{"role":"buyer","full_name":"Beto"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'local.hu4@demo.biffy.co','{"role":"restaurant","full_name":"Local"}');

insert into public.businesses (id, owner_id, brand)
values ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000c3', 'Local HU4');

insert into public.branches (id, business_id, name, campus_id, lat, lng)
values ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-00000000b001', 'Local HU4 Icesi', 'icesi', 3.3416, -76.5304);

insert into public.dishes (id, branch_id, category_id, name, price)
values ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b101', 'sandwich', 'Sándwich', 12000);

insert into public.addresses (id, user_id, point_id, line, label) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a1', 'icesi-biblioteca', 'Biblioteca', 'U'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-0000000000b2', 'icesi-biblioteca', 'Biblioteca', 'U');

insert into public.coupons (id, code, title, kind, amount, max_uses) values
  ('00000000-0000-0000-0000-00000000c001', 'HU4-FIJO',  '3.000 de descuento', 'fixed', 3000, 1),
  ('00000000-0000-0000-0000-00000000c002', 'HU4-ENVIO', 'Envío gratis',       'free_delivery', 0, 1),
  ('00000000-0000-0000-0000-00000000c003', 'HU4-VIEJO', 'Vencido',            'fixed', 5000, 1);
update public.coupons set valid_until = now() - interval '1 day' where code = 'HU4-VIEJO';

insert into public.user_coupons (user_id, coupon_id) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000c001'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000c002'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000c003');

-- Pide como el comprador. El servidor calcula precios (HU-3); si se manda
-- [p_total] y no coincide, rechaza con total_mismatch. [coupon_discount] se
-- manda inflado a propósito: la base debe ignorarlo.
create function pg_temp.pedido(p_user uuid, p_addr uuid, p_coupon uuid, p_total int default null)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  r := public.place_order(jsonb_strip_nulls(jsonb_build_object(
    'branch_id', '00000000-0000-0000-0000-00000000b101',
    'address_id', p_addr,
    'payment', 'cash',
    'lines', jsonb_build_array(jsonb_build_object(
      'dish_id', '00000000-0000-0000-0000-00000000d001', 'qty', 1)),
    'coupon_id', p_coupon,
    'coupon_discount', 12000,
    'total', p_total
  )));
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

do $t$
declare
  a uuid := '00000000-0000-0000-0000-0000000000a1';
  b uuid := '00000000-0000-0000-0000-0000000000b2';
  addr_a uuid := '00000000-0000-0000-0000-00000000a001';
  addr_b uuid := '00000000-0000-0000-0000-00000000a002';
  fijo uuid := '00000000-0000-0000-0000-00000000c001';
  envio uuid := '00000000-0000-0000-0000-00000000c002';
  viejo uuid := '00000000-0000-0000-0000-00000000c003';
  r jsonb;
begin
  r := pg_temp.pedido(a, addr_a, fijo, 2000);
  perform pg_temp.esperar('un total inventado por el cliente se rechaza', r, 'total_mismatch');
  if (r #>> '{breakdown,coupon_discount}')::int <> 3000 then
    raise exception 'FALLA: la base debía calcular 3000 de descuento, calculó %', r;
  end if;

  r := pg_temp.pedido(a, addr_a, null);
  perform pg_temp.esperar('sin cupón se crea el pedido', r, 'ok');
  if (r #>> '{order,coupon_discount}')::int <> 0 then
    raise exception 'FALLA: sin cupón el descuento debía ser 0 (el cliente mandó 12000)';
  end if;
  raise notice 'ok · el descuento que manda la app se ignora';

  r := pg_temp.pedido(b, addr_b, fijo);
  perform pg_temp.esperar('cupón de otro usuario se rechaza', r, 'coupon_unavailable');

  r := pg_temp.pedido(a, addr_a, viejo);
  perform pg_temp.esperar('cupón vencido se rechaza', r, 'coupon_unavailable');

  r := pg_temp.pedido(a, addr_a, fijo);
  perform pg_temp.esperar('cupón fijo válido aplica 3000', r, 'ok');
  if (r #>> '{order,coupon_discount}')::int <> 3000 then
    raise exception 'FALLA: coupon_discount guardado %', r #>> '{order,coupon_discount}';
  end if;

  r := pg_temp.pedido(a, addr_a, fijo);
  perform pg_temp.esperar('el mismo cupón no se usa dos veces', r, 'coupon_unavailable');

  r := pg_temp.pedido(a, addr_a, envio);
  perform pg_temp.esperar('envío gratis se acepta', r, 'ok');
  if (r #>> '{order,coupon_discount}')::int <> (r #>> '{order,delivery_fee}')::int then
    raise exception 'FALLA: envío gratis debía descontar la tarifa: %', r -> 'order';
  end if;
  raise notice 'ok · envío gratis descuenta exactamente la tarifa';

  if (select used_count from public.coupons where id = fijo) <> 1 then
    raise exception 'FALLA: used_count del cupón fijo';
  end if;
  if (select used_at from public.user_coupons where user_id = a and coupon_id = fijo) is null then
    raise exception 'FALLA: used_at no quedó marcado';
  end if;
  raise notice 'ok · cupón marcado como usado';
end $t$;

rollback;
