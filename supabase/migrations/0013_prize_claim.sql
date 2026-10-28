-- ============================================================================
-- 0013 · Canje del premio en el restaurante
-- ============================================================================
-- Cuando una caja entrega un PLATO, el comprador recibe un código de 6
-- caracteres y 30 días para reclamarlo. El restaurante valida ese código y el
-- premio pasa a `used`. Así se cierra el ciclo:
--   restaurante mete el plato -> comprador abre la caja -> reclama en la sede.
-- ============================================================================

alter table public.reward_redemptions
  add column if not exists claim_code text;
alter table public.reward_redemptions
  add column if not exists expires_at timestamptz;

create unique index if not exists reward_redemptions_claim_idx
  on public.reward_redemptions (claim_code);

comment on column public.reward_redemptions.claim_code is
  'Código que el comprador muestra en la sede para reclamar un plato.';
comment on column public.reward_redemptions.expires_at is
  'Fecha límite para reclamar el premio. NULL en premios que no son platos.';

-- Los canjes anteriores a esta migración reciben un código si eran platos.
update public.reward_redemptions
   set claim_code = upper(substr(md5(id::text), 1, 6))
 where claim_code is null
   and prize_dish_id is not null;

-- ------------------------------------------------- Validación por el negocio

create or replace function public.use_reward_redemption(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_red public.reward_redemptions;
  v_dish text;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select * into v_red
    from public.reward_redemptions
   where upper(claim_code) = upper(trim(coalesce(p_code, '')))
     for update;

  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  if v_red.status <> 'granted' then
    return jsonb_build_object('result', 'already_used');
  end if;

  if v_red.expires_at is not null and v_red.expires_at < now() then
    update public.reward_redemptions set status = 'expired' where id = v_red.id;
    return jsonb_build_object('result', 'expired');
  end if;

  -- Solo el negocio dueño de la sede puede validar el premio.
  if v_red.prize_branch_id is null
     or not public.is_my_branch(v_red.prize_branch_id) then
    return jsonb_build_object('result', 'forbidden');
  end if;

  update public.reward_redemptions
     set status = 'used', used_at = now()
   where id = v_red.id;

  select d.name into v_dish
    from public.dishes d
   where d.id = v_red.prize_dish_id;

  return jsonb_build_object(
    'result', 'ok',
    'prize', coalesce(v_dish, v_red.prize_label),
    'code', v_red.claim_code
  );
end;
$$;

revoke all on function public.use_reward_redemption(text) from public, anon;
grant execute on function public.use_reward_redemption(text) to authenticated;

-- ------------------------------------------- Canje con código de reclamación

create or replace function public.redeem_reward(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_reward public.gotas_rewards;
  v_balance int;
  v_redemption uuid;
  v_prize public.gotas_reward_prizes;
  v_prize_id uuid;
  v_dish_id uuid;
  v_branch_id uuid;
  v_item_label text;
  v_claim text;
  v_total int;
  v_roll numeric;
  v_used int;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  select * into v_reward
    from public.gotas_rewards
   where code = p_payload ->> 'code'
     and is_active;
  if not found then
    return jsonb_build_object('result', 'reward_not_found');
  end if;

  -- Enfriamiento configurable (0 = ilimitado).
  if v_reward.cooldown_hours > 0 and exists (
    select 1 from public.reward_redemptions r
     where r.user_id = v_uid
       and r.reward_id = v_reward.id
       and r.created_at > now() - make_interval(hours => v_reward.cooldown_hours)
  ) then
    return jsonb_build_object(
      'result', 'cooldown',
      'cooldown_hours', v_reward.cooldown_hours
    );
  end if;

  -- Límite diario opcional.
  if v_reward.daily_limit is not null then
    select count(*) into v_used
      from public.reward_redemptions r
     where r.user_id = v_uid
       and r.reward_id = v_reward.id
       and r.created_at > now() - interval '24 hours';
    if v_used >= v_reward.daily_limit then
      return jsonb_build_object('result', 'daily_limit');
    end if;
  end if;

  select gotas into v_balance
    from public.profiles
   where id = v_uid
     for update;

  if v_balance is null then
    return jsonb_build_object('result', 'no_profile');
  end if;
  if v_balance < v_reward.gotas_cost then
    return jsonb_build_object(
      'result', 'insufficient_gotas',
      'balance', v_balance,
      'cost', v_reward.gotas_cost
    );
  end if;

  -- 1) Platos que los restaurantes metieron en la caja.
  if v_reward.merchant_managed then
    select bi.dish_id, bi.branch_id, d.name
      into v_dish_id, v_branch_id, v_item_label
      from public.box_items bi
      join public.dishes d on d.id = bi.dish_id
      join public.branches b on b.id = bi.branch_id
     where bi.reward_id = v_reward.id
       and bi.is_active
       and d.active
       and d.deleted_at is null
       and b.deleted_at is null
     order by random()
     limit 1;
  end if;

  -- 2) Si no hay platos, premios de plataforma.
  if v_dish_id is null and v_reward.reward_type in ('mystery_box', 'monthly_raffle') then
    select coalesce(sum(weight), 0) into v_total
      from public.gotas_reward_prizes
     where reward_id = v_reward.id and is_active;

    if v_total > 0 then
      v_roll := random() * v_total;
      select p.id into v_prize_id
        from (
          select id, sum(weight) over (order by id) as cum
            from public.gotas_reward_prizes
           where reward_id = v_reward.id and is_active
        ) p
       where p.cum >= v_roll
       order by p.cum
       limit 1;

      if v_prize_id is not null then
        select * into v_prize
          from public.gotas_reward_prizes
         where id = v_prize_id;
      end if;
    end if;
  end if;

  -- Código de reclamación solo para platos.
  if v_dish_id is not null then
    v_claim := upper(substr(md5(gen_random_uuid()::text), 1, 6));
  end if;

  insert into public.reward_redemptions (
    user_id, reward_id, gotas_spent,
    prize_id, prize_label, prize_type, prize_amount,
    prize_dish_id, prize_branch_id,
    claim_code, expires_at
  ) values (
    v_uid, v_reward.id, v_reward.gotas_cost,
    case when v_dish_id is null then v_prize.id else null end,
    coalesce(v_item_label, v_prize.label),
    case when v_dish_id is not null then 'product' else v_prize.prize_type end,
    case when v_dish_id is null then coalesce(v_prize.amount, 0) else 0 end,
    v_dish_id,
    v_branch_id,
    v_claim,
    case when v_dish_id is not null then now() + interval '30 days' end
  )
  returning id into v_redemption;

  perform public.credit_gotas(
    v_uid, -v_reward.gotas_cost, 'Canje: ' || v_reward.name, null
  );

  return jsonb_build_object(
    'result', 'ok',
    'redemption_id', v_redemption,
    'reward', v_reward.code,
    'balance', v_balance - v_reward.gotas_cost,
    'prize', case
      when v_dish_id is not null then jsonb_build_object(
        'label', v_item_label,
        'type', 'product',
        'amount', 0,
        'dish_id', v_dish_id,
        'branch_id', v_branch_id,
        'claim_code', v_claim
      )
      when v_prize.id is null then null
      else jsonb_build_object(
        'label', v_prize.label,
        'type', v_prize.prize_type,
        'amount', v_prize.amount
      )
    end
  );
end;
$$;

revoke all on function public.redeem_reward(jsonb) from public, anon;
grant execute on function public.redeem_reward(jsonb) to authenticated;
