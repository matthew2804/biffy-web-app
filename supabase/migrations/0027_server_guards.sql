-- ============================================================================
-- 0027 · Reglas del servidor que antes solo validaba la app (HU-4 cierre)
-- ============================================================================
-- 1. Horario: un pedido solo entra si la sede está abierta (hora de Colombia)
--    a la hora de entrega. El ajuste «Horario de demostración» del comprador
--    (`app_settings.demo_lunch`) simula las 12:00, igual que la app.
-- 2. Repartidores cercanos: `branches.couriers_nearby` deja de ser un número
--    fijo y se calcula con los repartidores conectados (`courier_profiles`).
-- 3. `dishes.sold_today` lo lleva el servidor: sube al pedir, baja si el
--    pedido se cancela y se reinicia cada día. El cliente ya no lo escribe.
--
-- Todo va con triggers sobre `orders`, `order_items`, `courier_profiles`,
-- `branches` y `dishes`: funciona con cualquier versión de `place_order`
-- (la de HU-3 o la de pagos), sin redefinirla.
--
-- Los rechazos se lanzan como excepción con el mensaje `biffy:<código>`; la
-- app los traduce igual que el `result` de los RPC (order_errors.dart).
-- Idempotente: se puede volver a correr.
-- ============================================================================

-- ------------------------------------------------------------------ Utilidades

-- Hora actual del servidor. Las pruebas SQL pueden fijarla con
-- `set biffy.now = '...'`; PostgREST no deja a los clientes cambiar GUCs.
create or replace function public.biffy_now()
returns timestamptz
language sql
stable
set search_path = public
as $$
  select coalesce(
    nullif(current_setting('biffy.now', true), '')::timestamptz,
    now()
  );
$$;

-- Fecha de hoy en Colombia (el día comercial de los restaurantes).
create or replace function public.biffy_today()
returns date
language sql
stable
set search_path = public
as $$
  select (public.biffy_now() at time zone 'America/Bogota')::date;
$$;

-- Ejecuta un bloque como escritura interna y restaura el valor previo de
-- `biffy.internal` (no pisa el de quien llama, como pide 0023).
create or replace function public.biffy_internal_begin()
returns text
language plpgsql
as $$
declare
  v_prev text := coalesce(current_setting('biffy.internal', true), '0');
begin
  perform set_config('biffy.internal', '1', true);
  return v_prev;
end $$;

create or replace function public.biffy_internal_end(p_prev text)
returns void
language plpgsql
as $$
begin
  perform set_config('biffy.internal', coalesce(p_prev, '0'), true);
end $$;

-- ===================================================================== Horario

-- Indica si la sede atiende a esa hora local (espejo de isOpenAt en
-- catalog_rules.dart: día no cerrado y open_hour <= hora < close_hour).
create or replace function public.branch_open_at(
  p_branch public.branches,
  p_local timestamp
)
returns boolean
language sql
immutable
as $$
  select not p_branch.paused
     and not (extract(isodow from p_local)::smallint = any (p_branch.closed_weekdays))
     and extract(hour from p_local)::int >= p_branch.open_hour
     and extract(hour from p_local)::int < p_branch.close_hour;
$$;

-- Antes de crear el pedido: la sede debe estar abierta a la hora de entrega.
create or replace function public.guard_order_schedule()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch public.branches;
  v_local timestamp;
  v_demo boolean;
begin
  select * into v_branch from public.branches where id = new.branch_id;
  if not found then
    return new;  -- place_order ya responde branch_not_found
  end if;

  if new.scheduled_for is not null then
    if new.scheduled_for <= public.biffy_now() then
      raise exception using message = 'biffy:invalid_schedule';
    end if;
    v_local := new.scheduled_for at time zone 'America/Bogota';
  else
    select coalesce(s.demo_lunch, false) into v_demo
      from public.app_settings s
     where s.user_id = new.buyer_id;
    v_local := public.biffy_now() at time zone 'America/Bogota';
    -- «Horario de demostración»: mismo día, a las 12:00.
    if coalesce(v_demo, false) then
      v_local := date_trunc('day', v_local) + interval '12 hours';
    end if;
  end if;

  if not public.branch_open_at(v_branch, v_local) then
    raise exception using
      message = case when new.scheduled_for is null
        then 'biffy:branch_closed'
        else 'biffy:invalid_schedule' end;
  end if;
  return new;
