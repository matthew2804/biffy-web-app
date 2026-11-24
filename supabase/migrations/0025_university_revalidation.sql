-- ============================================================================
-- 0025 · Revalidación del correo institucional (HU-1 ampliada)
-- ============================================================================
-- Opción B: la cuenta puede usar un correo personal; el correo institucional
-- es adicional y solo habilita Campus. Cada 30 días se envía un código al
-- correo institucional. Si no se confirma o el correo rebota, Campus se
-- deshabilita y la cuenta personal sigue funcionando con normalidad.
--
-- El código se genera en `create_university_verification` (solo service_role)
-- y lo envía la Edge Function `send-university-code` con Resend. El cliente
-- nunca recibe el código real: solo lo escribe después de leerlo en su correo.
-- ============================================================================

-- ------------------------------------------------------- Columnas en profiles

alter table public.profiles
  add column if not exists university_status text not null default 'none',
  add column if not exists university_verified_at timestamptz,
  add column if not exists university_expires_at timestamptz;

do $$ begin
  alter table public.profiles
    add constraint profiles_university_status_check
    check (university_status in ('none', 'pending', 'active', 'inactive'));
exception when duplicate_object then null; end $$;

-- Migración de los usuarios que ya estaban verificados: se les da un ciclo
-- de 30 días desde la aplicación de esta migración.
update public.profiles
   set university_status = 'active',
       university_verified_at = coalesce(university_verified_at, now()),
       university_expires_at = coalesce(
         university_expires_at, now() + interval '30 days'
       )
 where verified
   and university_id is not null
   and university_email is not null;

-- ------------------------------------------------- Tabla de verificaciones

create table if not exists public.university_verifications (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  university_id text not null references public.universities (id),
  email text not null,
  status text not null default 'pending'
    check (status in ('pending', 'active', 'inactive')),
  token_hash text,
  token_expires_at timestamptz,
  attempts int not null default 0,
  last_sent_at timestamptz not null default now(),
  verified_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoke_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.university_verifications enable row level security;

drop policy if exists university_verifications_owner
  on public.university_verifications;
create policy university_verifications_owner
  on public.university_verifications
  for select to authenticated
  using (user_id = auth.uid());

-- El token no se expone: se revoca el select completo y se conceden columnas.
revoke all on public.university_verifications from anon, authenticated;
grant select (
  user_id, university_id, email, status, last_sent_at, verified_at,
  expires_at, revoked_at, revoke_reason, created_at, updated_at
) on public.university_verifications to authenticated;

drop trigger if exists university_verifications_updated
  on public.university_verifications;
create trigger university_verifications_updated
  before update on public.university_verifications
  for each row execute function public.touch_updated_at();

-- Copia de las verificaciones que ya existían para que el aviso mensual
-- también las alcance.
insert into public.university_verifications (
  user_id, university_id, email, status, verified_at, expires_at
)
select id, university_id, university_email, 'active',
       university_verified_at, university_expires_at
from public.profiles
where verified
  and university_id is not null
  and university_email is not null
on conflict (user_id) do nothing;

-- --------------------------------------------------- ¿Sigue verificado hoy?

create or replace function public.is_verified_student(
  p_user uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select p.verified
       and p.university_status = 'active'
       and (p.university_expires_at is null or p.university_expires_at > now())
      from public.profiles p
     where p.id = coalesce(p_user, auth.uid())
  ), false);
$$;

grant execute on function public.is_verified_student(uuid) to authenticated;

-- ------------------------------------- Crear el código (solo service_role)

