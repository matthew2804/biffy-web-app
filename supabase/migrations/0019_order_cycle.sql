-- ============================================================================
-- 0019 · Ciclo completo del pedido (HU-3)
-- ============================================================================
-- Cierra las brechas del ciclo comprador -> restaurante -> repartidor:
--
--   1. place_order calcula TODO en el servidor (precios, descuentos, tarifa,
--      distancia, pago al repartidor). El cliente solo manda qué quiere comprar
--      y, opcionalmente, lo que cree que va a pagar: si no coincide, se rechaza
--      con `subtotal_mismatch` / `total_mismatch` y no se crea nada.
--   2. El código de entrega vive en `order_secrets` (solo lo lee el comprador).
--      Antes estaba en `orders` y el repartidor podía leerlo.
--   3. Cancelar / rechazar devuelve Gotas Y cupón.
--   4. `order_events.from_status`: cada evento dice de qué estado a cuál.
--   5. Idempotencia de place_order (`client_key`).
--   6. courier_deliver exige que la foto exista de verdad en Storage.
--   7. Escrituras directas a las tablas de pedidos revocadas (defensa en
--      profundidad además de RLS sin políticas de escritura).
--
-- Va DESPUÉS de 0014 (geografía) y 0018 (idempotencia): reemplaza place_order
-- conservando sus validaciones PostGIS (radio y polígono del campus).
--
-- Es idempotente: se puede volver a ejecutar.
-- ============================================================================

-- ------------------------------------------------------------ 1. Eventos

alter table public.order_events
  add column if not exists from_status public.order_status;

-- Rellena el estado de origen de los eventos que ya existían.
update public.order_events e
   set from_status = prev.status
  from (
    select id,
           lag(status) over (partition by order_id order by created_at, id)
             as status
      from public.order_events
  ) prev
 where prev.id = e.id
   and e.from_status is null
   and prev.status is not null;

drop function if exists public.order_event(uuid, public.order_status, text);

