-- ============================================================================
-- 0009 · Gotas de bienvenida
-- ============================================================================
-- Al crear el perfil se acreditan 450 Gotas, igual que el modo demo
-- (`kWelcomeGotas` en lib/core/constants/catalog_constants.dart).
--
-- Sin esto, una cuenta nueva llegaría con 0 y no podría abrir cajas.
-- El valor vive en un solo lugar por entorno; si cambia en Dart, cambia aquí.
-- ============================================================================

create or replace function public.credit_welcome_gotas()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.credit_gotas(new.id, 450, 'Bienvenida a Biffy');
  return new;
end;
$$;

drop trigger if exists on_profile_created_welcome on public.profiles;
create trigger on_profile_created_welcome
  after insert on public.profiles
  for each row execute function public.credit_welcome_gotas();
