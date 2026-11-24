-- ============================================================================
-- 0024 · Envío gratis cuesta 5 Gotas
-- ============================================================================
-- La HU-4 fija el canje directo de envío gratis en 5 Gotas (0012 lo había
-- subido a 10). El enfriamiento de 12 h se mantiene.
-- ============================================================================

update public.gotas_rewards
   set gotas_cost = 5
 where code = 'free_shipping';
