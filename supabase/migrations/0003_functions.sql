-- ============================================================================
-- 0003 · Funciones de negocio (RPC)
-- ============================================================================
-- Regla: ninguna tabla de pedidos se escribe directo desde el cliente. Todo
-- pasa por estas funciones `security definer`, que validan permisos y estado.
--
-- Las firmas usan un único jsonb para poder crecer sin volver a tocar la base.
-- ============================================================================

-- ------------------------------------------------------- Helpers de permisos

create or replace function public.my_business_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select business_id from public.profiles where id = auth.uid()
$$;

create or replace function public.is_my_branch(p_branch uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.branches b
    join public.businesses bu on bu.id = b.business_id
    where b.id = p_branch
      and bu.owner_id = auth.uid()
  )
$$;

create or replace function public.is_courier()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.courier_profiles where user_id = auth.uid()
  )
$$;

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
        or (o.status = 'ready' and o.courier_id is null)
      )
  )
$$;

-- Distancia máxima por vehículo (espejo de Vehicle.maxKm en Dart).
create or replace function public.vehicle_max_km(p_vehicle public.vehicle_type)
returns numeric
language sql
immutable
as $$
  select case p_vehicle
    when 'moto' then 8
    when 'bicycle' then 4
    when 'scooter' then 3
    else 1.5
  end::numeric
$$;

create or replace function public.order_event(
  p_order uuid,
  p_status public.order_status,
  p_label text
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.order_events (order_id, status, actor_id, actor_label)
  values (p_order, p_status, auth.uid(), p_label)
$$;

-- --------------------------------------------------------------- Gotas

create or replace function public.credit_gotas(
  p_user uuid,
  p_amount int,
  p_reason text,
  p_order uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_amount = 0 then
    return;
  end if;

  perform set_config('biffy.internal', '1', true);

  insert into public.gotas_ledger (user_id, amount, reason, order_id)
  values (p_user, p_amount, p_reason, p_order);

  update public.profiles
     set gotas = greatest(0, gotas + p_amount)
   where id = p_user;

  perform set_config('biffy.internal', '0', true);
end;
$$;

-- ------------------------------------------------- Perfil: alta y protección

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
begin
  v_role := case
    when new.raw_user_meta_data ->> 'role' in ('buyer', 'courier', 'restaurant')
      then (new.raw_user_meta_data ->> 'role')::public.user_role
    else 'buyer'
  end;

  insert into public.profiles (id, email, full_name, phone, role)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.raw_user_meta_data ->> 'phone', ''),
    v_role
  )
  on conflict (id) do nothing;

  insert into public.preferences (user_id) values (new.id)
  on conflict (user_id) do nothing;

  insert into public.app_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Impide que el cliente se suba el rol, las Gotas o la verificación.
create or replace function public.guard_profile_update()
returns trigger
language plpgsql
as $$
begin
  if coalesce(current_setting('biffy.internal', true), '0') = '1' then
    return new;
  end if;

  -- Los scripts de administración (service_role) sí pueden ajustar el perfil.
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;

  if new.role <> old.role then
    raise exception 'El rol no se puede cambiar desde el cliente';
  end if;

  if new.verified <> old.verified then
    raise exception 'La verificación se gestiona con verify_university';
  end if;

  if new.gotas <> old.gotas then
    raise exception 'Las Gotas se gestionan con el libro de movimientos';
  end if;

  if new.business_id is distinct from old.business_id then
    if old.business_id is not null then
      raise exception 'La cuenta ya tiene un negocio asociado';
    end if;
    if new.business_id is not null and not exists (
      select 1 from public.businesses b
      where b.id = new.business_id and b.owner_id = auth.uid()
    ) then
      raise exception 'El negocio no pertenece a la cuenta';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists guard_profile_update on public.profiles;
create trigger guard_profile_update
  before update on public.profiles
  for each row execute function public.guard_profile_update();

