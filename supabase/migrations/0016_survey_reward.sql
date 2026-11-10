-- 0016 · Recompensa de la encuesta de preferencias
-- ============================================================================
-- Acredita 300 Gotas una sola vez cuando el comprador completa la encuesta.
-- La app marcaba `surveyRewarded` solo en memoria; con este RPC el saldo y la
-- bandera quedan en la base y no se puede reclamar dos veces.
-- ============================================================================

create or replace function public.complete_survey()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_rewarded boolean;
  v_balance int;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  -- Bloquea la fila: dos peticiones simultáneas no pueden acreditar dos veces.
  select rewarded into v_rewarded
    from public.preferences
   where user_id = v_uid
     for update;

  if not found then
    return jsonb_build_object('result', 'no_preferences');
  end if;

  if v_rewarded then
    return jsonb_build_object('result', 'already_rewarded');
  end if;

  update public.preferences
     set rewarded = true,
         completed = true
   where user_id = v_uid;

  perform public.credit_gotas(
    v_uid, 300, 'Completaste tus preferencias', null
  );

  select gotas into v_balance from public.profiles where id = v_uid;

  return jsonb_build_object(
    'result', 'ok',
    'awarded', 300,
    'balance', v_balance
  );
end;
$$;

revoke all on function public.complete_survey() from public, anon;
grant execute on function public.complete_survey() to authenticated;
