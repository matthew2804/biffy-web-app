-- ============================================================================
-- Evidencia de la HU-1 · ejecutar en el SQL Editor de Supabase
-- ============================================================================
-- Proyecto: jwdzpwsfwtkdeeuceaco
-- Solo lectura: no crea ni modifica nada.
--
-- Cómo usarlo:
--   1. Ejecuta primero supabase/migrations/0099_verify.sql y copia el aviso
--      "Biffy OK · N tablas · N políticas RLS · N funciones".
--   2. Pega este archivo completo y copia cada resultado en orden.
-- ============================================================================


-- 0) Resumen en una sola fila: úsalo para la captura de pantalla.
--    Devuelve el mismo texto que el aviso de 0099, pero como resultado de tabla.
select format(
  'Biffy OK · %s tablas · %s políticas RLS · %s funciones',
  (select count(*) from pg_tables where schemaname = 'public'),
  (select count(*) from pg_policies where schemaname = 'public'),
  (
    select count(*)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
  )
) as resultado;


-- 1) Las 28 tablas esperadas por 0099 y si tienen RLS activo.
with esperadas(tabla) as (
  values
    ('_biffy_meta'), ('universities'), ('delivery_points'), ('categories'),
    ('profiles'), ('businesses'), ('branches'), ('dishes'), ('dish_options'),
    ('preferences'), ('app_settings'), ('addresses'), ('gotas_ledger'),
    ('coupons'), ('user_coupons'), ('favorite_dishes'), ('favorite_branches'),
    ('notifications'), ('courier_profiles'), ('orders'), ('order_items'),
    ('order_events'), ('order_declines'), ('reviews'), ('gotas_rewards'),
    ('reward_redemptions'), ('gotas_reward_prizes'), ('box_items')
)
select
  e.tabla,
  coalesce(c.relrowsecurity, false) as rls_activo,
  exists (
    select 1 from pg_class x
    join pg_namespace n on n.oid = x.relnamespace
    where n.nspname = 'public' and x.relname = e.tabla and x.relkind = 'r'
  ) as existe
from esperadas e
left join pg_class c
  on c.relname = e.tabla
 and c.relnamespace = 'public'::regnamespace
order by e.tabla;


-- 2) Resumen: tablas físicas en public con y sin RLS (excluye legacy_*).
select
  count(*) filter (where c.relrowsecurity) as con_rls,
  count(*) filter (where not c.relrowsecurity) as sin_rls,
  count(*) as total
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and c.relname not like 'legacy\_%';


-- 3) Cantidad de políticas RLS y su reparto por tabla.
select count(*) as total_politicas
from pg_policies
where schemaname = 'public';

select tablename, count(*) as politicas
from pg_policies
where schemaname = 'public'
group by tablename
order by tablename;


-- 4) Datos semilla de referencia.
select 'universities' as tabla, count(*) as filas from public.universities
union all select 'delivery_points', count(*) from public.delivery_points
union all select 'categories', count(*) from public.categories
union all select 'gotas_rewards', count(*) from public.gotas_rewards
union all select 'gotas_reward_prizes', count(*) from public.gotas_reward_prizes
union all select 'branches', count(*) from public.branches
union all select 'dishes', count(*) from public.dishes
order by tabla;


-- 5) Cuentas demo: rol, Gotas, negocio y perfil de repartidor.
--    No imprime ids ni tokens.
select
  u.email,
  p.role,
  p.gotas,
  (p.business_id is not null) as tiene_negocio,
  exists (
    select 1 from public.courier_profiles cp where cp.user_id = u.id
  ) as tiene_perfil_repartidor,
  (
    select count(*) from public.gotas_ledger g where g.user_id = u.id
  ) as movimientos_gotas
from auth.users u
join public.profiles p on p.id = u.id
where lower(u.email) in (
  'diego.demo@icesi.edu.co',
  'andres.repartidor@demo.biffy.co',
  'qbano@demo.biffy.co'
)
order by u.email;


-- 6) Nadie debe tener más de una acreditación de bienvenida.
--    Resultado esperado: 0 filas.
select
  g.user_id,
  count(*) filter (where g.reason = 'Bienvenida a Biffy') as bienvenidas
from public.gotas_ledger g
group by g.user_id
having count(*) filter (where g.reason = 'Bienvenida a Biffy') > 1;


-- 7) Negocios sin sede (no debería haber ninguno tras el seed).
--    Resultado esperado: 0 filas.
select b.id, b.brand
from public.businesses b
where not exists (
  select 1 from public.branches br where br.business_id = b.id
);
