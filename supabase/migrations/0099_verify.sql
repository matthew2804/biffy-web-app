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
    ['reward_redemptions', 'claim_code']
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
