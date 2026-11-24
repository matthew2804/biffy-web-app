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
