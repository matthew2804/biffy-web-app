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
