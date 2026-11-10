-- ============================================================================
-- Cuentas demo mínimas para correr supabase/tests/*.sql en un Postgres local
-- ============================================================================
-- En el proyecto real las crea tool/admin_seed.dart. Aquí solo existen para
-- que pruebas como hu3_order_cycle.sql encuentren a Diego, Andrés y Qbano.
-- No se aplica en Supabase.
-- ============================================================================

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000de01', 'diego.demo@icesi.edu.co',
   '{"role":"buyer","full_name":"Diego (demo)"}'),
  ('00000000-0000-0000-0000-00000000de02', 'andres.repartidor@demo.biffy.co',
   '{"role":"courier","full_name":"Andrés (demo)"}'),
  ('00000000-0000-0000-0000-00000000de03', 'qbano@demo.biffy.co',
   '{"role":"restaurant","full_name":"Qbano (demo)"}')
on conflict (id) do nothing;

insert into public.businesses (id, owner_id, brand)
values ('00000000-0000-0000-0000-00000000de10',
        '00000000-0000-0000-0000-00000000de03', 'Qbano')
on conflict (id) do nothing;

insert into public.branches (id, business_id, name, campus_id, lat, lng)
values ('00000000-0000-0000-0000-00000000de11',
        '00000000-0000-0000-0000-00000000de10', 'Qbano Icesi', 'icesi',
        3.3410, -76.5300)
on conflict (id) do nothing;

insert into public.courier_profiles (user_id, full_name, doc_number, vehicle, online)
values ('00000000-0000-0000-0000-00000000de02', 'Andrés (demo)', '1000000000',
        'moto', true)
on conflict (user_id) do nothing;
