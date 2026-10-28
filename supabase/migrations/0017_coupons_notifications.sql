-- ============================================================================
-- 0017 · Cupones desde premios de caja y notificaciones propias
-- ============================================================================
-- 1) Cada premio de descuento o envío gratis genera un cupón de un solo uso
--    ligado al comprador, para que el premio se pueda aplicar en el checkout.
-- 2) El usuario autenticado puede guardar y leer sus propias notificaciones.
-- ============================================================================

-- ------------------------------------------------ Premio -> cupón utilizable
create or replace function public.create_coupon_for_redemption()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_coupon uuid;
  v_code text;
begin
  if new.prize_type is null
     or new.prize_type not in ('discount', 'free_shipping') then
    return new;
  end if;

  v_code := 'PZ-' || upper(left(new.id::text, 8));

  -- Idempotente por si el trigger se volviera a ejecutar.
  if exists (select 1 from public.coupons where code = v_code) then
    return new;
  end if;

  insert into public.coupons (
    code, title, kind, amount, max_uses, used_count, active, valid_until
  ) values (
    v_code,
    coalesce(new.prize_label, 'Premio de caja'),
    case
      when new.prize_type = 'free_shipping'
        then 'free_delivery'::public.coupon_kind
      else 'fixed'::public.coupon_kind
    end,
    case
      when new.prize_type = 'free_shipping' then 0
      else coalesce(new.prize_amount, 0)
    end,
    1,
    0,
    true,
    now() + interval '30 days'
  )
  returning id into v_coupon;

  insert into public.user_coupons (user_id, coupon_id)
  values (new.user_id, v_coupon);

  return new;
end;
$$;

drop trigger if exists reward_redemption_coupon on public.reward_redemptions;
create trigger reward_redemption_coupon
  after insert on public.reward_redemptions
  for each row execute function public.create_coupon_for_redemption();

-- ------------------------------------------------------- Notificaciones
drop policy if exists notifications_insert on public.notifications;
create policy notifications_insert on public.notifications
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and audience = 'user:' || auth.uid()::text
  );

drop policy if exists notifications_update on public.notifications;
create policy notifications_update on public.notifications
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
