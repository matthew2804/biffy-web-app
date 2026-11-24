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
