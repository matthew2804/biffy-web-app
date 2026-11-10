-- ============================================================================
-- HU-4 · Canjes de Gotas (redeem_reward)
-- ============================================================================
-- Corre dentro de una transacción y hace rollback: no deja datos.
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hu4_canjes.sql
-- ============================================================================

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'ana.hu4@icesi.edu.co',    '{"role":"buyer","full_name":"Ana"}'),
  ('00000000-0000-0000-0000-0000000000b2', 'beto.hu4@icesi.edu.co',   '{"role":"buyer","full_name":"Beto"}'),
  ('00000000-0000-0000-0000-0000000000c3', 'local.hu4@demo.biffy.co', '{"role":"restaurant","full_name":"Local"}');

insert into public.businesses (id, owner_id, brand)
values ('00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-0000000000c3', 'Local HU4');
insert into public.branches (id, business_id, name, campus_id, lat, lng)
values ('00000000-0000-0000-0000-00000000b101', '00000000-0000-0000-0000-00000000b001', 'Local HU4 Icesi', 'icesi', 3.3416, -76.5304);
insert into public.dishes (id, branch_id, category_id, name, price)
values ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b101', 'sandwich', 'Sándwich', 12000);
insert into public.addresses (id, user_id, point_id, line, label) values
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-0000000000a1', 'icesi-biblioteca', 'Biblioteca', 'U'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-0000000000b2', 'icesi-biblioteca', 'Biblioteca', 'U');

-- Recompensa que nadie puede pagar, para el caso de saldo insuficiente.
insert into public.gotas_rewards (code, name, reward_type, gotas_cost, is_active)
values ('hu4_cara', 'Caja imposible', 'mystery_box', 100000, true);
insert into public.gotas_reward_prizes (reward_id, code, label, prize_type, amount, weight)
select id, 'hu4_cara_premio', 'Premio', 'discount', 1000, 1 from public.gotas_rewards where code = 'hu4_cara';

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

create function pg_temp.saldo(p_user uuid) returns int language sql as $$
  select gotas from public.profiles where id = p_user $$;

create function pg_temp.cuadra(p_user uuid, p_caso text)
returns void language plpgsql as $$
declare v_saldo int; v_suma int;
begin
  select gotas into v_saldo from public.profiles where id = p_user;
  select coalesce(sum(amount), 0) into v_suma from public.gotas_ledger where user_id = p_user;
  if v_saldo is distinct from v_suma then
    raise exception 'FALLA [%]: profiles.gotas = %, suma del ledger = %', p_caso, v_saldo, v_suma;
  end if;
end $$;

do $t$
declare
  ana uuid := '00000000-0000-0000-0000-0000000000a1';
  beto uuid := '00000000-0000-0000-0000-0000000000b2';
  r jsonb;
  caja text;
  costo int;
  antes int;
  n int;
  cupon uuid;
