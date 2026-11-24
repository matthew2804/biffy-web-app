-- ============================================================================
-- 0026 · Pagos con pasarela (Wompi) + efectivo con billete
-- ============================================================================
-- Reglas que implementa esta migración:
--   * El pedido nace con `payment_status = 'pending'` si el método es online y
--     `'approved'` si es efectivo.
--   * El restaurante NO ve ni acepta un pedido hasta que el pago esté aprobado.
--   * Un rechazo no cancela el pedido: el comprador vuelve al carrito y
--     reintenta. Al vencer `payment_expires_at` sí se cancela y se devuelven
--     Gotas y cupón.
--   * `payments` es una fila por intento (auditoría) y `payment_events` guarda
--     cada webhook con idempotencia por `event_id`.
--   * El efectivo guarda con cuánto paga el comprador y las vueltas.
-- ============================================================================

-- ------------------------------------------------------------------ 1. Tipos
do $t$
begin
  create type public.payment_status as enum
    ('pending', 'processing', 'approved', 'rejected', 'expired', 'refunded');
exception when duplicate_object then null;
end $t$;

-- ----------------------------------------------------------------- 2. Tablas
create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  branch_id uuid not null references public.branches (id) on delete restrict,
  attempt int not null default 1,
  amount int not null check (amount >= 0),
  currency text not null default 'COP',
  method text not null
    check (method in ('nequi', 'daviplata', 'card', 'pse', 'cash')),
  status public.payment_status not null default 'pending',
  provider text not null default 'wompi',
  reference text not null unique,
  checkout_url text,
  provider_transaction_id text unique,
  status_detail text,
  idempotency_key text not null,
  refund_external_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  approved_at timestamptz,
  rejected_at timestamptz,
  expired_at timestamptz,
  refunded_at timestamptz,
  refund_amount int not null default 0,
  refund_reason text,
  unique (order_id, attempt)
);

create table if not exists public.payment_events (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid references public.payments (id) on delete cascade,
  event_id text not null unique,
  request_id text,
  signature_valid boolean not null default false,
  result text not null default '',
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.orders
  add column if not exists payment_status public.payment_status not null
    default 'pending',
  add column if not exists payment_expires_at timestamptz,
  add column if not exists cash_tendered int,
  add column if not exists cash_change int;

-- Los pedidos anteriores a la pasarela ya estaban pagados/simulados.
update public.orders
   set payment_status = 'approved'
 where payment_status = 'pending';

create index if not exists orders_payment_status_idx
  on public.orders (payment_status);
create index if not exists orders_payment_expires_idx
  on public.orders (payment_expires_at)
  where payment_status in ('pending', 'rejected');
create index if not exists payments_order_idx on public.payments (order_id);
create index if not exists payments_buyer_idx
  on public.payments (buyer_id, created_at desc);
create index if not exists payments_branch_idx on public.payments (branch_id);
create index if not exists payments_status_idx on public.payments (status);
create index if not exists payment_events_payment_idx
  on public.payment_events (payment_id);

-- ------------------------------------------------------------------- 3. RLS
alter table public.payments enable row level security;
alter table public.payment_events enable row level security;

drop policy if exists payments_read on public.payments;
create policy payments_read on public.payments
  for select to authenticated
  using (
    buyer_id = auth.uid()
    or (public.is_my_branch(branch_id) and status = 'approved')
  );

revoke insert, update, delete, truncate on public.payments
  from authenticated, anon;
revoke all on public.payment_events from authenticated, anon;
grant select on public.payments to authenticated;

-- ------------------------------------- 4. Reembolso: Gotas, cupón y pago
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

  -- Registra el reembolso del dinero (lo ejecuta la Edge Function con Wompi).
  update public.payments
     set status = 'refunded',
         refunded_at = coalesce(refunded_at, now()),
         refund_amount = p_order.total,
         refund_reason = coalesce(
           nullif(refund_reason, ''),
           'Cancelación de ' || p_order.code
         ),
         updated_at = now()
   where order_id = p_order.id
     and status = 'approved';

  update public.orders
     set payment_status = 'refunded'
   where id = p_order.id
     and payment_status = 'approved';
end;
$$;

-- ---------------------------------------------------------------- 5. Pedidos
-- Se reemplaza `place_order` de 0025 para que fije el estado del pago y el
-- efectivo con billete. El resto de la lógica (precios, Gotas, cupón, campus,
-- distancia) es idéntica.
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
  v_cash_tendered int := nullif(p_payload ->> 'cash_tendered', '')::int;
  v_cash_change int;
  v_payment_status public.payment_status;
  v_payment_expires timestamptz;
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
     and public.is_verified_student(v_uid)
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

  -- Pago: efectivo aprobado sin pasarela; online queda pendiente.
  if v_payment = 'cash' then
    -- Compatibilidad con la app anterior a la pasarela: si no manda billete,
    -- se asume pago exacto.
    if v_cash_tendered is null then
      v_cash_tendered := v_total;
    end if;
    if v_cash_tendered < v_total then
      return jsonb_build_object(
        'result', 'invalid_cash', 'total', v_total
      );
    end if;
    v_cash_change := v_cash_tendered - v_total;
    v_payment_status := 'approved';
    v_payment_expires := null;
  else
    v_cash_change := null;
    v_payment_status := 'pending';
    v_payment_expires := now() + interval '30 minutes';
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
    client_key, payment_status, payment_expires_at, cash_tendered, cash_change
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
    v_key,
    v_payment_status, v_payment_expires, v_cash_tendered, v_cash_change
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

  -- El efectivo también deja registro auditable en `payments`.
  if v_payment = 'cash' then
    insert into public.payments (
      order_id, buyer_id, branch_id, attempt, amount, method, status,
      provider, reference, approved_at, idempotency_key
    ) values (
      v_order.id, v_uid, v_branch.id, 1, v_total, 'cash', 'approved',
      'cash', v_order.code || '-cash', now(),
      coalesce(v_key, v_order.code || '-cash')
    );
  end if;

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

-- ------------------------------------------- 6. Solo se acepta si está pagado
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
  if v.payment_status <> 'approved' then
    return jsonb_build_object('result', 'payment_pending');
  end if;

  update public.orders
     set status = 'preparing', accepted_at = now()
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'preparing', 'Restaurante', 'pending');
  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v));