-- Verificación universitaria por dominio del correo (reemplaza la simulación).
create or replace function public.verify_university(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uni text := p_payload ->> 'university_id';
  v_email text := lower(coalesce(p_payload ->> 'email', ''));
  v_domain text;
begin
  if auth.uid() is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select domain into v_domain from public.universities where id = v_uni;
  if v_domain is null then
    return jsonb_build_object('result', 'unknown_university');
  end if;

  if v_email not like '%@' || v_domain then
    return jsonb_build_object('result', 'domain_mismatch');
  end if;

  perform set_config('biffy.internal', '1', true);
  update public.profiles
     set university_id = v_uni,
         university_email = v_email,
         verified = true
   where id = auth.uid();
  perform set_config('biffy.internal', '0', true);

  return jsonb_build_object('result', 'ok');
end;
$$;

-- ------------------------------------------------------------ Crear pedido

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
  v_dish public.dishes;
  v_order public.orders;
  v_line jsonb;
  v_qty int;
  v_unit int;
  v_lines_total int := 0;
  v_subtotal int := coalesce((p_payload ->> 'subtotal')::int, -1);
  v_campus int := coalesce((p_payload ->> 'campus_discount')::int, 0);
  v_coupon_disc int := coalesce((p_payload ->> 'coupon_discount')::int, 0);
  v_fee int := coalesce((p_payload ->> 'delivery_fee')::int, 0);
  v_gotas int := coalesce((p_payload ->> 'gotas_used')::int, 0);
  v_tip int := coalesce((p_payload ->> 'tip')::int, 0);
  v_total int := coalesce((p_payload ->> 'total')::int, -1);
  v_expected int;
  v_code text;
  v_coupon uuid := nullif(p_payload ->> 'coupon_id', '')::uuid;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('result', 'no_profile');
  end if;

  select * into v_branch
    from public.branches
   where id = (p_payload ->> 'branch_id')::uuid and deleted_at is null;
  if not found then
    return jsonb_build_object('result', 'branch_not_found');
  end if;

  select * into v_addr
    from public.addresses
   where id = (p_payload ->> 'address_id')::uuid
     and user_id = v_uid
     and deleted_at is null;
  if not found then
    return jsonb_build_object('result', 'address_not_found');
  end if;

  if p_payload -> 'lines' is null
     or jsonb_typeof(p_payload -> 'lines') <> 'array' then
    return jsonb_build_object('result', 'empty_cart');
  end if;

  if jsonb_array_length(p_payload -> 'lines') = 0 then
    return jsonb_build_object('result', 'empty_cart');
  end if;

  for v_line in select * from jsonb_array_elements(p_payload -> 'lines') loop
    v_qty := coalesce((v_line ->> 'qty')::int, 0);
    if v_qty <= 0 then
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

    v_unit := coalesce((v_line ->> 'unit_price')::int, v_dish.price);
    v_lines_total := v_lines_total + v_unit * v_qty;
  end loop;

  if v_subtotal <> v_lines_total then
    return jsonb_build_object(
      'result', 'subtotal_mismatch',
      'expected', v_lines_total
    );
  end if;

  v_expected := v_subtotal - v_campus - v_coupon_disc + v_fee + v_tip - v_gotas * 10;
  if v_total <> v_expected or v_total < 0 then
    return jsonb_build_object('result', 'total_mismatch', 'expected', v_expected);
  end if;

  if v_gotas < 0 or v_gotas > v_profile.gotas then
    return jsonb_build_object('result', 'insufficient_gotas');
  end if;

  if v_coupon is not null then
    if not exists (
      select 1 from public.user_coupons uc
      join public.coupons c on c.id = uc.coupon_id
      where uc.user_id = v_uid
        and uc.coupon_id = v_coupon
        and uc.used_at is null
        and c.active
    ) then
      return jsonb_build_object('result', 'coupon_unavailable');
    end if;
  end if;

  v_code := lpad((nextval('public.delivery_code_seq') % 10000)::text, 4, '0');

  insert into public.orders (
    buyer_id, buyer_name, branch_id, restaurant_name, address_snapshot,
    point_id, payment_method, subtotal, campus_discount, coupon_discount,
    delivery_fee, gotas_used, tip, total, eta_min, courier_pay, distance_km,
    delivery_code, restaurant_note, scheduled_for, coupon_id
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
    p_payload ->> 'payment',
    v_subtotal, v_campus, v_coupon_disc, v_fee, v_gotas, v_tip, v_total,
    coalesce((p_payload ->> 'eta_min')::int, v_branch.prep_min + 10),
    coalesce((p_payload ->> 'courier_pay')::int, 0),
    coalesce((p_payload ->> 'distance_km')::numeric, 0),
    v_code,
    coalesce(p_payload ->> 'restaurant_note', ''),
    nullif(p_payload ->> 'scheduled_for', '')::timestamptz,
    v_coupon
  )
  returning * into v_order;

  insert into public.order_items (
    order_id, dish_id, name, emoji, qty, unit_price, selection, detail, note
  )
  select
    v_order.id,
    (l ->> 'dish_id')::uuid,
    d.name,
    d.emoji,
    (l ->> 'qty')::int,
    coalesce((l ->> 'unit_price')::int, d.price),
    coalesce(l -> 'selection', '{}'::jsonb),
    coalesce(l ->> 'detail', ''),
    coalesce(l ->> 'note', '')
  from jsonb_array_elements(p_payload -> 'lines') l
  join public.dishes d on d.id = (l ->> 'dish_id')::uuid;

  perform public.order_event(v_order.id, 'pending', 'Comprador');

  if v_gotas > 0 then
    perform public.credit_gotas(
      v_uid, -v_gotas, 'Usadas en ' || v_order.code, v_order.id
    );
  end if;

  if v_coupon is not null then
    update public.user_coupons
       set used_at = now()
     where user_id = v_uid and coupon_id = v_coupon;
    update public.coupons
       set used_count = used_count + 1
     where id = v_coupon;
  end if;

  return jsonb_build_object('result', 'ok', 'order', to_jsonb(v_order));
end;
$$;

-- ------------------------------------------------------ Acciones por rol

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

  perform public.order_event(v.id, 'preparing', 'Restaurante');
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
  v_reason text := coalesce(nullif(trim(p_reason), ''), 'Rechazado por el restaurante');
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

  perform public.order_event(v.id, 'cancelled', 'Restaurante');

  if v.gotas_used > 0 then
    perform public.credit_gotas(
      v.buyer_id, v.gotas_used, 'Reembolso de ' || v.code, v.id
    );
  end if;

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

  perform public.order_event(v.id, 'ready', 'Restaurante');
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
  if v.buyer_id <> auth.uid() then
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

  perform public.order_event(v.id, 'cancelled', 'Comprador');

  if v.gotas_used > 0 then
    perform public.credit_gotas(
      v.buyer_id, v.gotas_used, 'Reembolso de ' || v.code, v.id
    );
  end if;

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
begin
  select * into v_cp from public.courier_profiles where user_id = auth.uid();
  if not found then
    return jsonb_build_object('result', 'not_available');
  end if;

  if exists (
    select 1 from public.orders
    where courier_id = auth.uid() and status in ('ready', 'on_the_way')
  ) then
    return jsonb_build_object('result', 'busy');
  end if;

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

  if v.id is null then
    return jsonb_build_object('result', 'already_assigned');
  end if;

  perform public.order_event(v.id, 'ready', 'Repartidor');
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
  if v.status <> 'ready' or v.courier_id is distinct from auth.uid() then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  update public.orders
     set status = 'on_the_way', picked_up_at = now()
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'on_the_way', 'Repartidor');
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
set search_path = public
as $$
declare
  v public.orders;
  v_earned int;
