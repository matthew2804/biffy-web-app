-- ============================================================================
-- Limpieza de los datos temporales creados por las pruebas de la HU-1
-- ============================================================================
-- Ejecutar en el SQL Editor después de la sustentación.
-- Borra solo las cuentas y el negocio de prueba `hu1.qa.*`; no toca las
-- cuentas demo ni el catálogo real.
-- ============================================================================

-- 1) Negocio temporal (sus sedes se borran en cascada).
delete from public.businesses
where brand = 'QA HU-1'
  and owner_id in (
    select id from auth.users
    where email like 'hu1.qa.%@demo.biffy.co'
  );

-- 2) Cuentas temporales (perfil, Gotas, direcciones y favoritos en cascada).
delete from auth.users
where email like 'hu1.qa.%@demo.biffy.co';

-- 3) Comprobación: debe devolver 0.
select count(*) as cuentas_qa_restantes
from auth.users
where email like 'hu1.qa.%@demo.biffy.co';
