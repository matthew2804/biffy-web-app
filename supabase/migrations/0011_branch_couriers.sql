-- ============================================================================
-- 0011 · Sedes visibles desde el primer día
-- ============================================================================
-- `isReachable` (lib/domain/catalog_rules.dart) exige `couriersNearby > 0`.
-- Mientras el catálogo no calcule la presencia real de repartidores, una sede
-- nueva nace invisible. Este valor por defecto evita ese pie de banco; en la
-- fase 2c se reemplaza por el conteo real de repartidores online.
-- ============================================================================

alter table public.branches
  alter column couriers_nearby set default 1;

update public.branches
   set couriers_nearby = 1
 where couriers_nearby = 0;