begin
  -- Cajas: descuentan su costo y guardan el premio
  foreach caja in array array['box_25', 'box_50', 'box_100'] loop
    select gotas_cost into costo from public.gotas_rewards where code = caja;
    antes := pg_temp.saldo(ana);
    r := pg_temp.como(ana, format('public.redeem_reward(%L::jsonb)', jsonb_build_object('code', caja)));
    if r ->> 'result' <> 'ok' then raise exception 'FALLA canje %: %', caja, r; end if;
    if pg_temp.saldo(ana) <> antes - costo then
      raise exception 'FALLA [%]: saldo % → %, costo %', caja, antes, pg_temp.saldo(ana), costo;
    end if;
    if not exists (
      select 1 from public.reward_redemptions rr
        join public.gotas_rewards g on g.id = rr.reward_id
       where rr.id = (r ->> 'redemption_id')::uuid
         and g.code = caja and rr.gotas_spent = costo
         and rr.prize_label is not null and rr.prize_type is not null
    ) then
      raise exception 'FALLA [%]: el premio no quedó guardado: %', caja, r;
    end if;
    if not exists (select 1 from public.gotas_ledger
                    where user_id = ana and amount = -costo and reason like 'Canje:%') then
      raise exception 'FALLA [%]: el ledger no tiene el movimiento del canje', caja;
    end if;
    perform pg_temp.cuadra(ana, caja);
    raise notice 'ok · % descuenta % y guarda "%" (%)', caja, costo, r -> 'prize' ->> 'label', r -> 'prize' ->> 'type';
  end loop;

  -- Enfriamiento: repetir la caja no cobra
  antes := pg_temp.saldo(ana);
  r := pg_temp.como(ana, $$ public.redeem_reward('{"code":"box_25"}') $$);
  if r ->> 'result' <> 'cooldown' or pg_temp.saldo(ana) <> antes then
    raise exception 'FALLA enfriamiento: %', r;
  end if;
  raise notice 'ok · repetir box_25 antes de tiempo no cobra (cooldown)';

  -- Saldo insuficiente: no descuenta nada ni deja canje
  antes := pg_temp.saldo(beto);
  r := pg_temp.como(beto, $$ public.redeem_reward('{"code":"hu4_cara"}') $$);
  if r ->> 'result' <> 'insufficient_gotas' then raise exception 'FALLA saldo insuficiente: %', r; end if;
  if pg_temp.saldo(beto) <> antes
     or exists (select 1 from public.reward_redemptions where user_id = beto)
     or (select count(*) from public.gotas_ledger where user_id = beto) <> 1 then
    raise exception 'FALLA: con saldo insuficiente se tocó algo';
  end if;
  raise notice 'ok · saldo insuficiente no descuenta ni deja canje';

  -- Cada premio de descuento o envío gratis tiene su cupón
  select count(*) into n
    from public.reward_redemptions rr
   where rr.user_id = ana
     and rr.prize_type in ('discount', 'free_shipping')
     and not exists (select 1 from public.coupons c where c.code = 'PZ-' || upper(left(rr.id::text, 8)));
  if n > 0 then raise exception 'FALLA: % premios sin cupón', n; end if;
  raise notice 'ok · cada premio de descuento o envío tiene su cupón';

  -- Envío gratis: cobra su costo y deja un cupón usable
  select gotas_cost into costo from public.gotas_rewards where code = 'free_shipping';
  antes := pg_temp.saldo(beto);
  r := pg_temp.como(beto, $$ public.redeem_reward('{"code":"free_shipping"}') $$);
  if r ->> 'result' <> 'ok' or pg_temp.saldo(beto) <> antes - costo then
    raise exception 'FALLA canje free_shipping: %', r;
  end if;
  raise notice 'ok · free_shipping descuenta % Gotas', costo;

  select uc.coupon_id into cupon
    from public.user_coupons uc
    join public.coupons c on c.id = uc.coupon_id
   where uc.user_id = beto and c.kind = 'free_delivery' and uc.used_at is null;
  if cupon is null then raise exception 'FALLA: free_shipping no generó un cupón de envío gratis'; end if;
  raise notice 'ok · free_shipping genera un cupón de envío gratis';

  r := pg_temp.como(beto, format($$ public.place_order(%L::jsonb) $$, jsonb_build_object(
    'branch_id', '00000000-0000-0000-0000-00000000b101',
    'address_id', '00000000-0000-0000-0000-00000000a002',
    'payment', 'cash',
    'lines', jsonb_build_array(jsonb_build_object('dish_id', '00000000-0000-0000-0000-00000000d001', 'qty', 1)),
    'subtotal', 12000, 'delivery_fee', 2000, 'coupon_id', cupon, 'total', 12000)));
  if r ->> 'result' <> 'ok' or (r -> 'order' ->> 'coupon_discount')::int <> 2000 then
    raise exception 'FALLA: el cupón de envío gratis no se pudo usar: %', r;
  end if;
  raise notice 'ok · el cupón de envío gratis se usa en un pedido y quita los 2.000 del envío';

  -- Privacidad: Beto no ve los canjes ni cupones de Ana
  r := pg_temp.como(beto, $$ jsonb_build_object(
        'canjes', (select count(*) from public.reward_redemptions where user_id = '00000000-0000-0000-0000-0000000000a1'),
        'cupones', (select count(*) from public.user_coupons where user_id = '00000000-0000-0000-0000-0000000000a1')) $$);
  if (r ->> 'canjes')::int <> 0 or (r ->> 'cupones')::int <> 0 then
    raise exception 'FALLA: Beto ve datos de Ana: %', r;
  end if;
  raise notice 'ok · un usuario no ve canjes ni cupones de otro';

  -- No se puede crear un canje ni un cupón a mano
  r := pg_temp.intentar(beto, format($$ insert into public.reward_redemptions (user_id, reward_id, gotas_spent)
        select %L, id, 0 from public.gotas_rewards where code = 'box_100' $$, beto));
  if r ->> 'result' <> 'error' then raise exception 'FALLA: Beto creó un canje gratis'; end if;
  r := pg_temp.intentar(beto, format($$ insert into public.user_coupons (user_id, coupon_id) values (%L, %L) $$,
        beto, (select coupon_id from public.user_coupons where user_id = ana limit 1)));
  if r ->> 'result' <> 'error' then raise exception 'FALLA: Beto se asignó un cupón'; end if;
  raise notice 'ok · no se pueden crear canjes ni cupones a mano';
end $t$;

rollback;
