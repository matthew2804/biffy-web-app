-- ============================================================================
-- 0010 · Realtime
-- ============================================================================
-- Supabase no publica tablas nuevas por defecto: hay que agregarlas a la
-- publicación `supabase_realtime` para recibir INSERT/UPDATE/DELETE.
--
-- Es opcional: si falla, la app sigue funcionando con la caché hidratada y
-- refresca al reabrir.
-- ============================================================================

do $$
declare
  t text;
begin
  foreach t in array array['branches', 'dishes', 'orders', 'order_events'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
      raise notice 'Realtime habilitado para public.%.', t;
    exception
      when duplicate_object then
        null; -- ya estaba publicada
      when undefined_object then
        raise notice 'No existe la publicación supabase_realtime; se omite %.', t;
    end;
  end loop;
end $$;