begin
  select * into v from public.orders where id = p_order for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v.status <> 'on_the_way' or v.courier_id is distinct from auth.uid() then
    return jsonb_build_object('result', 'invalid_state');
  end if;
  if v.delivery_code <> trim(coalesce(p_code, '')) then
    return jsonb_build_object('result', 'wrong_code');
  end if;
  if coalesce(trim(p_evidence), '') = '' then
    return jsonb_build_object('result', 'missing_evidence');
  end if;

  update public.orders
     set status = 'delivered',
         evidence_url = p_evidence,
         delivered_at = now(),
         gotas_credited = true
   where id = p_order
   returning * into v;

  perform public.order_event(v.id, 'delivered', 'Repartidor');

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

-- ------------------------------------------------------ Registro de negocio

create or replace function public.register_business(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_business uuid;
  v_branches jsonb := coalesce(p_payload -> 'branches', '[]'::jsonb);
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;
  if jsonb_array_length(v_branches) = 0 then
    return jsonb_build_object('result', 'no_branches');
  end if;

  insert into public.businesses (
    owner_id, brand, legal_name, nit, cuisine, description, owner_name,
    owner_doc, owner_phone, owner_email, bank_name, account_type,
    account_number, legal_docs, nutrition_info
  ) values (
    v_uid,
    coalesce(p_payload ->> 'brand', 'Mi negocio'),
    coalesce(p_payload ->> 'legal_name', ''),
    coalesce(p_payload ->> 'nit', ''),
    coalesce(p_payload ->> 'cuisine', 'almuerzo'),
    coalesce(p_payload ->> 'description', ''),
    coalesce(p_payload ->> 'owner_name', ''),
    coalesce(p_payload ->> 'owner_doc', ''),
    coalesce(p_payload ->> 'owner_phone', ''),
    coalesce(p_payload ->> 'owner_email', ''),
    coalesce(p_payload ->> 'bank_name', ''),
    coalesce(p_payload ->> 'account_type', 'Ahorros'),
    coalesce(p_payload ->> 'account_number', ''),
    coalesce(p_payload -> 'legal_docs', '{}'::jsonb),
    coalesce((p_payload ->> 'nutrition_info')::boolean, false)
  )
  returning id into v_business;

  insert into public.branches (
    business_id, name, branch_name, address, city, lat, lng, radius_km,
    open_hour, close_hour, campus_id, student_discount, emoji, tagline, cuisine
  )
  select
    v_business,
    coalesce(b ->> 'name', 'Sede principal'),
    coalesce(b ->> 'branch_name', 'Sede principal'),
    coalesce(b ->> 'address', ''),
    coalesce(b ->> 'city', ''),
    coalesce((b ->> 'lat')::numeric, 0),
    coalesce((b ->> 'lng')::numeric, 0),
    coalesce((b ->> 'radius_km')::numeric, 3),
    coalesce((b ->> 'open_hour')::int, 8),
    coalesce((b ->> 'close_hour')::int, 22),
    nullif(b ->> 'campus_id', ''),
    coalesce((b ->> 'student_discount')::numeric, 0),
    coalesce(b ->> 'emoji', '🍽️'),
    coalesce(b ->> 'tagline', ''),
    coalesce(p_payload ->> 'cuisine', 'almuerzo')
  from jsonb_array_elements(v_branches) b;

  perform set_config('biffy.internal', '1', true);
  update public.profiles set business_id = v_business where id = v_uid;
  perform set_config('biffy.internal', '0', true);

  return jsonb_build_object('result', 'ok', 'business_id', v_business);
end;
$$;

-- ------------------------------------------------------- Canje de Gotas

create or replace function public.redeem_reward(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_reward public.gotas_rewards;
  v_balance int;
  v_redemption uuid;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select * into v_reward
    from public.gotas_rewards
   where code = p_payload ->> 'code'
     and is_active;
  if not found then
    return jsonb_build_object('result', 'reward_not_found');
  end if;

  -- Bloquea el perfil para que dos canjes simultáneos no gasten de más.
  select gotas into v_balance
    from public.profiles
   where id = v_uid
     for update;

  if v_balance is null then
    return jsonb_build_object('result', 'no_profile');
  end if;

  if v_balance < v_reward.gotas_cost then
    return jsonb_build_object(
      'result', 'insufficient_gotas',
      'balance', v_balance,
      'cost', v_reward.gotas_cost
    );
  end if;

  insert into public.reward_redemptions (user_id, reward_id, gotas_spent)
  values (v_uid, v_reward.id, v_reward.gotas_cost)
  returning id into v_redemption;

  perform public.credit_gotas(
    v_uid, -v_reward.gotas_cost, 'Canje: ' || v_reward.name, null
  );

  return jsonb_build_object(
    'result', 'ok',
    'redemption_id', v_redemption,
    'reward', v_reward.code,
    'balance', v_balance - v_reward.gotas_cost
  );
end;
$$;

-- ---------------------------------------------------------------- Permisos

revoke all on function public.order_event(uuid, public.order_status, text)
  from public, anon, authenticated;
revoke all on function public.credit_gotas(uuid, int, text, uuid) from public, anon;
revoke all on function public.verify_university(jsonb) from public, anon;
revoke all on function public.register_business(jsonb) from public, anon;
revoke all on function public.place_order(jsonb) from public, anon;
revoke all on function public.restaurant_accept(uuid) from public, anon;
revoke all on function public.restaurant_reject(uuid, text) from public, anon;
revoke all on function public.restaurant_ready(uuid) from public, anon;
revoke all on function public.buyer_cancel(uuid) from public, anon;
revoke all on function public.courier_accept(uuid) from public, anon;
revoke all on function public.courier_decline(uuid) from public, anon;
revoke all on function public.courier_pickup(uuid) from public, anon;
revoke all on function public.courier_deliver(uuid, text, text) from public, anon;
revoke all on function public.redeem_reward(jsonb) from public, anon;

grant execute on function public.verify_university(jsonb) to authenticated;
grant execute on function public.register_business(jsonb) to authenticated;
grant execute on function public.place_order(jsonb) to authenticated;
grant execute on function public.restaurant_accept(uuid) to authenticated;
grant execute on function public.restaurant_reject(uuid, text) to authenticated;
grant execute on function public.restaurant_ready(uuid) to authenticated;
grant execute on function public.buyer_cancel(uuid) to authenticated;
grant execute on function public.courier_accept(uuid) to authenticated;
grant execute on function public.courier_decline(uuid) to authenticated;
grant execute on function public.courier_pickup(uuid) to authenticated;
grant execute on function public.courier_deliver(uuid, text, text) to authenticated;
grant execute on function public.redeem_reward(jsonb) to authenticated;