end;
$$;

-- --------------------------------- 7. Visibilidad: pagado (o reembolsado)
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
        or (
          public.is_my_branch(o.branch_id)
          and o.payment_status in ('approved', 'refunded')
        )
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
    or (
      public.is_my_branch(branch_id)
      and payment_status in ('approved', 'refunded')
    )
    or (status = 'ready' and courier_id is null and public.is_courier())
  );

-- --------------------------- 8. Notificaciones: no avisar sin pago aprobado
create or replace function public.notify_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders;
  v_business uuid;
  v_owner uuid;
  v_items text;
  v_buyer_route text;
  v_biz_audience text;
  c record;
begin
  select * into o from public.orders where id = new.order_id;
  if not found then
    return new;
  end if;

  select b.business_id, bz.owner_id into v_business, v_owner
    from public.branches b
    join public.businesses bz on bz.id = b.business_id
   where b.id = o.branch_id;

  select string_agg(i.qty || '× ' || i.name, ', ' order by i.name)
    into v_items
    from public.order_items i
   where i.order_id = o.id;

  v_buyer_route := '/pedido/' || o.code;
  v_biz_audience := 'business:' || v_business;

  if new.status = 'pending' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido ' || o.code || ' creado',
      'Esperando que ' || o.restaurant_name || ' lo acepte.',
      v_buyer_route, o.id);
    -- El restaurante solo se entera cuando el pago está aprobado.
    if o.payment_status = 'approved' then
      perform public.notify(v_owner, 'restaurant', v_biz_audience,
        'Nuevo pedido ' || o.code,
        coalesce(v_items, ''),
        '/negocio/pedidos', o.id);
    end if;

  elsif new.status = 'preparing' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido en preparación 👩‍🍳',
      o.restaurant_name || ' aceptó tu pedido ' || o.code || '.',
      v_buyer_route, o.id);

  elsif new.status = 'cancelled' and new.actor_label = 'Comprador' then
    if o.payment_status in ('approved', 'refunded') then
      perform public.notify(v_owner, 'restaurant', v_biz_audience,
        'Pedido ' || o.code || ' cancelado por el cliente',
        coalesce(v_items, ''),
        '/negocio/pedidos', o.id);
    end if;

  elsif new.status = 'cancelled' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido ' || o.code || ' rechazado',
      'Motivo: ' || coalesce(nullif(o.reject_reason, ''), 'sin motivo') || '. ' ||
        case
          when o.payment_status in ('approved', 'refunded')
            then 'El pago se reembolsará.'
          else 'No se realizó ningún cobro.'
        end,
      v_buyer_route, o.id);

  elsif new.status = 'ready' and new.actor_label = 'Repartidor' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Repartidor asignado 🛵',
      coalesce(o.courier_name, 'Un repartidor') || ' recogerá tu pedido ' || o.code || '.',
      v_buyer_route, o.id);
    perform public.notify(v_owner, 'restaurant', v_biz_audience,
      'Repartidor asignado a ' || o.code,
      coalesce(o.courier_name, 'El repartidor') || ' va en camino a recoger.',
      '/negocio/pedidos', o.id);
    perform public.notify(o.courier_id, 'courier', 'courier:' || o.courier_id,
      'Pedido ' || o.code || ' asignado',
      'Ve a ' || o.restaurant_name || case
        when coalesce(o.pickup_code, '') = '' then ' a recoger el pedido.'
        else ' y muestra el código ' || o.pickup_code || '.'
      end,
      '/repartidor/recogida/' || o.code, o.id);
    update public.notifications
       set read_at = now()
     where order_id = o.id
       and role = 'courier'
       and user_id is distinct from o.courier_id
       and read_at is null;

  elsif new.status = 'ready' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido listo 🛍️',
      'Tu pedido ' || o.code || ' está listo. Buscando repartidor.',
      v_buyer_route, o.id);
    for c in
      select cp.user_id
        from public.courier_profiles cp
       where cp.online
         and o.distance_km <= public.vehicle_max_km(cp.vehicle)
         and not exists (
           select 1 from public.orders x
            where x.courier_id = cp.user_id
              and x.status in ('ready', 'on_the_way')
         )
    loop
      perform public.notify(c.user_id, 'courier', 'courier:' || c.user_id,
        'Oferta disponible · ' || public.cop(o.courier_pay + o.tip),
        o.restaurant_name || ' → ' || coalesce(o.address_snapshot ->> 'label', 'entrega')
          || ' (' || o.distance_km || ' km).',
        '/repartidor/oferta/' || o.code, o.id);
    end loop;

  elsif new.status = 'on_the_way' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido en camino 🛵',
      coalesce(o.courier_name, 'Tu repartidor') || ' va en camino con tu pedido ' || o.code || '.',
      v_buyer_route, o.id);

  elsif new.status = 'delivered' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido entregado ✅',
      '¡Buen provecho! Ganaste ' || (o.subtotal / 1000) || ' Gotas con ' || o.code || '.',
      v_buyer_route, o.id);
    perform public.notify(v_owner, 'restaurant', v_biz_audience,
      'Pedido ' || o.code || ' entregado',
      'Entregado por ' || coalesce(o.courier_name, 'el repartidor') || '.',
      '/negocio/pedidos', o.id);
  end if;

  return new;