create or replace function public.create_university_verification(
  p_user uuid,
  p_university_id text,
  p_email text,
  p_renewal boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(trim(coalesce(p_email, '')));
  v_domain text;
  v_last timestamptz;
  v_bytes bytea := gen_random_bytes(4);
  v_token text;
  v_hash text;
  v_now timestamptz := now();
begin
  if p_user is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;
  if not exists (select 1 from public.profiles where id = p_user) then
    return jsonb_build_object('result', 'no_profile');
  end if;

  select domain into v_domain
    from public.universities where id = p_university_id;
  if v_domain is null then
    return jsonb_build_object('result', 'unknown_university');
  end if;
  if right(v_email, length(v_domain) + 1) <> '@' || v_domain then
    return jsonb_build_object('result', 'domain_mismatch');
  end if;

  select last_sent_at into v_last
    from public.university_verifications where user_id = p_user;
  if v_last is not null and v_last > v_now - interval '2 minutes' then
    return jsonb_build_object('result', 'rate_limited');
  end if;

  -- Código de 6 dígitos generado con bytes aleatorios.
  v_token := lpad((
    (get_byte(v_bytes, 0)::bigint * 16777216
     + get_byte(v_bytes, 1)::bigint * 65536
     + get_byte(v_bytes, 2)::bigint * 256
     + get_byte(v_bytes, 3)::bigint) % 1000000
  )::text, 6, '0');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');

  -- Revalidación: mantener Campus activo mientras llega el código nuevo.
  if p_renewal then
    update public.university_verifications
       set token_hash = v_hash,
           token_expires_at = v_now + interval '15 minutes',
           attempts = 0,
           last_sent_at = v_now
     where user_id = p_user
       and status = 'active'
       and expires_at > v_now;
    if not found then
      return jsonb_build_object('result', 'not_active');
    end if;
    return jsonb_build_object('result', 'ok', 'token', v_token);
  end if;

  insert into public.university_verifications (
    user_id, university_id, email, status, token_hash, token_expires_at,
    attempts, last_sent_at, verified_at, expires_at, revoked_at, revoke_reason
  ) values (
    p_user, p_university_id, v_email, 'pending', v_hash,
    v_now + interval '15 minutes', 0, v_now, null, null, null, null
  )
  on conflict (user_id) do update set
    university_id = excluded.university_id,
    email = excluded.email,
    status = 'pending',
    token_hash = excluded.token_hash,
    token_expires_at = excluded.token_expires_at,
    attempts = 0,
    last_sent_at = v_now,
    verified_at = null,
    expires_at = null,
    revoked_at = null,
    revoke_reason = null;

  perform set_config('biffy.internal', '1', true);
  update public.profiles
     set university_id = p_university_id,
         university_email = v_email,
         university_status = 'pending',
         verified = false,
         university_verified_at = null,
         university_expires_at = null
   where id = p_user;
  perform set_config('biffy.internal', '0', true);

  return jsonb_build_object('result', 'ok', 'token', v_token);
end;
$$;

revoke all on function public.create_university_verification(uuid, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.create_university_verification(uuid, text, text, boolean)
  to service_role;

-- ------------------------------------------- Confirmar código (el usuario)

create or replace function public.confirm_university_verification(
  p_email text,
  p_token text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.university_verifications;
  v_hash text;
  v_now timestamptz := now();
  v_expires timestamptz := v_now + interval '30 days';
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select * into v_row
    from public.university_verifications
   where user_id = v_uid
   for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_row.status = 'active'
     and v_row.token_hash is null
     and v_row.expires_at > v_now then
    return jsonb_build_object('result', 'already_active', 'expires_at', v_row.expires_at);
  end if;
  if v_row.status not in ('pending', 'active') then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_row.token_expires_at is null or v_row.token_expires_at < v_now then
    return jsonb_build_object('result', 'expired_token');
  end if;
  if v_row.attempts >= 5 then
    return jsonb_build_object('result', 'too_many_attempts');
  end if;
  if lower(trim(coalesce(p_email, ''))) <> v_row.email then
    update public.university_verifications
       set attempts = attempts + 1
     where user_id = v_uid;
    return jsonb_build_object('result', 'invalid_token');
  end if;

  v_hash := encode(digest(trim(coalesce(p_token, '')), 'sha256'), 'hex');
  if v_hash <> v_row.token_hash then
    update public.university_verifications
       set attempts = attempts + 1
     where user_id = v_uid;
    return jsonb_build_object('result', 'invalid_token');
  end if;

  update public.university_verifications
     set status = 'active',
         verified_at = v_now,
         expires_at = v_expires,
         token_hash = null,
         token_expires_at = null,
         attempts = 0
   where user_id = v_uid;

  perform set_config('biffy.internal', '1', true);
  update public.profiles
     set verified = true,
         university_status = 'active',
         university_verified_at = v_now,
         university_expires_at = v_expires
   where id = v_uid;
  perform set_config('biffy.internal', '0', true);

  return jsonb_build_object('result', 'ok', 'expires_at', v_expires);
end;
$$;

revoke all on function public.confirm_university_verification(text, text)
  from public, anon;
grant execute on function public.confirm_university_verification(text, text)
  to authenticated;

-- ----------------------------------- Revocar por rebote o por vencimiento

create or replace function public.revoke_university_verification(
  p_user uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now timestamptz := now();
  v_reason text := left(coalesce(p_reason, 'inactive'), 200);
begin
  if p_user is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  update public.university_verifications
     set status = 'inactive',
         revoked_at = v_now,
         revoke_reason = v_reason,
         token_hash = null,
         token_expires_at = null
   where user_id = p_user;

  perform set_config('biffy.internal', '1', true);
  update public.profiles
     set verified = false,
         university_status = 'inactive'
   where id = p_user;
  perform set_config('biffy.internal', '0', true);

  insert into public.notifications (
    user_id, role, audience, title, body, route
  ) values (
    p_user,
    'buyer',
    'user:' || p_user,
    'Campus deshabilitado',
    'Tu correo institucional ya no está activo. Puedes seguir usando Biffy; Campus quedó deshabilitado.',
    '/campus'
  );

  return jsonb_build_object('result', 'ok');
end;
$$;

revoke all on function public.revoke_university_verification(uuid, text)
  from public, anon, authenticated;
grant execute on function public.revoke_university_verification(uuid, text)
  to service_role;

-- ------------------------------------------ Revocar todos los vencidos

create or replace function public.expire_university_verifications()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ids uuid[];
begin
  select array_agg(user_id) into v_ids
    from public.university_verifications
   where status = 'active' and expires_at < now();

  if v_ids is null or cardinality(v_ids) = 0 then
    return 0;
  end if;

  update public.university_verifications
     set status = 'inactive',
         revoked_at = now(),
         revoke_reason = 'expired',
         token_hash = null,
         token_expires_at = null
   where user_id = any (v_ids);

  perform set_config('biffy.internal', '1', true);
  update public.profiles
     set verified = false,
         university_status = 'inactive'
   where id = any (v_ids);
  perform set_config('biffy.internal', '0', true);

  insert into public.notifications (
    user_id, role, audience, title, body, route
  )
  select id, 'buyer', 'user:' || id,
         'Campus deshabilitado',
         'Tu verificación institucional venció. Puedes seguir usando Biffy; vuelve a verificar para recuperar Campus.',
         '/campus'
    from unnest(v_ids) as id;

  return cardinality(v_ids);
end;
$$;

revoke all on function public.expire_university_verifications()
  from public, anon, authenticated;
grant execute on function public.expire_university_verifications()
  to service_role;

-- ------------------------------------- Verificación antigua sin escritura

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
  select domain into v_domain
    from public.universities where id = v_uni;
  if v_domain is null then
    return jsonb_build_object('result', 'unknown_university');
  end if;
  if right(v_email, length(v_domain) + 1) <> '@' || v_domain then
    return jsonb_build_object('result', 'domain_mismatch');
  end if;
  -- Ya no marca verificado: ahora hace falta el código enviado al correo.
  return jsonb_build_object('result', 'token_required');
end;
$$;

-- ------------------------------------- Proteger las columnas nuevas

create or replace function public.guard_profile_update()
returns trigger
language plpgsql
as $$
begin
  if coalesce(current_setting('biffy.internal', true), '0') = '1' then
    return new;
  end if;
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;

  if new.role <> old.role then
    raise exception 'El rol no se puede cambiar desde el cliente';
  end if;
  if new.verified <> old.verified then
    raise exception 'La verificación se gestiona con el código institucional';
  end if;
  if new.university_status is distinct from old.university_status
     or new.university_verified_at is distinct from old.university_verified_at
     or new.university_expires_at is distinct from old.university_expires_at then
    raise exception 'La verificación institucional se gestiona con el código enviado al correo';
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

-- ============================================================================
-- place_order con la verificación vigente
-- ============================================================================
-- Se reemplaza la función de 0019 para que el descuento de campus solo se
-- aplique si la verificación institucional está activa y no vencida.
-- El resto de la lógica es idéntica a 0019.
-- ============================================================================

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
