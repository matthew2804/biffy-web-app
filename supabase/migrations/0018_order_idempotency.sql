-- ============================================================================
-- 0018 · Idempotencia de place_order
-- ============================================================================
-- Un reintento por mala red no puede crear el pedido dos veces. El cliente
-- manda una `client_key` estable por intento (hoy: el id local del pedido).
-- Si esa clave ya existe para el comprador, se devuelve el pedido original.
-- ============================================================================

alter table public.orders
  add column if not exists client_key text;

create unique index if not exists orders_client_key_idx
  on public.orders (client_key)
  where client_key is not null;

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
  v_point_loc geometry;
  v_poly geometry;
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
  v_client_key text;
  v_coupon uuid := nullif(p_payload ->> 'coupon_id', '')::uuid;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select * into v_profile from public.profiles where id = v_uid;
  if not found then
    return jsonb_build_object('result', 'no_profile');
  end if;

  -- Reintento del mismo intento de compra: devolver el pedido ya creado.
  v_client_key := nullif(p_payload ->> 'client_key', '');
  if v_client_key is not null then
    select * into v_order
      from public.orders
     where client_key = v_client_key
       and buyer_id = v_uid;

    if found then
      return jsonb_build_object(
        'result', 'ok',
        'order', to_jsonb(v_order),
        'replayed', true
      );
    end if;
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

  select p.location into v_point_loc
    from public.delivery_points p
   where p.id = v_addr.point_id;

  -- 1) Distancia real (metros) con PostGIS.
  if v_branch.location is not null and v_point_loc is not null then
    if not st_dwithin(
      v_branch.location::geography,
      v_point_loc::geography,
      (v_branch.radius_km * 1000)::float8
    ) then
      return jsonb_build_object(
        'result', 'out_of_range',
        'radius_km', v_branch.radius_km
      );
    end if;
  end if;

  -- 2) Geocerca del campus cuando la sede es solo campus.
  if v_branch.campus_delivery_only then
    select u.boundary_polygon into v_poly
      from public.universities u
     where u.id = v_branch.campus_id;

    if v_poly is not null and v_point_loc is not null then
      if not st_covers(v_poly, v_point_loc) then
        return jsonb_build_object('result', 'outside_campus');
      end if;
    elsif v_branch.campus_id is not null then
      if not exists (
        select 1 from public.delivery_points p
         where p.id = v_addr.point_id
           and p.campus_id = v_branch.campus_id
      ) then
        return jsonb_build_object('result', 'outside_campus');
      end if;
    end if;
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
    delivery_code, restaurant_note, scheduled_for, coupon_id, client_key
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
    v_coupon,
    v_client_key
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

revoke all on function public.place_order(jsonb) from public, anon;
grant execute on function public.place_order(jsonb) to authenticated;
