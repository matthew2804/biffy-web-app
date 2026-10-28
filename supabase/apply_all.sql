-- ============================================================================
-- Biffy · Bootstrap de base de datos (generado)
-- ============================================================================
-- Uso: Supabase Dashboard -> SQL Editor -> New query -> pegar todo -> Run.
-- Se genera concatenando supabase/migrations/*.sql. No editar a mano.
-- Proyecto: jwdzpwsfwtkdeeuceaco
-- Generado: 2026-10-28 11:03
-- ============================================================================
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0000_legacy_cleanup.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0000 · Limpieza inicial del esquema public
-- ============================================================================
-- El proyecto remoto tenía tablas creadas a mano antes de este esquema
-- (users, sedes, dishes, categories, orders, order_items, courier_profiles,
-- notifications, universities, delivery_points, reviews, dish_options,
-- user_roles, gotas_rewards, ...). Se reemplazan por el esquema canónico.
--
-- Reglas de seguridad:
--   · Nunca toca objetos de extensiones (PostGIS crea `spatial_ref_sys`,
--     `geometry_columns`, `geography_columns`, ... en `public`).
--   · Tabla VACÍA  -> se elimina.
--   · Tabla CON FILAS -> NO se borra: se renombra a `legacy_<nombre>`, se le
--     activa RLS sin políticas y se le revocan los permisos. Nada se pierde.
--   · Se ejecuta una única vez: queda marcado en `_biffy_meta`.
-- ============================================================================

create table if not exists public._biffy_meta (
  key text primary key,
  value text not null,
  applied_at timestamptz not null default now()
);

do $cleanup$
declare
  v_obj text;
  v_new text;
  v_rows bigint;
  v_n int;
  v_protected text[] := array[
    '_biffy_meta',
    -- Objetos de PostGIS que viven en public:
    'spatial_ref_sys', 'geometry_columns', 'geography_columns',
    'raster_columns', 'raster_overviews'
  ];
begin
  if exists (select 1 from public._biffy_meta where key = 'legacy_cleanup') then
    raise notice 'Limpieza inicial ya aplicada; se omite.';
    return;
  end if;

  -- 1) Vistas del proyecto (no de extensiones).
  for v_obj in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind = 'v'
      and c.relname <> all (v_protected)
      and not exists (
        select 1
        from pg_depend d
        join pg_extension e on e.oid = d.refobjid
        where d.objid = c.oid and d.deptype = 'e'
      )
    order by c.relname
  loop
    execute format('drop view if exists public.%I cascade', v_obj);
    raise notice 'Vista public.% eliminada.', v_obj;
  end loop;

  -- 2) Tablas del proyecto (no de extensiones).
  for v_obj in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')
      and c.relname <> all (v_protected)
      and not exists (
        select 1
        from pg_depend d
        join pg_extension e on e.oid = d.refobjid
        where d.objid = c.oid and d.deptype = 'e'
      )
    order by c.relname
  loop
    execute format('select count(*) from public.%I', v_obj) into v_rows;

    if v_rows = 0 then
      execute format('drop table public.%I cascade', v_obj);
      raise notice 'Tabla public.% eliminada (0 filas).', v_obj;
      continue;
    end if;

    -- Con datos: se conserva, renombrada y bloqueada.
    v_new := 'legacy_' || v_obj;
    v_n := 1;
    while exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = v_new
    ) loop
      v_n := v_n + 1;
      v_new := 'legacy_' || v_obj || '_' || v_n;
    end loop;

    execute format('alter table public.%I rename to %I', v_obj, v_new);
    execute format('alter table public.%I enable row level security', v_new);
    execute format('revoke all on table public.%I from anon, authenticated', v_new);
    raise notice
      'Tabla public.% conservada como public.% (% filas, RLS activo).',
      v_obj, v_new, v_rows;
  end loop;

  insert into public._biffy_meta (key, value) values ('legacy_cleanup', 'ok');
end
$cleanup$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0001_init.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0001 · Extensiones, tipos y utilidades
-- ============================================================================

create extension if not exists pgcrypto;

do $$ begin
  create type public.user_role as enum ('buyer', 'courier', 'restaurant');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_status as enum
    ('pending', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.vehicle_type as enum ('moto', 'bicycle', 'scooter', 'walking');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.courier_zone as enum ('general', 'campus');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.coupon_kind as enum ('free_delivery', 'fixed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.dish_option_kind as enum ('size', 'side', 'extra');
exception when duplicate_object then null; end $$;

-- Códigos de pedido legibles: BF-2041, BF-2042, ...
create sequence if not exists public.order_code_seq start with 2041;

-- Código de entrega de 4 dígitos (único por pedido mientras la secuencia no
-- dé la vuelta; la columna además es NOT NULL).
create sequence if not exists public.delivery_code_seq start with 1000;

-- Marca updated_at en cada UPDATE.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0002_schema.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0002 · Esquema base
-- ============================================================================
-- Convenciones:
--   · Dinero en pesos colombianos enteros (int). Nunca float.
--   · Fechas en timestamptz (UTC).
--   · Catálogo y pedidos usan uuid; las tablas de referencia (universidades,
--     puntos de entrega, categorías) usan text porque son constantes de la app.
--   · Borrado lógico (deleted_at) en catálogo y direcciones.
-- ============================================================================

-- ---------------------------------------------------------------- Referencia

create table if not exists public.universities (
  id text primary key,
  name text not null,
  domain text not null unique,
  city text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.delivery_points (
  id text primary key,
  name text not null,
  detail text not null default '',
  lat numeric(9, 6) not null,
  lng numeric(9, 6) not null,
  campus_id text references public.universities (id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id text primary key,
  label text not null,
  emoji text not null default '🍽️',
  sort int not null default 0
);

-- ------------------------------------------------------------------ Usuarios

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  full_name text not null default '',
  phone text not null default '',
  role public.user_role not null default 'buyer',
  university_id text references public.universities (id) on delete set null,
  university_email text,
  verified boolean not null default false,
  business_id uuid,
  active_role public.user_role not null default 'buyer',
  is_demo boolean not null default false,
  gotas int not null default 0 check (gotas >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------------ Catálogo

create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  brand text not null,
  legal_name text not null default '',
  nit text not null default '',
  cuisine text not null default 'almuerzo',
  description text not null default '',
  owner_name text not null default '',
  owner_doc text not null default '',
  owner_phone text not null default '',
  owner_email text not null default '',
  bank_name text not null default '',
  account_type text not null default 'Ahorros',
  account_number text not null default '',
  legal_docs jsonb not null default '{}'::jsonb,
  nutrition_info boolean not null default false,
  is_demo boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- FK circular resuelta después de crear businesses.
do $$ begin
  alter table public.profiles
    add constraint profiles_business_id_fkey
    foreign key (business_id) references public.businesses (id) on delete set null;
exception when duplicate_object then null; end $$;

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  name text not null,
  branch_name text not null default 'Sede principal',
  emoji text not null default '🍽️',
  tagline text not null default '',
  cuisine text not null default 'almuerzo',
  address text not null default '',
  city text not null default '',
  lat numeric(9, 6) not null default 0,
  lng numeric(9, 6) not null default 0,
  radius_km numeric(4, 2) not null default 3 check (radius_km > 0),
  couriers_nearby int not null default 0 check (couriers_nearby >= 0),
  rating numeric(2, 1) not null default 4.5 check (rating between 0 and 5),
  prep_min int not null default 20 check (prep_min > 0),
  open_hour int not null default 8 check (open_hour between 0 and 23),
  close_hour int not null default 22 check (close_hour between 1 and 24),
  closed_weekdays smallint[] not null default '{}',
  campus_id text references public.universities (id) on delete set null,
  student_discount numeric(4, 2) not null default 0
    check (student_discount between 0 and 0.3),
  paused boolean not null default false,
  demo boolean not null default false,
  campus_delivery_only boolean not null default false,
  shows_nutrition boolean not null default false,
  image_url text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dishes (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches (id) on delete cascade,
  name text not null,
  description text not null default '',
  price int not null check (price >= 0),
  emoji text not null default '🍽️',
  category_id text not null references public.categories (id),
  section text not null default 'Menú',
  prep_min int not null default 15 check (prep_min > 0),
  rating numeric(2, 1) not null default 4.5 check (rating between 0 and 5),
  ingredients text[] not null default '{}',
  allergens text[] not null default '{}',
  tags text[] not null default '{}',
  nutrition jsonb,
  popular boolean not null default false,
  featured boolean not null default false,
  active boolean not null default true,
  sold_out boolean not null default false,
  portion_limit int check (portion_limit is null or portion_limit >= 0),
  sold_today int not null default 0 check (sold_today >= 0),
  image_url text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.dish_options (
  id uuid primary key default gen_random_uuid(),
  dish_id uuid not null references public.dishes (id) on delete cascade,
  kind public.dish_option_kind not null,
  label text not null,
  price_delta int not null default 0,
  sort int not null default 0,
  active boolean not null default true
);

-- -------------------------------------------------------- Datos del comprador

create table if not exists public.preferences (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  likes text[] not null default '{}',
  lifestyle text[] not null default '{}',
  allergies text[] not null default '{}',
  budget int not null default 25000 check (budget >= 0),
  completed boolean not null default false,
  rewarded boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  notifications boolean not null default true,
  promotions boolean not null default true,
  email_summary boolean not null default false,
  dark_mode boolean not null default false,
  demo_lunch boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  label text not null,
  line text not null,
  details text not null default '',
  neighborhood text not null default '',
  reference text not null default '',
  point_id text not null references public.delivery_points (id),
  is_default boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists addresses_one_default_idx
  on public.addresses (user_id)
  where is_default and deleted_at is null;

create table if not exists public.gotas_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  amount int not null,
  reason text not null default '',
  order_id uuid,
  created_at timestamptz not null default now()
);

-- Catálogo de recompensas canjeables con Gotas. Conserva el modelo que ya
-- existía en el proyecto (código, tipo, costo, nivel y frecuencia de sorteo).
create table if not exists public.gotas_rewards (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  reward_type text not null
    check (reward_type in ('free_shipping', 'mystery_box', 'monthly_raffle', 'discount')),
  gotas_cost int not null check (gotas_cost >= 0),
  tier int,
  draw_frequency text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  reward_id uuid not null references public.gotas_rewards (id) on delete restrict,
  gotas_spent int not null check (gotas_spent >= 0),
  status text not null default 'granted'
    check (status in ('granted', 'used', 'expired', 'cancelled')),
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  title text not null,
  kind public.coupon_kind not null,
  amount int not null default 0 check (amount >= 0),
  max_uses int,
  used_count int not null default 0 check (used_count >= 0),
  active boolean not null default true,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.user_coupons (
  user_id uuid not null references public.profiles (id) on delete cascade,
  coupon_id uuid not null references public.coupons (id) on delete cascade,
  used_at timestamptz,
  primary key (user_id, coupon_id)
);

create table if not exists public.favorite_dishes (
  user_id uuid not null references public.profiles (id) on delete cascade,
  dish_id uuid not null references public.dishes (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, dish_id)
);

create table if not exists public.favorite_branches (
  user_id uuid not null references public.profiles (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, branch_id)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade,
  audience text not null default 'all',
  title text not null,
  body text not null default '',
  route text,
  read_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------- Repartidor

create table if not exists public.courier_profiles (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  full_name text not null,
  doc_type text not null default 'CC',
  doc_number text not null,
  phone text not null default '',
  vehicle public.vehicle_type not null default 'moto',
  plate text,
  university_id text references public.universities (id) on delete set null,
  zone public.courier_zone not null default 'general',
  online boolean not null default false,
  rating numeric(2, 1) not null default 5.0 check (rating between 0 and 5),
  deliveries_total int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ------------------------------------------------------------------- Pedidos

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  code text not null unique
    default ('BF-' || nextval('public.order_code_seq')),
  buyer_id uuid not null references public.profiles (id) on delete restrict,
  buyer_name text not null default '',
  branch_id uuid not null references public.branches (id) on delete restrict,
  restaurant_name text not null default '',
  address_snapshot jsonb not null default '{}'::jsonb,
  point_id text references public.delivery_points (id),
  payment_method text not null
    check (payment_method in ('nequi', 'daviplata', 'card', 'pse', 'cash')),
  status public.order_status not null default 'pending',
  subtotal int not null check (subtotal >= 0),
  campus_discount int not null default 0 check (campus_discount >= 0),
  coupon_discount int not null default 0 check (coupon_discount >= 0),
  delivery_fee int not null default 0 check (delivery_fee >= 0),
  gotas_used int not null default 0 check (gotas_used >= 0),
  tip int not null default 0 check (tip >= 0),
  total int not null check (total >= 0),
  eta_min int not null default 20,
  courier_pay int not null default 0 check (courier_pay >= 0),
  distance_km numeric(5, 2) not null default 0 check (distance_km >= 0),
  delivery_code text not null,
  pickup_code text not null default '',
  restaurant_note text not null default '',
  scheduled_for timestamptz,
  courier_id uuid references public.profiles (id) on delete set null,
  courier_name text,
  reject_reason text,
  evidence_url text,
  coupon_id uuid references public.coupons (id) on delete set null,
  gotas_credited boolean not null default false,
  accepted_at timestamptz,
  ready_at timestamptz,
  picked_up_at timestamptz,
  delivered_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  dish_id uuid references public.dishes (id) on delete set null,
  name text not null,
  emoji text not null default '🍽️',
  qty int not null check (qty > 0),
  unit_price int not null check (unit_price >= 0),
  selection jsonb not null default '{}'::jsonb,
  detail text not null default '',
  note text not null default ''
);

create table if not exists public.order_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  status public.order_status not null,
  actor_id uuid references public.profiles (id) on delete set null,
  actor_label text not null default '',
  created_at timestamptz not null default now()
);

create table if not exists public.order_declines (
  order_id uuid not null references public.orders (id) on delete cascade,
  courier_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (order_id, courier_id)
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null unique references public.orders (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now()
);

-- --------------------------------------------- PostGIS (opcional, si existe)
-- El esquema original ya usaba geometrías (polígono de campus y puntos de
-- sede/entrega). Se conservan como columnas opcionales: la regla de radio
-- actual sigue usando lat/lng + repartidores, y más adelante se puede pasar a
-- ST_DWithin sin cambiar el modelo.
do $postgis$
begin
  if exists (select 1 from pg_extension where extname = 'postgis') then
    alter table public.universities
      add column if not exists boundary_polygon geometry(Polygon, 4326);
    alter table public.delivery_points
      add column if not exists location geometry(Point, 4326);
    alter table public.branches
      add column if not exists location geometry(Point, 4326);

    create index if not exists delivery_points_location_idx
      on public.delivery_points using gist (location);
    create index if not exists branches_location_idx
      on public.branches using gist (location);

    comment on column public.universities.boundary_polygon is
      'Polígono del campus (SRID 4326). Opcional hoy; base para geocercas.';
    comment on column public.delivery_points.location is
      'Punto del lugar de entrega (SRID 4326), para radio con ST_DWithin.';
    comment on column public.branches.location is
      'Punto de la sede (SRID 4326), para radio con ST_DWithin.';
  end if;
end
$postgis$;

-- ------------------------------------------------------------------- Índices

create index if not exists branches_business_idx
  on public.branches (business_id) where deleted_at is null;
create index if not exists branches_geo_idx on public.branches (lat, lng);
create index if not exists branches_campus_idx on public.branches (campus_id);

create index if not exists dishes_branch_idx
  on public.dishes (branch_id) where deleted_at is null;
create index if not exists dishes_category_idx on public.dishes (category_id);

create index if not exists dish_options_dish_idx on public.dish_options (dish_id);

create index if not exists addresses_user_idx
  on public.addresses (user_id) where deleted_at is null;

create index if not exists gotas_user_idx
  on public.gotas_ledger (user_id, created_at desc);

create index if not exists reward_redemptions_user_idx
  on public.reward_redemptions (user_id, created_at desc);
create index if not exists reward_redemptions_reward_idx
  on public.reward_redemptions (reward_id);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_audience_idx
  on public.notifications (audience, created_at desc);

create index if not exists orders_buyer_idx
  on public.orders (buyer_id, created_at desc);
create index if not exists orders_branch_idx
  on public.orders (branch_id, created_at desc);
create index if not exists orders_courier_idx on public.orders (courier_id);
create index if not exists orders_status_idx on public.orders (status);
create index if not exists orders_available_idx
  on public.orders (created_at desc)
  where status = 'ready' and courier_id is null;

create index if not exists order_items_order_idx on public.order_items (order_id);
create index if not exists order_events_order_idx
  on public.order_events (order_id, created_at);

-- ---------------------------------------------------- Triggers de updated_at

do $$
declare
  t text;
begin
  foreach t in array array[
    'profiles', 'businesses', 'branches', 'dishes', 'preferences',
    'app_settings', 'addresses', 'courier_profiles', 'orders', 'gotas_rewards'
  ] loop
    execute format('drop trigger if exists set_updated_at on public.%I', t);
    execute format(
      'create trigger set_updated_at before update on public.%I
       for each row execute function public.touch_updated_at()', t);
  end loop;
end $$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0003_functions.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
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

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0004_rls.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0004 · Row Level Security
-- ============================================================================
-- Principio: todo denegado por defecto. El catálogo es público; los datos de
-- cada persona solo los ve su dueño; los pedidos los ven las tres partes
-- involucradas. Las escrituras de pedidos NO tienen política: solo entran por
-- las funciones de 0003 (security definer).
-- ============================================================================

alter table public._biffy_meta enable row level security;
alter table public.universities enable row level security;
alter table public.delivery_points enable row level security;
alter table public.categories enable row level security;
alter table public.profiles enable row level security;
alter table public.businesses enable row level security;
alter table public.branches enable row level security;
alter table public.dishes enable row level security;
alter table public.dish_options enable row level security;
alter table public.preferences enable row level security;
alter table public.app_settings enable row level security;
alter table public.addresses enable row level security;
alter table public.gotas_ledger enable row level security;
alter table public.gotas_rewards enable row level security;
alter table public.reward_redemptions enable row level security;
alter table public.coupons enable row level security;
alter table public.user_coupons enable row level security;
alter table public.favorite_dishes enable row level security;
alter table public.favorite_branches enable row level security;
alter table public.notifications enable row level security;
alter table public.courier_profiles enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_events enable row level security;
alter table public.order_declines enable row level security;
alter table public.reviews enable row level security;

-- ---------------------------------------------------------------- Catálogo

drop policy if exists universities_read on public.universities;
create policy universities_read on public.universities
  for select to anon, authenticated using (true);

drop policy if exists delivery_points_read on public.delivery_points;
create policy delivery_points_read on public.delivery_points
  for select to anon, authenticated using (true);

drop policy if exists categories_read on public.categories;
create policy categories_read on public.categories
  for select to anon, authenticated using (true);

drop policy if exists branches_read on public.branches;
create policy branches_read on public.branches
  for select to anon, authenticated
  using (deleted_at is null);

drop policy if exists branches_write on public.branches;
create policy branches_write on public.branches
  for all to authenticated
  using (business_id = public.my_business_id())
  with check (business_id = public.my_business_id());

drop policy if exists dishes_read on public.dishes;
create policy dishes_read on public.dishes
  for select to anon, authenticated
  using (deleted_at is null and (active or public.is_my_branch(branch_id)));

drop policy if exists dishes_write on public.dishes;
create policy dishes_write on public.dishes
  for all to authenticated
  using (public.is_my_branch(branch_id))
  with check (public.is_my_branch(branch_id));

drop policy if exists dish_options_read on public.dish_options;
create policy dish_options_read on public.dish_options
  for select to anon, authenticated using (active or public.is_my_branch(
    (select d.branch_id from public.dishes d where d.id = dish_id)
  ));

drop policy if exists dish_options_write on public.dish_options;
create policy dish_options_write on public.dish_options
  for all to authenticated
  using (public.is_my_branch(
    (select d.branch_id from public.dishes d where d.id = dish_id)
  ))
  with check (public.is_my_branch(
    (select d.branch_id from public.dishes d where d.id = dish_id)
  ));

drop policy if exists coupons_read on public.coupons;
create policy coupons_read on public.coupons
  for select to authenticated using (active);

-- --------------------------------------------------------------- Identidad

drop policy if exists profiles_read on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated using (id = auth.uid());

drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

drop policy if exists businesses_read on public.businesses;
create policy businesses_read on public.businesses
  for select to authenticated using (owner_id = auth.uid());

drop policy if exists businesses_insert on public.businesses;
create policy businesses_insert on public.businesses
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists businesses_update on public.businesses;
create policy businesses_update on public.businesses
  for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Datos públicos del negocio (sin cuentas bancarias ni documentos).
create or replace view public.businesses_public as
select id, brand, cuisine, description, nutrition_info
from public.businesses;

grant select on public.businesses_public to anon, authenticated;

-- ------------------------------------------------------- Datos personales

drop policy if exists preferences_owner on public.preferences;
create policy preferences_owner on public.preferences
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists app_settings_owner on public.app_settings;
create policy app_settings_owner on public.app_settings
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists addresses_owner on public.addresses;
create policy addresses_owner on public.addresses
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists gotas_ledger_read on public.gotas_ledger;
create policy gotas_ledger_read on public.gotas_ledger
  for select to authenticated using (user_id = auth.uid());

drop policy if exists gotas_rewards_read on public.gotas_rewards;
create policy gotas_rewards_read on public.gotas_rewards
  for select to anon, authenticated using (is_active);

drop policy if exists reward_redemptions_read on public.reward_redemptions;
create policy reward_redemptions_read on public.reward_redemptions
  for select to authenticated using (user_id = auth.uid());

drop policy if exists user_coupons_read on public.user_coupons;
create policy user_coupons_read on public.user_coupons
  for select to authenticated using (user_id = auth.uid());

drop policy if exists favorite_dishes_owner on public.favorite_dishes;
create policy favorite_dishes_owner on public.favorite_dishes
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists favorite_branches_owner on public.favorite_branches;
create policy favorite_branches_owner on public.favorite_branches
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists courier_profiles_owner on public.courier_profiles;
create policy courier_profiles_owner on public.courier_profiles
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists notifications_read on public.notifications;
create policy notifications_read on public.notifications
  for select to authenticated
  using (
    user_id = auth.uid()
    or audience = 'all'
    or (audience = 'couriers' and public.is_courier())
    or audience = 'user:' || auth.uid()::text
  );

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ----------------------------------------------------------------- Pedidos

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
  for select to authenticated
  using (
    buyer_id = auth.uid()
    or courier_id = auth.uid()
    or public.is_my_branch(branch_id)
    or (status = 'ready' and courier_id is null)
  );

drop policy if exists order_items_read on public.order_items;
create policy order_items_read on public.order_items
  for select to authenticated using (public.can_read_order(order_id));

drop policy if exists order_events_read on public.order_events;
create policy order_events_read on public.order_events
  for select to authenticated using (public.can_read_order(order_id));

drop policy if exists order_declines_read on public.order_declines;
create policy order_declines_read on public.order_declines
  for select to authenticated using (courier_id = auth.uid());

drop policy if exists reviews_read on public.reviews;
create policy reviews_read on public.reviews
  for select to anon, authenticated using (true);

drop policy if exists reviews_insert on public.reviews;
create policy reviews_insert on public.reviews
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.orders o
      where o.id = order_id
        and o.buyer_id = auth.uid()
        and o.status = 'delivered'
    )
  );

-- ------------------------------------------------------------- Privilegios

grant usage on schema public to anon, authenticated;

grant select on
  public.universities,
  public.delivery_points,
  public.categories,
  public.branches,
  public.dishes,
  public.dish_options,
  public.gotas_rewards,
  public.reviews
to anon, authenticated;

grant select, insert, update, delete on all tables in schema public
  to authenticated;

grant select on public.notifications to authenticated;
grant select on public.coupons to authenticated;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0005_storage.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0005 · Storage (buckets y políticas)
-- ============================================================================
-- dish-images        público   fotos de platos (carpeta = business_id)
-- delivery-evidence  privado   evidencia de entrega (carpeta = order_id)
-- merchant-docs      privado   documentos del negocio (carpeta = business_id)
-- ============================================================================

insert into storage.buckets (id, name, public)
values
  ('dish-images', 'dish-images', true),
  ('delivery-evidence', 'delivery-evidence', false),
  ('merchant-docs', 'merchant-docs', false)
on conflict do nothing;

-- Cast seguro de texto a uuid (evita errores en rutas que no son de pedido).
create or replace function public.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
as $$
begin
  return p_value::uuid;
exception when others then
  return null;
end;
$$;

-- ---------------------------------------------------------------- dish-images

drop policy if exists dish_images_read on storage.objects;
create policy dish_images_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'dish-images');

drop policy if exists dish_images_insert on storage.objects;
create policy dish_images_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'dish-images'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists dish_images_update on storage.objects;
create policy dish_images_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'dish-images'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists dish_images_delete on storage.objects;
create policy dish_images_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'dish-images'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

-- ---------------------------------------------------------- delivery-evidence

drop policy if exists delivery_evidence_read on storage.objects;
create policy delivery_evidence_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'delivery-evidence'
    and public.can_read_order(public.try_uuid((storage.foldername(name))[1]))
  );

drop policy if exists delivery_evidence_insert on storage.objects;
create policy delivery_evidence_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'delivery-evidence'
    and exists (
      select 1 from public.orders o
      where o.id = public.try_uuid((storage.foldername(name))[1])
        and o.courier_id = auth.uid()
    )
  );

-- --------------------------------------------------------------- merchant-docs

drop policy if exists merchant_docs_read on storage.objects;
create policy merchant_docs_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'merchant-docs'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists merchant_docs_insert on storage.objects;
create policy merchant_docs_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'merchant-docs'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists merchant_docs_delete on storage.objects;
create policy merchant_docs_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'merchant-docs'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0006_seed_reference.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0006 · Datos de referencia
-- ============================================================================
-- Universidades, puntos de entrega y categorías: son constantes que la app
-- ya tiene en `lib/core/constants/catalog_constants.dart`. Se replican aquí
-- para que la base sea usable sola (joins, validación de dominio, RLS).
--
-- El catálogo de restaurantes/platos NO se siembra aquí: depende de una
-- cuenta de Auth (owner_id). Se carga con el script de datos demo.
-- ============================================================================

insert into public.universities (id, name, domain, city) values
  ('icesi', 'Universidad Icesi', 'icesi.edu.co', 'Cali'),
  ('unal', 'Universidad Nacional', 'unal.edu.co', 'Bogotá'),
  ('andes', 'Universidad de los Andes', 'uniandes.edu.co', 'Bogotá'),
  ('javeriana', 'Pontificia Universidad Javeriana', 'javeriana.edu.co', 'Bogotá')
on conflict (id) do update set
  name = excluded.name,
  domain = excluded.domain,
  city = excluded.city;

insert into public.delivery_points (id, name, detail, lat, lng, campus_id) values
  ('icesi-biblioteca', 'Icesi · Biblioteca', 'Punto de encuentro demo · Cali', 3.3415, -76.5305, 'icesi'),
  ('icesi-plazoleta', 'Icesi · Plazoleta', 'Punto de encuentro demo · Cali', 3.3421, -76.5298, 'icesi'),
  ('icesi-entrada', 'Icesi · Entrada principal', 'Punto de encuentro demo · Cali', 3.3409, -76.5309, 'icesi'),
  ('biblio', 'Biblioteca Central', 'Entrada principal · Bogotá', 4.6355, -74.0830, 'unal'),
  ('inge', 'Edificio Ingeniería', 'Hall piso 1 · Bogotá', 4.6378, -74.0825, 'unal'),
  ('plazoleta-che', 'Plazoleta Che', 'Junto a las bancas · Bogotá', 4.6362, -74.0815, 'unal'),
  ('chapinero', 'Casa · Chapinero', 'Cra 7 #60-20 · Bogotá', 4.6465, -74.0628, null),
  ('suba', 'Casa · Suba', 'Cl 145 #91-10 · Bogotá', 4.7405, -74.0835, null)
on conflict (id) do update set
  name = excluded.name,
  detail = excluded.detail,
  lat = excluded.lat,
  lng = excluded.lng,
  campus_id = excluded.campus_id;

insert into public.categories (id, label, emoji, sort) values
  ('sandwich', 'Sándwiches', '🥪', 1),
  ('pizza', 'Pizza', '🍕', 2),
  ('hamburguesa', 'Hamburguesas', '🍔', 3),
  ('saludable', 'Saludable', '🥗', 4),
  ('almuerzo', 'Almuerzos', '🍛', 5),
  ('cafe', 'Café', '☕', 6),
  ('postres', 'Postres', '🍩', 7),
  ('mexicana', 'Mexicana', '🌮', 8),
  ('asiatica', 'Asiática', '🍜', 9)
on conflict (id) do update set
  label = excluded.label,
  emoji = excluded.emoji,
  sort = excluded.sort;

-- Recompensas canjeables con Gotas (se conservan las que ya existían en el
-- proyecto: envío gratis, caja sorpresa, caja premium y sorteo mensual).
insert into public.gotas_rewards
  (code, name, reward_type, gotas_cost, tier, draw_frequency, is_active)
values
  ('free_shipping', 'Envío gratis', 'free_shipping', 5, null, null, true),
  ('box_25', 'Caja sorpresa', 'mystery_box', 25, 1, null, true),
  ('box_50', 'Caja premium', 'mystery_box', 50, 2, null, true),
  ('box_100', 'Caja sorteo', 'monthly_raffle', 100, 3, 'monthly', true)
on conflict (code) do update set
  name = excluded.name,
  reward_type = excluded.reward_type,
  gotas_cost = excluded.gotas_cost,
  tier = excluded.tier,
  draw_frequency = excluded.draw_frequency,
  is_active = excluded.is_active;

-- Geometrías de los puntos (solo si PostGIS está instalado).
do $geo$
begin
  if exists (select 1 from pg_extension where extname = 'postgis') then
    update public.delivery_points
       set location = st_setsrid(st_makepoint(lng::float8, lat::float8), 4326)
     where location is null;
  end if;
end
$geo$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0008_reward_boxes.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0008 · Cajas con premios aleatorios
-- ============================================================================
-- Cada caja (mystery_box / monthly_raffle) tiene un catálogo de premios con
-- un peso. Al canjearla se sortea un premio ponderado: a mejor caja (tier),
-- mejores premios y mayor probabilidad de los raros.
--
-- El premio se guarda en `reward_redemptions` para que quede trazable.
-- ============================================================================

create table if not exists public.gotas_reward_prizes (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid not null references public.gotas_rewards (id) on delete cascade,
  code text not null,
  label text not null,
  prize_type text not null
    check (prize_type in ('discount', 'free_shipping', 'product', 'raffle_ticket')),
  amount int not null default 0 check (amount >= 0),
  weight int not null default 10 check (weight > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (reward_id, code)
);

create index if not exists gotas_reward_prizes_reward_idx
  on public.gotas_reward_prizes (reward_id)
  where is_active;

alter table public.reward_redemptions
  add column if not exists prize_id uuid
    references public.gotas_reward_prizes (id) on delete set null;
alter table public.reward_redemptions
  add column if not exists prize_label text;
alter table public.reward_redemptions
  add column if not exists prize_type text;
alter table public.reward_redemptions
  add column if not exists prize_amount int not null default 0;

alter table public.gotas_reward_prizes enable row level security;

drop policy if exists gotas_reward_prizes_read on public.gotas_reward_prizes;
create policy gotas_reward_prizes_read on public.gotas_reward_prizes
  for select to anon, authenticated using (is_active);

grant select on public.gotas_reward_prizes to anon, authenticated;

-- ---------------------------------------------------------------- Canje

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
  v_prize public.gotas_reward_prizes;
  v_prize_id uuid;
  v_total int;
  v_roll numeric;
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

  -- Bloquea el perfil: dos canjes simultáneos no pueden gastar de más.
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

  -- Sorteo ponderado (solo cajas y sorteo mensual).
  if v_reward.reward_type in ('mystery_box', 'monthly_raffle') then
    select coalesce(sum(weight), 0) into v_total
      from public.gotas_reward_prizes
     where reward_id = v_reward.id
       and is_active;

    if v_total > 0 then
      v_roll := random() * v_total;

      select p.id into v_prize_id
        from (
          select id, sum(weight) over (order by id) as cum
            from public.gotas_reward_prizes
           where reward_id = v_reward.id
             and is_active
        ) p
       where p.cum >= v_roll
       order by p.cum
       limit 1;

      if v_prize_id is not null then
        select * into v_prize
          from public.gotas_reward_prizes
         where id = v_prize_id;
      end if;
    end if;
  end if;

  insert into public.reward_redemptions (
    user_id, reward_id, gotas_spent,
    prize_id, prize_label, prize_type, prize_amount
  ) values (
    v_uid, v_reward.id, v_reward.gotas_cost,
    v_prize.id, v_prize.label, v_prize.prize_type,
    coalesce(v_prize.amount, 0)
  )
  returning id into v_redemption;

  perform public.credit_gotas(
    v_uid, -v_reward.gotas_cost, 'Canje: ' || v_reward.name, null
  );

  return jsonb_build_object(
    'result', 'ok',
    'redemption_id', v_redemption,
    'reward', v_reward.code,
    'balance', v_balance - v_reward.gotas_cost,
    'prize', case
      when v_prize.id is null then null
      else jsonb_build_object(
        'label', v_prize.label,
        'type', v_prize.prize_type,
        'amount', v_prize.amount
      )
    end
  );
end;
$$;

revoke all on function public.redeem_reward(jsonb) from public, anon;
grant execute on function public.redeem_reward(jsonb) to authenticated;

-- ------------------------------------------------------- Premios por caja
-- Los pesos son relativos: 45 significa 45 % si el total suma 100.

insert into public.gotas_reward_prizes
  (reward_id, code, label, prize_type, amount, weight)
select r.id, v.code, v.label, v.prize_type, v.amount, v.weight
from (values
  -- Caja sorpresa (25 Gotas) · premios comunes
  ('box_25', 'discount_2000', '$2.000 de descuento', 'discount', 2000, 45),
  ('box_25', 'free_shipping', 'Envío gratis', 'free_shipping', 0, 25),
  ('box_25', 'discount_3000', '$3.000 de descuento', 'discount', 3000, 18),
  ('box_25', 'product_dessert', 'Postre gratis', 'product', 0, 9),
  ('box_25', 'discount_5000', '$5.000 de descuento', 'discount', 5000, 3),

  -- Caja premium (50 Gotas) · premios medios
  ('box_50', 'discount_5000', '$5.000 de descuento', 'discount', 5000, 40),
  ('box_50', 'free_shipping_x2', '2 envíos gratis', 'free_shipping', 0, 20),
  ('box_50', 'discount_8000', '$8.000 de descuento', 'discount', 8000, 22),
  ('box_50', 'product_surprise', 'Producto sorpresa', 'product', 0, 13),
  ('box_50', 'discount_12000', '$12.000 de descuento', 'discount', 12000, 5),

  -- Caja sorteo (100 Gotas) · premios altos + boleto
  ('box_100', 'discount_10000', '$10.000 de descuento', 'discount', 10000, 35),
  ('box_100', 'discount_15000', '$15.000 de descuento', 'discount', 15000, 25),
  ('box_100', 'product_premium', 'Producto premium', 'product', 0, 20),
  ('box_100', 'raffle_ticket', 'Boleto extra de sorteo', 'raffle_ticket', 0, 15),
  ('box_100', 'discount_25000', '$25.000 de descuento', 'discount', 25000, 5)
) as v(reward_code, code, label, prize_type, amount, weight)
join public.gotas_rewards r on r.code = v.reward_code
on conflict (reward_id, code) do update set
  label = excluded.label,
  prize_type = excluded.prize_type,
  amount = excluded.amount,
  weight = excluded.weight,
  is_active = true;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0009_welcome_gotas.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0009 · Gotas de bienvenida
-- ============================================================================
-- Al crear el perfil se acreditan 450 Gotas, igual que el modo demo
-- (`kWelcomeGotas` en lib/core/constants/catalog_constants.dart).
--
-- Sin esto, una cuenta nueva llegaría con 0 y no podría abrir cajas.
-- El valor vive en un solo lugar por entorno; si cambia en Dart, cambia aquí.
-- ============================================================================

create or replace function public.credit_welcome_gotas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.credit_gotas(new.id, 450, 'Bienvenida a Biffy');
  return new;
end;
$$;

drop trigger if exists on_profile_created_welcome on public.profiles;
create trigger on_profile_created_welcome
  after insert on public.profiles
  for each row execute function public.credit_welcome_gotas();

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0010_realtime.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0010 · Realtime
-- ============================================================================
-- Supabase no publica tablas nuevas por defecto: hay que agregarlas a la
-- publicación `supabase_realtime` para recibir INSERT/UPDATE/DELETE.
--
-- Es opcional: si falla, la app sigue funcionando con la caché hidratada y
-- refresca al reabrir.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array['branches', 'dishes', 'orders', 'order_events'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
      raise notice 'Realtime habilitado para public.%.', t;
    exception
      when duplicate_object then
        null; -- ya estaba publicada
      when undefined_object then
        raise notice 'No existe la publicación supabase_realtime; se omite %.', t;
    end;
  end loop;
end $$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0011_branch_couriers.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0011 · Sedes visibles desde el primer día
-- ============================================================================
-- `isReachable` (lib/domain/catalog_rules.dart) exige `couriersNearby > 0`.
-- Mientras el catálogo no calcule la presencia real de repartidores, una sede
-- nueva nace invisible. Este valor por defecto evita ese pie de banco; en la
-- fase 2c se reemplaza por el conteo real de repartidores online.
-- ============================================================================

alter table public.branches
  alter column couriers_nearby set default 1;

update public.branches
   set couriers_nearby = 1
 where couriers_nearby = 0;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0012_box_items.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0012 · Cajas configurables por restaurante y límites por recompensa
-- ============================================================================
-- Cambios:
--   1. Cada recompensa define su enfriamiento y su límite diario en la base,
--      para poder ajustarlos sin tocar código.
--   2. Los restaurantes pueden meter y sacar SUS platos de una caja.
--   3. El sorteo usa primero los platos de los restaurantes y, si no hay,
--      cae a los premios de plataforma.
--
-- Reglas pedidas (configurables en `gotas_rewards`):
--   · Caja de 5 Gotas      -> ilimitada (cooldown_hours = 0)
--   · Resto de recompensas -> cada 12 horas (cooldown_hours = 12)
--   · La caja más grande   -> cada 24 horas (cooldown_hours = 24)
-- ============================================================================

-- ------------------------------------------------------- Configuración
alter table public.gotas_rewards
  add column if not exists cooldown_hours int not null default 0
    check (cooldown_hours >= 0);
alter table public.gotas_rewards
  add column if not exists daily_limit int
    check (daily_limit is null or daily_limit > 0);
alter table public.gotas_rewards
  add column if not exists merchant_managed boolean not null default false;
alter table public.gotas_rewards
  add column if not exists sort int not null default 0;

comment on column public.gotas_rewards.cooldown_hours is
  'Horas mínimas entre dos canjes del mismo usuario. 0 = sin límite.';
comment on column public.gotas_rewards.daily_limit is
  'Canjes máximos por usuario en 24 h. NULL = sin límite.';
comment on column public.gotas_rewards.merchant_managed is
  'Si es true, los restaurantes pueden meter sus platos en la caja.';

-- ------------------------------------------------- Productos dentro de caja
create table if not exists public.box_items (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid not null references public.gotas_rewards (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete cascade,
  dish_id uuid not null references public.dishes (id) on delete cascade,
  quantity int not null default 1 check (quantity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (reward_id, branch_id, dish_id)
);

create index if not exists box_items_reward_idx
  on public.box_items (reward_id) where is_active;
create index if not exists box_items_branch_idx
  on public.box_items (branch_id);

drop trigger if exists set_updated_at on public.box_items;
create trigger set_updated_at
  before update on public.box_items
  for each row execute function public.touch_updated_at();

-- Premio entregado cuando sale un plato de restaurante.
alter table public.reward_redemptions
  add column if not exists prize_dish_id uuid
    references public.dishes (id) on delete set null;
alter table public.reward_redemptions
  add column if not exists prize_branch_id uuid
    references public.branches (id) on delete set null;

-- ------------------------------------------------------------------- RLS
alter table public.box_items enable row level security;

drop policy if exists box_items_read on public.box_items;
create policy box_items_read on public.box_items
  for select to anon, authenticated using (is_active);

drop policy if exists box_items_write on public.box_items;
create policy box_items_write on public.box_items
  for all to authenticated
  using (public.is_my_branch(branch_id))
  with check (public.is_my_branch(branch_id));

grant select on public.box_items to anon, authenticated;

-- ------------------------------------------------------- Canje con límites
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
  v_prize public.gotas_reward_prizes;
  v_prize_id uuid;
  v_dish_id uuid;
  v_branch_id uuid;
  v_item_label text;
  v_total int;
  v_roll numeric;
  v_used int;
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

  -- Enfriamiento configurable (0 = ilimitado).
  if v_reward.cooldown_hours > 0 and exists (
    select 1 from public.reward_redemptions r
     where r.user_id = v_uid
       and r.reward_id = v_reward.id
       and r.created_at > now() - make_interval(hours => v_reward.cooldown_hours)
  ) then
    return jsonb_build_object(
      'result', 'cooldown',
      'cooldown_hours', v_reward.cooldown_hours
    );
  end if;

  -- Límite diario opcional.
  if v_reward.daily_limit is not null then
    select count(*) into v_used
      from public.reward_redemptions r
     where r.user_id = v_uid
       and r.reward_id = v_reward.id
       and r.created_at > now() - interval '24 hours';
    if v_used >= v_reward.daily_limit then
      return jsonb_build_object('result', 'daily_limit');
    end if;
  end if;

  -- Bloquea el perfil: dos canjes simultáneos no pueden gastar de más.
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

  -- 1) Platos que los restaurantes metieron en la caja.
  if v_reward.merchant_managed then
    select bi.dish_id, bi.branch_id, d.name
      into v_dish_id, v_branch_id, v_item_label
      from public.box_items bi
      join public.dishes d on d.id = bi.dish_id
      join public.branches b on b.id = bi.branch_id
     where bi.reward_id = v_reward.id
       and bi.is_active
       and d.active
       and d.deleted_at is null
       and b.deleted_at is null
     order by random()
     limit 1;
  end if;

  -- 2) Si no hay platos, premios de plataforma (descuentos, envío, boleto).
  if v_dish_id is null and v_reward.reward_type in ('mystery_box', 'monthly_raffle') then
    select coalesce(sum(weight), 0) into v_total
      from public.gotas_reward_prizes
     where reward_id = v_reward.id and is_active;

    if v_total > 0 then
      v_roll := random() * v_total;
      select p.id into v_prize_id
        from (
          select id, sum(weight) over (order by id) as cum
            from public.gotas_reward_prizes
           where reward_id = v_reward.id and is_active
        ) p
       where p.cum >= v_roll
       order by p.cum
       limit 1;

      if v_prize_id is not null then
        select * into v_prize
          from public.gotas_reward_prizes
         where id = v_prize_id;
      end if;
    end if;
  end if;

  insert into public.reward_redemptions (
    user_id, reward_id, gotas_spent,
    prize_id, prize_label, prize_type, prize_amount,
    prize_dish_id, prize_branch_id
  ) values (
    v_uid, v_reward.id, v_reward.gotas_cost,
    case when v_dish_id is null then v_prize.id else null end,
    coalesce(v_item_label, v_prize.label),
    case
      when v_dish_id is not null then 'product'
      else v_prize.prize_type
    end,
    case when v_dish_id is null then coalesce(v_prize.amount, 0) else 0 end,
    v_dish_id,
    v_branch_id
  )
  returning id into v_redemption;

  perform public.credit_gotas(
    v_uid, -v_reward.gotas_cost, 'Canje: ' || v_reward.name, null
  );

  return jsonb_build_object(
    'result', 'ok',
    'redemption_id', v_redemption,
    'reward', v_reward.code,
    'balance', v_balance - v_reward.gotas_cost,
    'prize', case
      when v_dish_id is not null then jsonb_build_object(
        'label', v_item_label,
        'type', 'product',
        'amount', 0,
        'dish_id', v_dish_id,
        'branch_id', v_branch_id
      )
      when v_prize.id is null then null
      else jsonb_build_object(
        'label', v_prize.label,
        'type', v_prize.prize_type,
        'amount', v_prize.amount
      )
    end
  );
end;
$$;

revoke all on function public.redeem_reward(jsonb) from public, anon;
grant execute on function public.redeem_reward(jsonb) to authenticated;

-- --------------------------------------------------------------- Catálogo
-- La caja de 5 es ilimitada; el resto se recarga cada 12 h; la grande cada 24 h.
insert into public.gotas_rewards
  (code, name, reward_type, gotas_cost, tier, draw_frequency, is_active,
   cooldown_hours, daily_limit, merchant_managed, sort)
values
  ('box_5', 'Caja básica', 'mystery_box', 5, null, null, true, 0, null, true, 1),
  ('free_shipping', 'Envío gratis', 'free_shipping', 10, null, null, true, 12, null, false, 2),
  ('box_25', 'Caja sorpresa', 'mystery_box', 25, 1, null, true, 12, null, true, 3),
  ('box_50', 'Caja premium', 'mystery_box', 50, 2, null, true, 12, null, true, 4),
  ('box_100', 'Caja sorteo', 'monthly_raffle', 100, 3, 'monthly', true, 24, null, true, 5)
on conflict (code) do update set
  name = excluded.name,
  reward_type = excluded.reward_type,
  gotas_cost = excluded.gotas_cost,
  tier = excluded.tier,
  draw_frequency = excluded.draw_frequency,
  is_active = excluded.is_active,
  cooldown_hours = excluded.cooldown_hours,
  daily_limit = excluded.daily_limit,
  merchant_managed = excluded.merchant_managed,
  sort = excluded.sort;

-- Premios de plataforma para la caja de 5 (se usan si ningún restaurante
-- ha metido platos todavía).
insert into public.gotas_reward_prizes
  (reward_id, code, label, prize_type, amount, weight)
select r.id, v.code, v.label, v.prize_type, v.amount, v.weight
from (values
  ('box_5', 'discount_1000', '$1.000 de descuento', 'discount', 1000, 50),
  ('box_5', 'free_shipping', 'Envío gratis', 'free_shipping', 0, 30),
  ('box_5', 'product_snack', 'Snack sorpresa', 'product', 0, 20)
) as v(reward_code, code, label, prize_type, amount, weight)
join public.gotas_rewards r on r.code = v.reward_code
on conflict (reward_id, code) do update set
  label = excluded.label,
  prize_type = excluded.prize_type,
  amount = excluded.amount,
  weight = excluded.weight,
  is_active = true;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0013_prize_claim.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0013 · Canje del premio en el restaurante
-- ============================================================================
-- Cuando una caja entrega un PLATO, el comprador recibe un código de 6
-- caracteres y 30 días para reclamarlo. El restaurante valida ese código y el
-- premio pasa a `used`. Así se cierra el ciclo:
--   restaurante mete el plato -> comprador abre la caja -> reclama en la sede.
-- ============================================================================

alter table public.reward_redemptions
  add column if not exists claim_code text;
alter table public.reward_redemptions
  add column if not exists expires_at timestamptz;

create unique index if not exists reward_redemptions_claim_idx
  on public.reward_redemptions (claim_code);

comment on column public.reward_redemptions.claim_code is
  'Código que el comprador muestra en la sede para reclamar un plato.';
comment on column public.reward_redemptions.expires_at is
  'Fecha límite para reclamar el premio. NULL en premios que no son platos.';

-- Los canjes anteriores a esta migración reciben un código si eran platos.
update public.reward_redemptions
   set claim_code = upper(substr(md5(id::text), 1, 6))
 where claim_code is null
   and prize_dish_id is not null;

-- ------------------------------------------------- Validación por el negocio

create or replace function public.use_reward_redemption(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_red public.reward_redemptions;
  v_dish text;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select * into v_red
    from public.reward_redemptions
   where upper(claim_code) = upper(trim(coalesce(p_code, '')))
     for update;

  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  if v_red.status <> 'granted' then
    return jsonb_build_object('result', 'already_used');
  end if;

  if v_red.expires_at is not null and v_red.expires_at < now() then
    update public.reward_redemptions set status = 'expired' where id = v_red.id;
    return jsonb_build_object('result', 'expired');
  end if;

  -- Solo el negocio dueño de la sede puede validar el premio.
  if v_red.prize_branch_id is null
     or not public.is_my_branch(v_red.prize_branch_id) then
    return jsonb_build_object('result', 'forbidden');
  end if;

  update public.reward_redemptions
     set status = 'used', used_at = now()
   where id = v_red.id;

  select d.name into v_dish
    from public.dishes d
   where d.id = v_red.prize_dish_id;

  return jsonb_build_object(
    'result', 'ok',
    'prize', coalesce(v_dish, v_red.prize_label),
    'code', v_red.claim_code
  );
end;
$$;

revoke all on function public.use_reward_redemption(text) from public, anon;
grant execute on function public.use_reward_redemption(text) to authenticated;

-- ------------------------------------------- Canje con código de reclamación

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
  v_prize public.gotas_reward_prizes;
  v_prize_id uuid;
  v_dish_id uuid;
  v_branch_id uuid;
  v_item_label text;
  v_claim text;
  v_total int;
  v_roll numeric;
  v_used int;
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

  -- Enfriamiento configurable (0 = ilimitado).
  if v_reward.cooldown_hours > 0 and exists (
    select 1 from public.reward_redemptions r
     where r.user_id = v_uid
       and r.reward_id = v_reward.id
       and r.created_at > now() - make_interval(hours => v_reward.cooldown_hours)
  ) then
    return jsonb_build_object(
      'result', 'cooldown',
      'cooldown_hours', v_reward.cooldown_hours
    );
  end if;

  -- Límite diario opcional.
  if v_reward.daily_limit is not null then
    select count(*) into v_used
      from public.reward_redemptions r
     where r.user_id = v_uid
       and r.reward_id = v_reward.id
       and r.created_at > now() - interval '24 hours';
    if v_used >= v_reward.daily_limit then
      return jsonb_build_object('result', 'daily_limit');
    end if;
  end if;

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

  -- 1) Platos que los restaurantes metieron en la caja.
  if v_reward.merchant_managed then
    select bi.dish_id, bi.branch_id, d.name
      into v_dish_id, v_branch_id, v_item_label
      from public.box_items bi
      join public.dishes d on d.id = bi.dish_id
      join public.branches b on b.id = bi.branch_id
     where bi.reward_id = v_reward.id
       and bi.is_active
       and d.active
       and d.deleted_at is null
       and b.deleted_at is null
     order by random()
     limit 1;
  end if;

  -- 2) Si no hay platos, premios de plataforma.
  if v_dish_id is null and v_reward.reward_type in ('mystery_box', 'monthly_raffle') then
    select coalesce(sum(weight), 0) into v_total
      from public.gotas_reward_prizes
     where reward_id = v_reward.id and is_active;

    if v_total > 0 then
      v_roll := random() * v_total;
      select p.id into v_prize_id
        from (
          select id, sum(weight) over (order by id) as cum
            from public.gotas_reward_prizes
           where reward_id = v_reward.id and is_active
        ) p
       where p.cum >= v_roll
       order by p.cum
       limit 1;

      if v_prize_id is not null then
        select * into v_prize
          from public.gotas_reward_prizes
         where id = v_prize_id;
      end if;
    end if;
  end if;

  -- Código de reclamación solo para platos.
  if v_dish_id is not null then
    v_claim := upper(substr(md5(gen_random_uuid()::text), 1, 6));
  end if;

  insert into public.reward_redemptions (
    user_id, reward_id, gotas_spent,
    prize_id, prize_label, prize_type, prize_amount,
    prize_dish_id, prize_branch_id,
    claim_code, expires_at
  ) values (
    v_uid, v_reward.id, v_reward.gotas_cost,
    case when v_dish_id is null then v_prize.id else null end,
    coalesce(v_item_label, v_prize.label),
    case when v_dish_id is not null then 'product' else v_prize.prize_type end,
    case when v_dish_id is null then coalesce(v_prize.amount, 0) else 0 end,
    v_dish_id,
    v_branch_id,
    v_claim,
    case when v_dish_id is not null then now() + interval '30 days' end
  )
  returning id into v_redemption;

  perform public.credit_gotas(
    v_uid, -v_reward.gotas_cost, 'Canje: ' || v_reward.name, null
  );

  return jsonb_build_object(
    'result', 'ok',
    'redemption_id', v_redemption,
    'reward', v_reward.code,
    'balance', v_balance - v_reward.gotas_cost,
    'prize', case
      when v_dish_id is not null then jsonb_build_object(
        'label', v_item_label,
        'type', 'product',
        'amount', 0,
        'dish_id', v_dish_id,
        'branch_id', v_branch_id,
        'claim_code', v_claim
      )
      when v_prize.id is null then null
      else jsonb_build_object(
        'label', v_prize.label,
        'type', v_prize.prize_type,
        'amount', v_prize.amount
      )
    end
  );
end;
$$;

revoke all on function public.redeem_reward(jsonb) from public, anon;
grant execute on function public.redeem_reward(jsonb) to authenticated;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0014_geo_guards.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0014 · Geografía: puntos de sede, polígonos de campus y validación en pedidos
-- ============================================================================
-- 1) Sincroniza `branches.location` desde lat/lng (trigger + backfill).
-- 2) Siembra polígonos de campus APROXIMADOS para las 4 universidades.
--    Son rectángulos de demostración: reemplázalos por el contorno real con
--    `update universities set boundary_polygon = st_geomfromgeojson('...')`.
-- 3) `place_order` valida con PostGIS:
--      · la dirección debe caer dentro de `radius_km` (ST_DWithin), y
--      · si la sede es `campus_delivery_only`, dentro del polígono del campus.
--    La regla de visibilidad del cliente no cambia: esto es defensa en el
--    servidor para que un pedido no se cree fuera de cobertura.
-- ============================================================================

-- ------------------------------------------------ Punto de la sede desde lat/lng
create or replace function public.sync_branch_location()
returns trigger
language plpgsql
as $$
begin
  if new.lat is not null and new.lng is not null then
    new.location := st_setsrid(
      st_makepoint(new.lng::float8, new.lat::float8),
      4326
    );
  end if;
  return new;
end;
$$;

drop trigger if exists sync_location on public.branches;
create trigger sync_location
  before insert or update on public.branches
  for each row execute function public.sync_branch_location();

update public.branches
   set location = st_setsrid(st_makepoint(lng::float8, lat::float8), 4326)
 where location is null
   and lat is not null
   and lng is not null;

-- ------------------------------------------------- Polígonos de campus (demo)
-- Rectángulo alrededor de los puntos de entrega del campus. Para las
-- universidades sin puntos se usa un centro aproximado.
do $$
declare
  u record;
  v_min_lng numeric;
  v_max_lng numeric;
  v_min_lat numeric;
  v_max_lat numeric;
begin
  for u in select id from public.universities loop
    select min(lng), max(lng), min(lat), max(lat)
      into v_min_lng, v_max_lng, v_min_lat, v_max_lat
      from public.delivery_points
     where campus_id = u.id;

    -- Centros aproximados cuando el campus no tiene puntos de entrega.
    if v_min_lng is null then
      case u.id
        when 'andes' then
          v_min_lng := -74.0695; v_max_lng := -74.0615;
          v_min_lat := 4.5975;  v_max_lat := 4.6055;
        when 'javeriana' then
          v_min_lng := -74.0682; v_max_lng := -74.0602;
          v_min_lat := 4.6236;  v_max_lat := 4.6316;
        else
          continue;
      end case;
    else
      -- Margen de ~450 m alrededor de los puntos del campus.
      v_min_lng := v_min_lng - 0.004;
      v_max_lng := v_max_lng + 0.004;
      v_min_lat := v_min_lat - 0.004;
      v_max_lat := v_max_lat + 0.004;
    end if;

    update public.universities
       set boundary_polygon = st_setsrid(
         st_makeenvelope(
           v_min_lng::float8, v_min_lat::float8,
           v_max_lng::float8, v_max_lat::float8,
           4326
         ),
         4326
       )
     where id = u.id
       and boundary_polygon is null;
  end loop;
end $$;

-- --------------------------------------- Validación geográfica en place_order
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

  -- Punto de entrega de la dirección.
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

revoke all on function public.place_order(jsonb) from public, anon;
grant execute on function public.place_order(jsonb) to authenticated;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0015_campus_polygons.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0015 · Polígono real del campus Icesi (OpenStreetMap)
-- ============================================================================
-- Fuente: OpenStreetMap, relation/6784907 (© colaboradores de OSM, ODbL).
--
-- FILTRO: este trabajo es solo para campus de Cali. La migración aplica el
-- polígono únicamente si la universidad tiene `city = 'Cali'` y valida que la
-- geometría caiga dentro del área metropolitana de Cali. Las universidades de
-- otras ciudades quedan sin polígono y usan el respaldo por `campus_id`.
--
-- El export que compartió el equipo es de Cali: de nuestras cuatro
-- universidades solo Icesi tiene polígono ahí. La Javeriana del archivo es la
-- sede de Cali, distinta de la fila `javeriana` (Bogotá) del catálogo, así que
-- no se aplica.
-- ============================================================================

do $$
declare
  v_geom geometry;
  v_fixed geometry;
  v_area numeric;
begin
  -- Anillo exterior del campus (cerrado, coordenadas [lng, lat]).
  v_geom := st_setsrid(
    st_geomfromgeojson('{
      "type": "Polygon",
      "coordinates": [[
        [-76.5282002, 3.3386242],
        [-76.5282327, 3.3397619],
        [-76.5282701, 3.3406067],
        [-76.5273123, 3.3406012],
        [-76.5272969, 3.3411561],
        [-76.5272786, 3.3417826],
        [-76.5282533, 3.3418052],
        [-76.5282393, 3.3424088],
        [-76.5272563, 3.3423941],
        [-76.5272443, 3.3426985],
        [-76.5275395, 3.3426964],
        [-76.5275458, 3.3433883],
        [-76.5290493, 3.3432815],
        [-76.5291687, 3.343273],
        [-76.529648, 3.3432389],
        [-76.5300269, 3.343212],
        [-76.5302486, 3.3431969],
        [-76.5304627, 3.3431811],
        [-76.5306312, 3.3431186],
        [-76.5307462, 3.3430382],
        [-76.5308097, 3.3429639],
        [-76.5308269, 3.3429371],
        [-76.530887, 3.3424907],
        [-76.530935, 3.3424008],
        [-76.5309636, 3.3420806],
        [-76.531001, 3.3413804],
        [-76.5310091, 3.3412676],
        [-76.5310177, 3.3411545],
        [-76.5311915, 3.339794],
        [-76.5304425, 3.339819],
        [-76.529524, 3.3398743],
        [-76.5292166, 3.339917],
        [-76.5291506, 3.3387198],
        [-76.5291401, 3.3385876],
        [-76.5288588, 3.3385985],
        [-76.5287545, 3.3386027],
        [-76.5286721, 3.3386058],
        [-76.5282002, 3.3386242]
      ]]
    }'),
    4326
  );

  -- Si OSM devuelve un anillo con problemas, se repara; el tipo debe ser Polygon.
  v_fixed := st_makevalid(v_geom);
  if geometrytype(v_fixed) <> 'POLYGON' then
    v_fixed := st_geometryn(v_fixed, 1);
  end if;

  -- Filtro geográfico: el polígono debe caer dentro del área de Cali.
  if not st_within(
    v_fixed,
    st_makeenvelope(-76.75, 3.25, -76.35, 3.60, 4326)
  ) then
    raise exception 'El polígono de Icesi no está dentro del área de Cali.';
  end if;

  -- Filtro por ciudad: solo se aplica a universidades marcadas como Cali.
  update public.universities
     set boundary_polygon = v_fixed
   where id = 'icesi'
     and city = 'Cali';

  if not exists (
    select 1 from public.universities
     where id = 'icesi'
       and city = 'Cali'
       and boundary_polygon is not null
  ) then
    raise warning 'No se aplicó el polígono: Icesi no está marcada como Cali.';
  end if;

  -- Campus de otras ciudades: se prefiere el respaldo por `campus_id`.
  update public.universities
     set boundary_polygon = null
   where id in ('unal', 'andes', 'javeriana');

  v_area := round(
    (select st_area(boundary_polygon::geography)
       from public.universities
      where id = 'icesi')
  );

  raise notice 'Icesi: % m² · válido = %',
    v_area,
    (select st_isvalid(boundary_polygon) from public.universities where id = 'icesi');

  if exists (
    select 1
      from public.delivery_points p
      join public.universities u on u.id = 'icesi'
     where p.campus_id = 'icesi'
       and not st_covers(u.boundary_polygon, p.location)
  ) then
    raise warning 'Hay puntos de entrega de Icesi fuera del polígono.';
  else
    raise notice 'Todos los puntos de entrega de Icesi caen dentro del campus.';
  end if;
end $$;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0016_survey_reward.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0016 · Recompensa de la encuesta de preferencias
-- ============================================================================
-- Acredita 300 Gotas una sola vez cuando el comprador completa la encuesta.
-- La app marcaba `surveyRewarded` solo en memoria; con este RPC el saldo y la
-- bandera quedan en la base y no se puede reclamar dos veces.
-- ============================================================================

create or replace function public.complete_survey()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rewarded boolean;
  v_balance int;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  -- Bloquea la fila: dos peticiones simultáneas no pueden acreditar dos veces.
  select rewarded into v_rewarded
    from public.preferences
   where user_id = v_uid
     for update;

  if not found then
    return jsonb_build_object('result', 'no_preferences');
  end if;

  if v_rewarded then
    return jsonb_build_object('result', 'already_rewarded');
  end if;

  update public.preferences
     set rewarded = true,
         completed = true
   where user_id = v_uid;

  perform public.credit_gotas(
    v_uid, 300, 'Completaste tus preferencias', null
  );

  select gotas into v_balance from public.profiles where id = v_uid;

  return jsonb_build_object(
    'result', 'ok',
    'awarded', 300,
    'balance', v_balance
  );
end;
$$;

revoke all on function public.complete_survey() from public, anon;
grant execute on function public.complete_survey() to authenticated;

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0017_coupons_notifications.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0017 · Cupones desde premios de caja y notificaciones propias
-- ============================================================================
-- 1) Cada premio de descuento o envío gratis genera un cupón de un solo uso
--    ligado al comprador, para que el premio se pueda aplicar en el checkout.
-- 2) El usuario autenticado puede guardar y leer sus propias notificaciones.
-- ============================================================================

-- ------------------------------------------------ Premio -> cupón utilizable
create or replace function public.create_coupon_for_redemption()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coupon uuid;
  v_code text;
begin
  if new.prize_type is null
     or new.prize_type not in ('discount', 'free_shipping') then
    return new;
  end if;

  v_code := 'PZ-' || upper(left(new.id::text, 8));

  -- Idempotente por si el trigger se volviera a ejecutar.
  if exists (select 1 from public.coupons where code = v_code) then
    return new;
  end if;

  insert into public.coupons (
    code, title, kind, amount, max_uses, used_count, active, valid_until
  ) values (
    v_code,
    coalesce(new.prize_label, 'Premio de caja'),
    case
      when new.prize_type = 'free_shipping'
        then 'free_delivery'::public.coupon_kind
      else 'fixed'::public.coupon_kind
    end,
    case
      when new.prize_type = 'free_shipping' then 0
      else coalesce(new.prize_amount, 0)
    end,
    1,
    0,
    true,
    now() + interval '30 days'
  )
  returning id into v_coupon;

  insert into public.user_coupons (user_id, coupon_id)
  values (new.user_id, v_coupon);

  return new;
end;
$$;

drop trigger if exists reward_redemption_coupon on public.reward_redemptions;
create trigger reward_redemption_coupon
  after insert on public.reward_redemptions
  for each row execute function public.create_coupon_for_redemption();

-- ------------------------------------------------------- Notificaciones
drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and audience = 'user:' || auth.uid()::text
  );

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- 0099_verify.sql
-- >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
-- ============================================================================
-- 0007 · Verificación final
-- ============================================================================
-- Si algo quedó a medias, este bloque falla con un mensaje claro en vez de
-- dejar la base silenciosamente incompleta.
-- ============================================================================

do $$
declare
  v_table text;
  v_col text;
  v_missing text := '';
  v_legacy text;
  v_tables int;
  v_policies int;
  v_functions int;
  expected_tables text[] := array[
    '_biffy_meta', 'universities', 'delivery_points', 'categories', 'profiles',
    'businesses', 'branches', 'dishes', 'dish_options', 'preferences',
    'app_settings', 'addresses', 'gotas_ledger', 'coupons', 'user_coupons',
    'favorite_dishes', 'favorite_branches', 'notifications', 'courier_profiles',
    'orders', 'order_items', 'order_events', 'order_declines', 'reviews',
    'gotas_rewards', 'reward_redemptions', 'gotas_reward_prizes', 'box_items'
  ];
  expected_columns text[][] := array[
    ['dishes', 'active'], ['dishes', 'sold_out'], ['dishes', 'branch_id'],
    ['branches', 'paused'], ['orders', 'delivery_code'], ['orders', 'gotas_used'],
    ['profiles', 'gotas'], ['profiles', 'business_id'],
    ['gotas_rewards', 'cooldown_hours'], ['box_items', 'reward_id'],
    ['reward_redemptions', 'claim_code'],
    ['branches', 'location'], ['universities', 'boundary_polygon']
  ];
  expected_functions text[] := array[
    'place_order', 'restaurant_accept', 'restaurant_reject', 'restaurant_ready',
    'buyer_cancel', 'courier_accept', 'courier_decline', 'courier_pickup',
    'courier_deliver', 'verify_university', 'register_business', 'redeem_reward'
  ];
begin
  foreach v_table in array expected_tables loop
    if not exists (
      select 1 from pg_tables
      where schemaname = 'public' and tablename = v_table
    ) then
      v_missing := v_missing || v_table || ' ';
    end if;
  end loop;

  if v_missing <> '' then
    raise exception 'Faltan tablas en public: %', v_missing;
  end if;

  for i in 1 .. array_length(expected_columns, 1) loop
    v_table := expected_columns[i][1];
    v_col := expected_columns[i][2];
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = v_col
    ) then
      raise exception 'A la tabla public.% le falta la columna %', v_table, v_col;
    end if;
  end loop;

  foreach v_table in array expected_functions loop
    if not exists (
      select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_table
    ) then
      raise exception 'Falta la función public.%', v_table;
    end if;
  end loop;

  -- PostGIS debe seguir intacto (nuestra limpieza no toca objetos de extensiones).
  if exists (select 1 from pg_extension where extname = 'postgis') then
    if not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'spatial_ref_sys'
    ) then
      raise exception 'PostGIS quedó dañado: falta public.spatial_ref_sys';
    end if;

    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'universities'
        and column_name = 'boundary_polygon'
    ) then
      raise exception 'Falta la columna universities.boundary_polygon (PostGIS)';
    end if;
  end if;

  select count(*) into v_tables from pg_tables where schemaname = 'public';
  select count(*) into v_policies from pg_policies where schemaname = 'public';
  select count(*) into v_functions
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public';

  select string_agg(tablename, ', ' order by tablename) into v_legacy
  from pg_tables
  where schemaname = 'public' and left(tablename, 7) = 'legacy_';

  if v_legacy is not null then
    raise notice 'Tablas antiguas conservadas con RLS: %', v_legacy;
  end if;

  if not exists (select 1 from public.gotas_rewards) then
    raise warning 'public.gotas_rewards quedó vacía; revisa 0006_seed_reference.sql';
  end if;

  if exists (
    select 1
    from public.gotas_rewards r
    where r.reward_type in ('mystery_box', 'monthly_raffle')
      and not exists (
        select 1
        from public.gotas_reward_prizes p
        where p.reward_id = r.id and p.is_active
      )
  ) then
    raise warning 'Hay cajas sin premios activos; revisa 0008_reward_boxes.sql';
  end if;

  raise notice 'Biffy OK · % tablas · % políticas RLS · % funciones en public',
    v_tables, v_policies, v_functions;
end $$;