end $$;

drop trigger if exists orders_guard_schedule on public.orders;
create trigger orders_guard_schedule
  before insert on public.orders
  for each row execute function public.guard_order_schedule();

-- ======================================================= Repartidores cercanos

-- Repartidores conectados que pueden atender la sede: los de zona general
-- sirven a todas; los de zona campus, solo a las sedes de su universidad.
create or replace function public.couriers_nearby_for(p_campus text)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from public.courier_profiles c
   where c.online
     and (c.zone = 'general'
          or (c.zone = 'campus' and c.university_id is not distinct from p_campus
              and p_campus is not null));
$$;

-- Recalcula `couriers_nearby` en todas las sedes vivas (Realtime avisa a la
-- app porque `branches` está publicada en 0010).
create or replace function public.refresh_couriers_nearby()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev text := public.biffy_internal_begin();
begin
  update public.branches b
     set couriers_nearby = public.couriers_nearby_for(b.campus_id)
   where b.deleted_at is null
     and b.couriers_nearby is distinct from public.couriers_nearby_for(b.campus_id);
  perform public.biffy_internal_end(v_prev);
end $$;

-- Cada cambio de conexión, zona o universidad de un repartidor recalcula.
create or replace function public.on_courier_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.refresh_couriers_nearby();
  return null;
end $$;

drop trigger if exists courier_profiles_nearby on public.courier_profiles;
create trigger courier_profiles_nearby
  after insert or delete or update of online, zone, university_id
  on public.courier_profiles
  for each statement execute function public.on_courier_change();

-- El repartidor se conecta o desconecta desde la app. Zona campus exige
-- estudiante verificado (misma regla que setCourierZone en la app).
create or replace function public.courier_set_online(
  p_online boolean,
  p_zone public.courier_zone default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.courier_profiles;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;
  select * into v_row from public.courier_profiles where user_id = v_uid for update;
  if not found then
    return jsonb_build_object('result', 'no_profile');
  end if;
  if p_zone = 'campus' and not public.is_verified_student(v_uid) then
    return jsonb_build_object('result', 'not_verified');
  end if;

  update public.courier_profiles
     set online = coalesce(p_online, online),
         zone = coalesce(p_zone, zone),
         university_id = case
           when coalesce(p_zone, zone) = 'campus'
             then coalesce(university_id,
                           (select university_id from public.profiles where id = v_uid))
           else university_id end
   where user_id = v_uid
   returning * into v_row;

  return jsonb_build_object(
    'result', 'ok', 'online', v_row.online, 'zone', v_row.zone
  );
end $$;

revoke all on function public.courier_set_online(boolean, public.courier_zone) from public;
grant execute on function public.courier_set_online(boolean, public.courier_zone) to authenticated;

-- El cliente ya no puede fijar `couriers_nearby` a mano (antes era simulado).
create or replace function public.guard_branch_couriers()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('biffy.internal', true), '0') = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.couriers_nearby := public.couriers_nearby_for(new.campus_id);
  elsif new.campus_id is distinct from old.campus_id then
    new.couriers_nearby := public.couriers_nearby_for(new.campus_id);
  else
    new.couriers_nearby := old.couriers_nearby;
  end if;
  return new;
end $$;

drop trigger if exists branches_guard_couriers on public.branches;
create trigger branches_guard_couriers
  before insert or update on public.branches
  for each row execute function public.guard_branch_couriers();

alter table public.branches alter column couriers_nearby set default 0;

-- =================================================================== sold_today

alter table public.dishes
  add column if not exists sold_on date;

comment on column public.dishes.sold_on is
  'Día (Colombia) al que corresponde sold_today. Si es otro día, cuenta 0.';

alter table public.order_items
  add column if not exists sold_on date;

comment on column public.order_items.sold_on is
  'Día en que el ítem sumó a dishes.sold_today; cancelar solo devuelve ese día.';

-- Unidades vendidas hoy, teniendo en cuenta el reinicio diario.
create or replace function public.dish_sold_today(p_dish public.dishes)
returns int
language sql
stable
as $$
  select case when p_dish.sold_on = public.biffy_today()
              then p_dish.sold_today else 0 end;
