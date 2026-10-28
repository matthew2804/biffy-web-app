-- ============================================================================
-- 0015 · Polígono real del campus Icesi (OpenStreetMap)
-- ============================================================================
-- Fuente: OpenStreetMap, relation/6784907 (© colaboradores de OSM, ODbL).
-- El export que compartió el equipo es de Cali: de nuestras cuatro
-- universidades solo Icesi tiene polígono ahí. La Javeriana del archivo es la
-- sede de Cali, distinta de la fila `javeriana` (Bogotá) del catálogo, así que
-- no se aplica.
--
-- Para UNAL y Andes (Bogotá) y Javeriana (Bogotá) se deja el polígono en null:
-- la geocerca cae al respaldo por `campus_id` hasta que exista su GeoJSON.
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

  update public.universities
     set boundary_polygon = v_fixed
   where id = 'icesi';

  -- Campus sin GeoJSON: se prefiere el respaldo por `campus_id`.
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