end;
$$;

drop trigger if exists order_events_notify on public.order_events;
create trigger order_events_notify
  after insert on public.order_events
  for each row execute function public.notify_order_event();

-- ------------------------------------------------------- 9. RPC de pagos
-- Inicia (o reutiliza) un intento de pago online. Solo service_role.
create or replace function public.payment_begin(
  p_order uuid,
  p_buyer uuid,
  p_method text,
  p_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_payment public.payments;
  v_attempt int;
  v_ref text;
begin
  select * into v_order from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_order.buyer_id <> p_buyer then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v_order.payment_status = 'approved' then
    return jsonb_build_object('result', 'already_paid');
  end if;
  if v_order.status <> 'pending' then
    return jsonb_build_object('result', 'invalid_state');
  end if;
  if p_method not in ('nequi', 'daviplata', 'card', 'pse') then
    return jsonb_build_object('result', 'invalid_method');
  end if;
  if v_order.payment_expires_at is not null
     and v_order.payment_expires_at < now() then
    return jsonb_build_object('result', 'expired');
  end if;

  -- Reutiliza el intento pendiente: un corte de red no cobra dos veces.
  select * into v_payment
    from public.payments
   where order_id = p_order
     and status in ('pending', 'processing')
   order by attempt desc
   limit 1;
  if found then
    return jsonb_build_object(
      'result', 'ok',
      'payment_id', v_payment.id,
      'amount', v_payment.amount,
      'attempt', v_payment.attempt,
      'reference', v_payment.reference,
      'checkout_url', v_payment.checkout_url
    );
  end if;

  select coalesce(max(attempt), 0) + 1 into v_attempt
    from public.payments where order_id = p_order;
  v_ref := v_order.code || '-' || v_attempt || '-' ||
    substr(replace(gen_random_uuid()::text, '-', ''), 1, 10);

  insert into public.payments (
    order_id, buyer_id, branch_id, attempt, amount, method, status,
    provider, reference, idempotency_key
  ) values (
    p_order, p_buyer, v_order.branch_id, v_attempt, v_order.total, p_method,
    'pending', 'wompi', v_ref, coalesce(nullif(p_key, ''), v_ref)
  )
  returning * into v_payment;

  update public.orders
     set payment_status = 'pending',
         payment_method = p_method,
         payment_expires_at = coalesce(
           payment_expires_at, now() + interval '30 minutes'
         )
   where id = p_order;

  return jsonb_build_object(
    'result', 'ok',
    'payment_id', v_payment.id,
    'amount', v_payment.amount,
    'attempt', v_payment.attempt,
    'reference', v_payment.reference,
    'checkout_url', v_payment.checkout_url
  );
end;
$$;

-- Guarda la URL de checkout que construyó la Edge Function.
create or replace function public.payment_set_checkout(
  p_payment uuid,
  p_url text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.payments
     set checkout_url = p_url,
         updated_at = now()
   where id = p_payment;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  return jsonb_build_object('result', 'ok');
end;
$$;

-- Aplica el estado que confirmó Wompi. Idempotente.
create or replace function public.payment_apply(
  p_payment uuid,
  p_status public.payment_status,
  p_tx_id text default null,
  p_detail text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments;
  v_order public.orders;
  v_business uuid;
  v_owner uuid;
  v_items text;
begin
  select * into v_payment from public.payments where id = p_payment for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  -- Mismo estado (o repetido): no se vuelve a procesar.
  if v_payment.status = p_status
     and (p_tx_id is null or v_payment.provider_transaction_id = p_tx_id) then
    return jsonb_build_object('result', 'duplicate', 'status', v_payment.status);
  end if;

  if not (
    (v_payment.status in ('pending', 'processing')
      and p_status in ('approved', 'rejected', 'expired', 'refunded'))
    or (v_payment.status = 'approved' and p_status = 'refunded')
  ) then
    return jsonb_build_object(
      'result', 'invalid_state',
      'from', v_payment.status,
      'to', p_status
    );
  end if;

  select * into v_order
    from public.orders where id = v_payment.order_id for update;
  if not found then
    return jsonb_build_object('result', 'order_not_found');
  end if;

  -- Llegó aprobado pero el pedido ya se había cancelado: hay que reembolsar.
  if p_status = 'approved' and v_order.status <> 'pending' then
    update public.payments
       set status = 'refunded',
           refunded_at = now(),
           refund_amount = v_payment.amount,
           refund_reason = 'El pedido ya estaba cancelado',
           updated_at = now()
     where id = p_payment;
    return jsonb_build_object('result', 'refund_required');
  end if;

  update public.payments
     set status = p_status,
         provider_transaction_id = coalesce(p_tx_id, provider_transaction_id),
         status_detail = coalesce(p_detail, status_detail),
         updated_at = now(),
         approved_at = case when p_status = 'approved'
                            then coalesce(approved_at, now()) else approved_at end,
         rejected_at = case when p_status = 'rejected'
                            then coalesce(rejected_at, now()) else rejected_at end,
         expired_at = case when p_status = 'expired'
                           then coalesce(expired_at, now()) else expired_at end,
         refunded_at = case when p_status = 'refunded'
                            then coalesce(refunded_at, now()) else refunded_at end
   where id = p_payment;

  if p_status = 'approved' then
    update public.orders
       set payment_status = 'approved',
           payment_expires_at = null
     where id = v_order.id
     returning * into v_order;

    select b.business_id, bz.owner_id into v_business, v_owner
      from public.branches b
      join public.businesses bz on bz.id = b.business_id
     where b.id = v_order.branch_id;
    select string_agg(i.qty || '× ' || i.name, ', ' order by i.name)
      into v_items
      from public.order_items i
     where i.order_id = v_order.id;

    perform public.notify(v_owner, 'restaurant', 'business:' || v_business,
      'Nuevo pedido ' || v_order.code || ' pagado',
      coalesce(v_items, '') || ' · Pago aprobado',
      '/negocio/pedidos', v_order.id);
    perform public.notify(v_order.buyer_id, 'buyer', 'user:' || v_order.buyer_id,
      'Pago aprobado ✅',
      'Tu pedido ' || v_order.code || ' ya está con ' || v_order.restaurant_name || '.',
      '/pedido/' || v_order.code, v_order.id);

  elsif p_status = 'rejected' then
    update public.orders
       set payment_status = 'rejected'
     where id = v_order.id;
    perform public.notify(v_order.buyer_id, 'buyer', 'user:' || v_order.buyer_id,
      'Pago rechazado',
      coalesce(nullif(p_detail, ''), 'El pago no se pudo completar') ||
        '. Puedes intentarlo de nuevo.',
      '/pedido/' || v_order.code, v_order.id);

  elsif p_status = 'expired' then
    -- Si otro intento ya está aprobado, no se cancela.
    if exists (
      select 1 from public.payments p
       where p.order_id = v_order.id and p.status = 'approved'
    ) then
      return jsonb_build_object('result', 'already_paid');
    end if;
    update public.orders
       set status = 'cancelled',
           reject_reason = 'El pago venció',
           cancelled_at = now(),
           payment_status = 'expired'
     where id = v_order.id
     returning * into v_order;
    perform public.order_event(v_order.id, 'cancelled', 'Pasarela', 'pending');
    perform public.refund_order(v_order);

  elsif p_status = 'refunded' then
    update public.orders
       set payment_status = 'refunded'
     where id = v_order.id;
  end if;

  select * into v_order from public.orders where id = v_payment.order_id;
  return jsonb_build_object(
    'result', 'ok',
    'status', p_status,
    'order_status', v_order.status,
    'payment_status', v_order.payment_status
  );
end;
$$;

-- Registra el reembolso del dinero (lo confirma la Edge Function).
create or replace function public.payment_refund(
  p_order uuid,
  p_reason text,
  p_external_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.payments
     set status = 'refunded',
         refunded_at = coalesce(refunded_at, now()),
         refund_amount = amount,
         refund_reason = coalesce(nullif(p_reason, ''), 'Reembolso'),
         refund_external_id = coalesce(p_external_id, refund_external_id),
         updated_at = now()
   where order_id = p_order
     and status in ('approved', 'refunded');
  update public.orders
     set payment_status = 'refunded'
   where id = p_order and payment_status in ('approved', 'refunded');
  return jsonb_build_object('result', 'ok');
end;
$$;

-- Cancela los pedidos cuyo pago no se aprobó dentro de la ventana.
create or replace function public.expire_pending_payments()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_count int := 0;
begin
  for v_order in
    select o.*
      from public.orders o
     where o.payment_status in ('pending', 'rejected')
       and o.status = 'pending'
       and o.payment_expires_at is not null
       and o.payment_expires_at < now()
       and not exists (
         select 1 from public.payments p
          where p.order_id = o.id and p.status = 'approved'
       )
     for update
  loop
    update public.payments
       set status = 'expired',
           expired_at = coalesce(expired_at, now()),
           updated_at = now()
     where order_id = v_order.id
       and status in ('pending', 'processing', 'rejected');
    update public.orders
       set status = 'cancelled',
           reject_reason = 'El pago venció',
           cancelled_at = now(),
           payment_status = 'expired'
     where id = v_order.id
     returning * into v_order;
    perform public.order_event(v_order.id, 'cancelled', 'Pasarela', 'pending');
    perform public.refund_order(v_order);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- Último intento de pago del pedido, para la app.
create or replace function public.payment_for_order(p_order uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_payment public.payments;
begin
  if not exists (
    select 1 from public.orders o
     where o.id = p_order
       and (o.buyer_id = auth.uid() or public.is_my_branch(o.branch_id))
  ) then
    return jsonb_build_object('result', 'forbidden');
  end if;

  select * into v_payment
    from public.payments
   where order_id = p_order
   order by attempt desc
   limit 1;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  return jsonb_build_object('result', 'ok', 'payment', to_jsonb(v_payment));
end;
$$;

-- ------------------------------------------------------------- 10. Realtime
do $$
begin
  begin
    alter publication supabase_realtime add table public.payments;
  exception
    when duplicate_object then null;
    when undefined_object then null;
  end;
end $$;

-- ------------------------------------ 11. Permisos de las RPC de pagos
revoke execute on function public.payment_begin(uuid, uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.payment_set_checkout(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.payment_apply(
  uuid, public.payment_status, text, text
) from public, anon, authenticated;
revoke execute on function public.payment_refund(uuid, text, text)
  from public, anon, authenticated;
revoke execute on function public.expire_pending_payments()
  from public, anon, authenticated;
grant execute on function public.payment_for_order(uuid) to authenticated;

-- Las escrituras de payments/payment_events solo entran por las RPC de arriba.
revoke insert, update, delete, truncate
  on public.payments, public.payment_events
  from authenticated, anon;