create or replace function public.order_event(
  p_order uuid,
  p_status public.order_status,
  p_label text,
  p_from public.order_status default null
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.order_events
    (order_id, from_status, status, actor_id, actor_label)
  values (p_order, p_from, p_status, auth.uid(), p_label)
$$;

-- ------------------------------------------------------ 2. Código de entrega

create table if not exists public.order_secrets (
  order_id uuid primary key references public.orders (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  delivery_code text not null
);

alter table public.order_secrets enable row level security;

drop policy if exists order_secrets_read on public.order_secrets;
create policy order_secrets_read on public.order_secrets
  for select to authenticated using (buyer_id = auth.uid());

-- Mueve los códigos existentes y vacía la columna pública.
insert into public.order_secrets (order_id, buyer_id, delivery_code)
select id, buyer_id, delivery_code
  from public.orders
 where delivery_code <> ''
on conflict (order_id) do nothing;

alter table public.orders alter column delivery_code set default '';

update public.orders set delivery_code = '' where delivery_code <> '';

-- ------------------------------------------------------- 3. Idempotencia

alter table public.orders add column if not exists client_key text;

-- 0018 creó un índice único global; el correcto es por comprador.
drop index if exists public.orders_client_key_idx;

create unique index if not exists orders_buyer_client_key_uidx
  on public.orders (buyer_id, client_key)
  where client_key is not null;

-- ------------------------------------------------------------ 4. Helpers

-- Haversine en km (espejo de distanceKm en lib/core/utils/geo.dart).
create or replace function public.distance_km(
  lat1 numeric, lng1 numeric, lat2 numeric, lng2 numeric
) returns numeric
language sql
immutable
as $$
  select (
    2 * 6371.0 * asin(least(1.0::float8, sqrt(
      power(sin(radians((lat2 - lat1)::float8) / 2), 2)
      + cos(radians(lat1::float8)) * cos(radians(lat2::float8))
        * power(sin(radians((lng2 - lng1)::float8) / 2), 2)
    )))
  )::numeric
$$;

-- Devuelve Gotas y cupón de un pedido que no se llegó a preparar.
create or replace function public.refund_order(p_order public.orders)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_order.gotas_used > 0 then
    perform public.credit_gotas(
      p_order.buyer_id, p_order.gotas_used,
      'Reembolso de ' || p_order.code, p_order.id
    );
  end if;

  if p_order.coupon_id is not null then
    update public.user_coupons
       set used_at = null
     where user_id = p_order.buyer_id
       and coupon_id = p_order.coupon_id
       and used_at is not null;
    if found then
      update public.coupons
         set used_count = greatest(0, used_count - 1)
       where id = p_order.coupon_id;
    end if;
  end if;
end;
$$;

-- Pedido tal como lo ve quien lo crea (incluye su código de entrega).
create or replace function public.order_json(p_order public.orders)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(p_order) || jsonb_build_object(
    'delivery_code',
    coalesce((
      select s.delivery_code from public.order_secrets s
       where s.order_id = p_order.id and s.buyer_id = auth.uid()
    ), '')
  )
$$;

-- ---------------------------------------------------------- 5. place_order

create or replace function public.place_order(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles;
  v_branch public.branches;
  v_addr public.addresses;
  v_point public.delivery_points;
  v_poly geometry;
  v_dish public.dishes;
  v_order public.orders;
  v_existing public.orders;
  v_coupon public.coupons;
  v_line jsonb;
  v_items jsonb := '[]'::jsonb;
  v_qty int;
  v_unit int;
  v_delta int;
  v_opt_count int;
  v_size uuid;
  v_side uuid;
  v_extras uuid[];
  v_prep int := 0;
  v_subtotal int := 0;
  v_campus int := 0;
  v_fee int;
  v_coupon_id uuid := nullif(p_payload ->> 'coupon_id', '')::uuid;
  v_coupon_disc int := 0;
  v_gotas int := coalesce((p_payload ->> 'gotas_used')::int, 0);
  v_payable int;
  v_tip int := coalesce((p_payload ->> 'tip')::int, 0);
  v_total int;
  v_km numeric;
  v_pay int;
  v_eta int;
  v_key text := nullif(trim(coalesce(p_payload ->> 'client_key', '')), '');
  v_payment text := p_payload ->> 'payment';
  v_delivery text;
  v_pickup text;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  -- Reintento con la misma clave: devuelve el pedido ya creado.
  if v_key is not null then
    select * into v_existing
      from public.orders
     where buyer_id = v_uid and client_key = v_key;
    if found then
      return jsonb_build_object(
        'result', 'ok', 'duplicate', true,
        'order', public.order_json(v_existing)
      );
    end if;
  end if;

  -- Bloquea el perfil: dos pedidos simultáneos no gastan las mismas Gotas.
  select * into v_profile from public.profiles where id = v_uid for update;
  if not found then
    return jsonb_build_object('result', 'no_profile');
  end if;

  if v_payment is null
     or v_payment not in ('nequi', 'daviplata', 'card', 'pse', 'cash') then
    return jsonb_build_object('result', 'invalid_payment');
  end if;

  select * into v_branch
    from public.branches
   where id = (p_payload ->> 'branch_id')::uuid and deleted_at is null;
  if not found then
    return jsonb_build_object('result', 'branch_not_found');
  end if;
  if v_branch.paused then
    return jsonb_build_object('result', 'branch_paused');
  end if;

  select * into v_addr
    from public.addresses
   where id = (p_payload ->> 'address_id')::uuid
     and user_id = v_uid
     and deleted_at is null;
  if not found then
    return jsonb_build_object('result', 'address_not_found');
  end if;

  select * into v_point from public.delivery_points where id = v_addr.point_id;
  if not found then
    return jsonb_build_object('result', 'point_not_found');
  end if;

  -- Regla de alcance (espejo de isReachable en catalog_rules.dart).
  v_km := round(public.distance_km(
    v_branch.lat, v_branch.lng, v_point.lat, v_point.lng
  ), 2);
  -- Sede solo campus: polígono real del campus (0014/0015) y, si no hay,
  -- el campus del punto de entrega.
  if v_branch.campus_delivery_only then
    select u.boundary_polygon into v_poly
      from public.universities u
     where u.id = v_branch.campus_id;
    if v_poly is not null and v_point.location is not null then
      if not st_covers(v_poly, v_point.location) then
        return jsonb_build_object('result', 'outside_campus');
      end if;
    elsif v_point.campus_id is distinct from v_branch.campus_id then
      return jsonb_build_object('result', 'outside_campus');
    end if;
  end if;
  if v_branch.couriers_nearby <= 0 or v_km > v_branch.radius_km then
    return jsonb_build_object('result', 'out_of_zone');
  end if;

  if jsonb_typeof(p_payload -> 'lines') is distinct from 'array'
     or jsonb_array_length(p_payload -> 'lines') = 0 then
    return jsonb_build_object('result', 'empty_cart');
  end if;

  -- Líneas: el precio sale SIEMPRE de dishes + dish_options.
  for v_line in select * from jsonb_array_elements(p_payload -> 'lines') loop
    v_qty := coalesce((v_line ->> 'qty')::int, 0);
    if v_qty <= 0 or v_qty > 50 then
      return jsonb_build_object('result', 'invalid_qty');
    end if;

    select * into v_dish
      from public.dishes
     where id = (v_line ->> 'dish_id')::uuid
       and branch_id = v_branch.id
       and deleted_at is null;
    if not found then
      return jsonb_build_object('result', 'dish_not_found');
    end if;
    if not v_dish.active or v_dish.sold_out then
      return jsonb_build_object('result', 'dish_unavailable', 'dish', v_dish.name);
    end if;
    if v_dish.portion_limit is not null
       and v_dish.sold_today + v_qty > v_dish.portion_limit then
      return jsonb_build_object('result', 'no_portions', 'dish', v_dish.name);
    end if;

    v_unit := v_dish.price;
    v_size := nullif(v_line #>> '{selection,sizeId}', '')::uuid;
    v_side := nullif(v_line #>> '{selection,sideId}', '')::uuid;
    select coalesce(array_agg(distinct x::uuid), '{}')
      into v_extras
      from jsonb_array_elements_text(
        coalesce(v_line #> '{selection,extraIds}', '[]'::jsonb)
      ) x;

    if v_size is not null then
      select price_delta into v_delta
        from public.dish_options
       where id = v_size and dish_id = v_dish.id
         and kind = 'size' and active;
      if not found then
        return jsonb_build_object('result', 'invalid_option', 'dish', v_dish.name);
      end if;
      v_unit := v_unit + v_delta;
    end if;

    if v_side is not null then
      select price_delta into v_delta
        from public.dish_options
       where id = v_side and dish_id = v_dish.id
         and kind = 'side' and active;
      if not found then
        return jsonb_build_object('result', 'invalid_option', 'dish', v_dish.name);
      end if;
      v_unit := v_unit + v_delta;
    end if;

    if cardinality(v_extras) > 0 then
      select count(*), coalesce(sum(price_delta), 0)
        into v_opt_count, v_delta
        from public.dish_options
       where dish_id = v_dish.id and kind = 'extra' and active
         and id = any (v_extras);
      if v_opt_count <> cardinality(v_extras) then
        return jsonb_build_object('result', 'invalid_option', 'dish', v_dish.name);
      end if;
      v_unit := v_unit + v_delta;
    end if;

    v_unit := greatest(0, v_unit);
    v_subtotal := v_subtotal + v_unit * v_qty;
    v_prep := greatest(v_prep, v_dish.prep_min);

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'dish_id', v_dish.id,
      'name', v_dish.name,
      'emoji', v_dish.emoji,
      'qty', v_qty,
      'unit_price', v_unit,
      'selection', coalesce(v_line -> 'selection', '{}'::jsonb),
      'detail', left(coalesce(v_line ->> 'detail', ''), 200),
      'note', left(coalesce(v_line ->> 'note', ''), 300)
    ));
  end loop;

  -- Descuento de campus (espejo de campusDiscount en pricing.dart).
  if v_branch.campus_id is not null
     and v_branch.student_discount > 0
     and v_profile.verified
     and v_profile.university_id = v_branch.campus_id then
    v_campus := round(v_subtotal * v_branch.student_discount)::int;
  end if;

  -- Tarifa de entrega (espejo de deliveryFee en pricing.dart).
  v_fee := case
    when v_branch.campus_id is not null
         and v_branch.campus_id = v_point.campus_id then 1500
    else 3500
  end;

  -- Cupón: debe ser del usuario, estar vigente y sin usar.
  if v_coupon_id is not null then
    select c.* into v_coupon
      from public.user_coupons uc
      join public.coupons c on c.id = uc.coupon_id
     where uc.user_id = v_uid
       and uc.coupon_id = v_coupon_id
       and uc.used_at is null
       and c.active
       and c.valid_from <= now()
       and (c.valid_until is null or c.valid_until > now())
       and (c.max_uses is null or c.used_count < c.max_uses)
     for update of uc;
    if not found then
      return jsonb_build_object('result', 'coupon_unavailable');
    end if;
    v_coupon_disc := case v_coupon.kind
      when 'free_delivery' then v_fee
      else least(v_coupon.amount, greatest(0, v_subtotal - v_campus))
    end;
  end if;

  -- Gotas (1 Gota = $10): no más que el saldo ni que lo que falta por pagar.
  v_payable := greatest(0, v_subtotal - v_campus - v_coupon_disc);
  if v_gotas < 0 or v_gotas > v_profile.gotas then
    return jsonb_build_object('result', 'insufficient_gotas');
  end if;
  if v_gotas > v_payable / 10 then
    return jsonb_build_object('result', 'invalid_gotas');
  end if;

  -- Propina: hasta 20 % del subtotal.
  if v_tip < 0 or v_tip > (ceil(v_subtotal * 0.2 / 100) * 100)::int then
    return jsonb_build_object('result', 'invalid_tip');
  end if;

  v_total := greatest(
    0, v_subtotal - v_campus - v_coupon_disc - v_gotas * 10 + v_fee + v_tip
  );

  -- Lo que el comprador vio debe ser lo que se cobra.
  if (p_payload ->> 'subtotal') is not null
     and (p_payload ->> 'subtotal')::int <> v_subtotal then
    return jsonb_build_object(
      'result', 'subtotal_mismatch', 'expected', v_subtotal
    );
  end if;
  if (p_payload ->> 'total') is not null
     and (p_payload ->> 'total')::int <> v_total then
    return jsonb_build_object(
      'result', 'total_mismatch',
      'expected', v_total,
      'breakdown', jsonb_build_object(
        'subtotal', v_subtotal, 'campus_discount', v_campus,
        'coupon_discount', v_coupon_disc, 'delivery_fee', v_fee,
        'gotas_used', v_gotas, 'tip', v_tip
      )
    );
  end if;

  -- Tiempos y pago al repartidor (espejo de etaMinutes / courierPayFor).
  v_prep := case when v_prep = 0 then v_branch.prep_min else v_prep end;
  v_eta := v_prep + round(v_km * 4)::int + 5;
  v_pay := greatest(4500, (round((3500 + v_km * 1500) / 100)::int) * 100);

  v_delivery := (1000 + floor(random() * 9000))::int::text;
  v_pickup := (1000 + floor(random() * 9000))::int::text;

  insert into public.orders (
    buyer_id, buyer_name, branch_id, restaurant_name, address_snapshot,
    point_id, payment_method, subtotal, campus_discount, coupon_discount,
    delivery_fee, gotas_used, tip, total, eta_min, courier_pay, distance_km,
    delivery_code, pickup_code, restaurant_note, scheduled_for, coupon_id,
    client_key
  ) values (
    v_uid,
    v_profile.full_name,
    v_branch.id,
    v_branch.name,
    jsonb_build_object(
      'id', v_addr.id,
      'label', v_addr.label,
      'line', v_addr.line,
      'details', v_addr.details,
      'neighborhood', v_addr.neighborhood,
      'reference', v_addr.reference,
      'point_id', v_addr.point_id
    ),
    v_addr.point_id,
    v_payment,
    v_subtotal, v_campus, v_coupon_disc, v_fee, v_gotas, v_tip, v_total,
    v_eta, v_pay, v_km,
    '', v_pickup,
    left(coalesce(p_payload ->> 'restaurant_note', ''), 300),
    nullif(p_payload ->> 'scheduled_for', '')::timestamptz,
    v_coupon_id,
    v_key
  )
  returning * into v_order;

  insert into public.order_secrets (order_id, buyer_id, delivery_code)
  values (v_order.id, v_uid, v_delivery);

  insert into public.order_items (
    order_id, dish_id, name, emoji, qty, unit_price, selection, detail, note
  )
  select v_order.id,
         (i ->> 'dish_id')::uuid,
         i ->> 'name',
         i ->> 'emoji',
         (i ->> 'qty')::int,
         (i ->> 'unit_price')::int,
         i -> 'selection',
         i ->> 'detail',
         i ->> 'note'
    from jsonb_array_elements(v_items) i;

  perform public.order_event(v_order.id, 'pending', 'Comprador', null);

  if v_gotas > 0 then
    perform public.credit_gotas(
      v_uid, -v_gotas, 'Usadas en ' || v_order.code, v_order.id
    );
  end if;

  if v_coupon_id is not null then
    update public.user_coupons
       set used_at = now()
     where user_id = v_uid and coupon_id = v_coupon_id;
    update public.coupons
       set used_count = used_count + 1
     where id = v_coupon_id;
  end if;

  return jsonb_build_object(
    'result', 'ok',
    'order', to_jsonb(v_order) || jsonb_build_object('delivery_code', v_delivery)
  );

exception
  when unique_violation then
    -- Carrera con otro intento de la misma clave: devuelve el ganador.
    select * into v_existing
      from public.orders
     where buyer_id = v_uid and client_key = v_key;
    if found then
      return jsonb_build_object(
        'result', 'ok', 'duplicate', true,
        'order', public.order_json(v_existing)
      );
    end if;
    return jsonb_build_object('result', 'invalid_payload');
  when invalid_text_representation
     or numeric_value_out_of_range
     or invalid_parameter_value
     or invalid_datetime_format
     or datetime_field_overflow
     or null_value_not_allowed then
    return jsonb_build_object('result', 'invalid_payload');
end;
$$;

-- ------------------------------------------------------ 6. Acciones por rol

create or replace function public.restaurant_accept(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.orders;
begin
  select * into v from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if not public.is_my_branch(v.branch_id) then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v.status <> 'pending' then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  update public.orders
     set status = 'preparing', accepted_at = now()
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'preparing', 'Restaurante', 'pending');
  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

create or replace function public.restaurant_reject(p_order uuid, p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.orders;
  v_reason text := left(
    coalesce(nullif(trim(p_reason), ''), 'Rechazado por el restaurante'), 300
  );
begin
  select * into v from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if not public.is_my_branch(v.branch_id) then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v.status <> 'pending' then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  update public.orders
     set status = 'cancelled',
         reject_reason = v_reason,
         cancelled_at = now()
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'cancelled', 'Restaurante', 'pending');
  perform public.refund_order(v);

  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

create or replace function public.restaurant_ready(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.orders;
begin
  select * into v from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if not public.is_my_branch(v.branch_id) then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v.status <> 'preparing' then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  update public.orders
     set status = 'ready', ready_at = now()
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'ready', 'Restaurante', 'preparing');
  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

create or replace function public.buyer_cancel(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.orders;
begin
  select * into v from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v.buyer_id is distinct from auth.uid() then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v.status <> 'pending' then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  update public.orders
     set status = 'cancelled',
         reject_reason = 'Cancelado por el comprador',
         cancelled_at = now()
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'cancelled', 'Comprador', 'pending');
  perform public.refund_order(v);

  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

create or replace function public.courier_accept(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.orders;
  v_cp public.courier_profiles;
  v_branch public.branches;
begin
  -- Bloquea al repartidor: no puede aceptar dos pedidos a la vez.
  select * into v_cp
    from public.courier_profiles
   where user_id = auth.uid()
   for update;
  if not found then
    return jsonb_build_object('result', 'forbidden');
  end if;

  if exists (
    select 1 from public.orders
     where courier_id = auth.uid() and status in ('ready', 'on_the_way')
  ) then
    return jsonb_build_object('result', 'busy');
  end if;

  -- Bloquea el pedido: si dos repartidores llegan juntos, el segundo espera
  -- aquí y luego ve `courier_id` ya asignado.
  select * into v from public.orders where id = p_order for update;
  if not found or v.status <> 'ready' then
    return jsonb_build_object('result', 'not_available');
  end if;
  if v.courier_id is not null then
    return jsonb_build_object('result', 'already_assigned');
  end if;
  if v.distance_km > public.vehicle_max_km(v_cp.vehicle) then
    return jsonb_build_object('result', 'out_of_range');
  end if;

  if v_cp.zone = 'campus' then
    select * into v_branch from public.branches where id = v.branch_id;
    if v_cp.university_id is null
       or v_branch.campus_id is distinct from v_cp.university_id then
      return jsonb_build_object('result', 'out_of_zone');
    end if;
  end if;

  if exists (
    select 1 from public.order_declines d
     where d.order_id = p_order and d.courier_id = auth.uid()
  ) then
    return jsonb_build_object('result', 'declined_before');
  end if;

  -- El estado sigue en 'ready': el pedido se recoge en courier_pickup.
  update public.orders
     set courier_id = auth.uid(), courier_name = v_cp.full_name
   where id = p_order and courier_id is null and status = 'ready'
   returning * into v;
  if not found then
    return jsonb_build_object('result', 'already_assigned');
  end if;

  perform public.order_event(v.id, 'ready', 'Repartidor', 'ready');
  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

create or replace function public.courier_decline(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_courier() then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if not exists (
    select 1 from public.orders
     where id = p_order and status = 'ready' and courier_id is null
  ) then
    return jsonb_build_object('result', 'not_available');
  end if;

  insert into public.order_declines (order_id, courier_id)
  values (p_order, auth.uid())
  on conflict do nothing;
  return jsonb_build_object('result', 'ok');
end;
$$;

create or replace function public.courier_pickup(p_order uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v public.orders;
begin
  select * into v from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v.courier_id is distinct from auth.uid() then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v.status <> 'ready' then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  update public.orders
     set status = 'on_the_way', picked_up_at = now()
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'on_the_way', 'Repartidor', 'ready');
  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

create or replace function public.courier_deliver(
  p_order uuid,
  p_code text,
  p_evidence text
) returns jsonb
language plpgsql
security definer
set search_path = public, storage
as $$
declare
  v public.orders;
  v_secret text;
  v_earned int;
begin
  select * into v from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v.courier_id is distinct from auth.uid() then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v.status <> 'on_the_way' then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  select delivery_code into v_secret
    from public.order_secrets where order_id = p_order;
  if v_secret is null or v_secret <> trim(coalesce(p_code, '')) then
    return jsonb_build_object('result', 'wrong_code');
  end if;

  -- La foto debe existir de verdad en la carpeta de ESTE pedido.
  if coalesce(trim(p_evidence), '') = ''
     or left(p_evidence, length(p_order::text) + 1) <> p_order::text || '/'
     or not exists (
       select 1 from storage.objects o
        where o.bucket_id = 'delivery-evidence' and o.name = p_evidence
     ) then
    return jsonb_build_object('result', 'missing_evidence');
  end if;

  update public.orders
     set status = 'delivered',
         evidence_url = p_evidence,
         delivered_at = now(),
         gotas_credited = true
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'delivered', 'Repartidor', 'on_the_way');

  v_earned := v.subtotal / 1000;
  if v_earned > 0 then
    perform public.credit_gotas(
      v.buyer_id, v_earned, 'Pedido ' || v.code || ' entregado', v.id
    );
  end if;

  update public.courier_profiles
     set deliveries_total = deliveries_total + 1
   where user_id = auth.uid();

  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

-- --------------------------------------------------- 7. Evidencia (Storage)

update storage.buckets
   set file_size_limit = 5242880,
       allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id = 'delivery-evidence';

-- Solo el repartidor asignado, y solo mientras el pedido va en camino.
drop policy if exists delivery_evidence_insert on storage.objects;
create policy delivery_evidence_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'delivery-evidence'
    and exists (
      select 1 from public.orders o
       where o.id = public.try_uuid((storage.foldername(name))[1])
         and o.courier_id = auth.uid()
         and o.status = 'on_the_way'
    )
  );

-- ------------------------------ 8. Las ofertas solo las ven los repartidores
-- Antes cualquier usuario autenticado veía los pedidos «listos sin repartidor»
-- (con nombre y dirección del comprador).

create or replace function public.can_read_order(p_order uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.orders o
    where o.id = p_order
      and (
        o.buyer_id = auth.uid()
        or o.courier_id = auth.uid()
        or public.is_my_branch(o.branch_id)
        or (o.status = 'ready' and o.courier_id is null and public.is_courier())
      )
  )
$$;

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
  for select to authenticated
  using (
    buyer_id = auth.uid()
    or courier_id = auth.uid()
    or public.is_my_branch(branch_id)
    or (status = 'ready' and courier_id is null and public.is_courier())
  );

-- ------------------------------------- 9. Escrituras solo por RPC (defensa)

revoke insert, update, delete, truncate
  on public.orders, public.order_items, public.order_events,
     public.order_declines, public.order_secrets
  from authenticated, anon;

revoke all on public.order_secrets from anon;
grant select on public.order_secrets to authenticated;

-- Las funciones internas no se exponen como RPC públicas.
revoke execute on function public.refund_order(public.orders) from public, anon, authenticated;
revoke execute on function public.order_json(public.orders) from public, anon, authenticated;
revoke execute on function public.credit_gotas(uuid, int, text, uuid) from public, anon, authenticated;
revoke execute on function public.order_event(uuid, public.order_status, text, public.order_status) from public, anon, authenticated;