$$;

-- Antes de guardar cada ítem del pedido: suma las unidades y valida el límite de
-- porciones con el conteo del día (la fila del plato queda bloqueada, así dos
-- pedidos simultáneos no pasan el límite).
create or replace function public.on_order_item_sold()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dish public.dishes;
  v_sold int;
  v_prev text;
begin
  if new.dish_id is null then
    return new;
  end if;
  select * into v_dish from public.dishes where id = new.dish_id for update;
  if not found then
    return new;
  end if;
  v_sold := public.dish_sold_today(v_dish) + new.qty;
  if v_dish.portion_limit is not null and v_sold > v_dish.portion_limit then
    raise exception using message = 'biffy:no_portions', detail = v_dish.name;
  end if;

  v_prev := public.biffy_internal_begin();
  update public.dishes
     set sold_today = v_sold, sold_on = public.biffy_today()
   where id = v_dish.id;
  perform public.biffy_internal_end(v_prev);
  new.sold_on := public.biffy_today();
  return new;
end $$;

drop trigger if exists order_items_sold on public.order_items;
create trigger order_items_sold
  before insert on public.order_items
  for each row execute function public.on_order_item_sold();

-- Pedido cancelado (por el comprador, el restaurante o un pago rechazado):
-- devuelve las porciones de los ítems que se contaron hoy.
create or replace function public.on_order_cancel_release()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev text;
begin
  if new.status <> 'cancelled' or old.status = 'cancelled' then
    return new;
  end if;
  v_prev := public.biffy_internal_begin();
  update public.dishes d
     set sold_today = greatest(0, d.sold_today - i.qty)
    from (select dish_id, sold_on, sum(qty)::int as qty
            from public.order_items
           where order_id = new.id and dish_id is not null and sold_on is not null
           group by dish_id, sold_on) i
   where d.id = i.dish_id
     and d.sold_on = i.sold_on;
  perform public.biffy_internal_end(v_prev);
  return new;
end $$;

drop trigger if exists orders_cancel_release on public.orders;
create trigger orders_cancel_release
  after update of status on public.orders
  for each row execute function public.on_order_cancel_release();

-- El cliente no escribe `sold_today` ni `sold_on` (antes lo mandaba la app).
create or replace function public.guard_dish_sold()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if coalesce(current_setting('biffy.internal', true), '0') = '1' then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.sold_today := 0;
    new.sold_on := null;
  else
    new.sold_today := old.sold_today;
    new.sold_on := old.sold_on;
  end if;
  return new;
end $$;

drop trigger if exists dishes_guard_sold on public.dishes;
create trigger dishes_guard_sold
  before insert or update on public.dishes
  for each row execute function public.guard_dish_sold();

-- Reinicio diario a medianoche de Colombia (05:00 UTC). La lectura ya ignora
-- días viejos (`dish_sold_today`); esto deja la columna limpia para la app.
create or replace function public.reset_sold_today()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prev text := public.biffy_internal_begin();
  v_n int;
begin
  update public.dishes
     set sold_today = 0, sold_on = public.biffy_today()
   where sold_on is distinct from public.biffy_today() and sold_today <> 0;
  get diagnostics v_n = row_count;
  perform public.biffy_internal_end(v_prev);
  return v_n;
end $$;

revoke all on function public.reset_sold_today() from public, anon, authenticated;
revoke all on function public.refresh_couriers_nearby() from public, anon, authenticated;

-- pg_cron existe en Supabase; en el Postgres local de pruebas no, y se omite.
do $$
begin
  create extension if not exists pg_cron;
  perform cron.unschedule(jobid) from cron.job where jobname = 'biffy_reset_sold_today';
  perform cron.schedule('biffy_reset_sold_today', '0 5 * * *',
                        'select public.reset_sold_today()');
exception when others then
  raise notice 'pg_cron no disponible: el reinicio diario queda en dish_sold_today()';
end $$;

-- =================================================================== Datos

-- Estado inicial: conteo real de repartidores y ventas del día.
select public.refresh_couriers_nearby();
select public.reset_sold_today();
