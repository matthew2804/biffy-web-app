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
