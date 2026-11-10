-- ============================================================================
-- 0023 · credit_gotas nunca descuadra el saldo
-- ============================================================================
-- Antes hacía `greatest(0, gotas + amount)`: si alguna vez se descontaba más
-- de lo que había, el saldo quedaba en 0 pero el ledger guardaba el negativo
-- completo, y profiles.gotas dejaba de ser la suma de gotas_ledger.
-- Ahora falla (y revierte todo el RPC que la llamó) en vez de recortar.
-- ============================================================================

create or replace function public.credit_gotas(
  p_user uuid,
  p_amount int,
  p_reason text,
  p_order uuid default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_balance int;
begin
  if p_amount = 0 then
    return;
  end if;
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'credit_gotas: el movimiento necesita un motivo';
  end if;

  select gotas into v_balance
    from public.profiles
   where id = p_user
     for update;
  if not found then
    raise exception 'credit_gotas: perfil % no existe', p_user;
  end if;
  if v_balance + p_amount < 0 then
    raise exception 'insufficient_gotas: saldo %, movimiento %', v_balance, p_amount;
  end if;

  perform set_config('biffy.internal', '1', true);

  insert into public.gotas_ledger (user_id, amount, reason, order_id)
  values (p_user, p_amount, p_reason, p_order);

  update public.profiles
     set gotas = v_balance + p_amount
   where id = p_user;

  perform set_config('biffy.internal', '0', true);
end;
$$;

revoke all on function public.credit_gotas(uuid, int, text, uuid) from public, anon, authenticated;
