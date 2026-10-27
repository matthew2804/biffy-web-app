-- ============================================================================
-- Biffy · Bootstrap de base de datos (generado)
-- ============================================================================
-- Uso: Supabase Dashboard -> SQL Editor -> New query -> pegar todo -> Run.
--
-- Se genera concatenando supabase/migrations/*.sql. No editar a mano.
-- Proyecto: jwdzpwsfwtkdeeuceaco
-- Generado: 2026-10-27 10:11
--
-- AVISO: la migración 0000 reemplaza las tablas de public. Las tablas con
-- filas NO se borran: se conservan como legacy_<nombre> con RLS activo.
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
    'gotas_rewards', 'reward_redemptions', 'gotas_reward_prizes'
  ];
  expected_columns text[][] := array[
    ['dishes', 'active'], ['dishes', 'sold_out'], ['dishes', 'branch_id'],
    ['branches', 'paused'], ['orders', 'delivery_code'], ['orders', 'gotas_used'],
    ['profiles', 'gotas'], ['profiles', 'business_id']
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

