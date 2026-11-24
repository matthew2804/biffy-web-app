-- ============================================================================
-- 0008 · Cajas con premios aleatorios
-- ============================================================================
-- Cada caja (mystery_box / monthly_raffle) tiene un catálogo de premios con
-- un peso. Al canjearla se sortea un premio ponderado: a mejor caja (tier),
-- mejores premios y mayor probabilidad de los raros.
--
-- El premio se guarda en `reward_redemptions` para que quede trazable.
-- ============================================================================

create table if not exists public.gotas_reward_prizes (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid not null references public.gotas_rewards (id) on delete cascade,
  code text not null,
  label text not null,
  prize_type text not null
    check (prize_type in ('discount', 'free_shipping', 'product', 'raffle_ticket')),
  amount int not null default 0 check (amount >= 0),
  weight int not null default 10 check (weight > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (reward_id, code)
);

create index if not exists gotas_reward_prizes_reward_idx
  on public.gotas_reward_prizes (reward_id)
  where is_active;

alter table public.reward_redemptions
  add column if not exists prize_id uuid
    references public.gotas_reward_prizes (id) on delete set null;
alter table public.reward_redemptions
  add column if not exists prize_label text;
alter table public.reward_redemptions
  add column if not exists prize_type text;
alter table public.reward_redemptions
  add column if not exists prize_amount int not null default 0;

alter table public.gotas_reward_prizes enable row level security;

drop policy if exists gotas_reward_prizes_read on public.gotas_reward_prizes;
create policy gotas_reward_prizes_read on public.gotas_reward_prizes
  for select to anon, authenticated using (is_active);

grant select on public.gotas_reward_prizes to anon, authenticated;

-- ---------------------------------------------------------------- Canje

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
  v_total int;
  v_roll numeric;
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

  -- Bloquea el perfil: dos canjes simultáneos no pueden gastar de más.
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

  -- Sorteo ponderado (solo cajas y sorteo mensual).
  if v_reward.reward_type in ('mystery_box', 'monthly_raffle') then
    select coalesce(sum(weight), 0) into v_total
      from public.gotas_reward_prizes
     where reward_id = v_reward.id
       and is_active;

    if v_total > 0 then
      v_roll := random() * v_total;

      select p.id into v_prize_id
        from (
          select id, sum(weight) over (order by id) as cum
            from public.gotas_reward_prizes
           where reward_id = v_reward.id
             and is_active
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

  insert into public.reward_redemptions (
    user_id, reward_id, gotas_spent,
    prize_id, prize_label, prize_type, prize_amount
  ) values (
    v_uid, v_reward.id, v_reward.gotas_cost,
    v_prize.id, v_prize.label, v_prize.prize_type,
    coalesce(v_prize.amount, 0)
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

-- ------------------------------------------------------- Premios por caja
-- Los pesos son relativos: 45 significa 45 % si el total suma 100.

insert into public.gotas_reward_prizes
  (reward_id, code, label, prize_type, amount, weight)
select r.id, v.code, v.label, v.prize_type, v.amount, v.weight
from (values
  -- Caja sorpresa (25 Gotas) · premios comunes
  ('box_25', 'discount_2000', '$2.000 de descuento', 'discount', 2000, 45),
  ('box_25', 'free_shipping', 'Envío gratis', 'free_shipping', 0, 25),
  ('box_25', 'discount_3000', '$3.000 de descuento', 'discount', 3000, 18),
  ('box_25', 'product_dessert', 'Postre gratis', 'product', 0, 9),
  ('box_25', 'discount_5000', '$5.000 de descuento', 'discount', 5000, 3),

  -- Caja premium (50 Gotas) · premios medios
  ('box_50', 'discount_5000', '$5.000 de descuento', 'discount', 5000, 40),
  ('box_50', 'free_shipping_x2', '2 envíos gratis', 'free_shipping', 0, 20),
  ('box_50', 'discount_8000', '$8.000 de descuento', 'discount', 8000, 22),
  ('box_50', 'product_surprise', 'Producto sorpresa', 'product', 0, 13),
  ('box_50', 'discount_12000', '$12.000 de descuento', 'discount', 12000, 5),

  -- Caja sorteo (100 Gotas) · premios altos + boleto
  ('box_100', 'discount_10000', '$10.000 de descuento', 'discount', 10000, 35),
  ('box_100', 'discount_15000', '$15.000 de descuento', 'discount', 15000, 25),
  ('box_100', 'product_premium', 'Producto premium', 'product', 0, 20),
  ('box_100', 'raffle_ticket', 'Boleto extra de sorteo', 'raffle_ticket', 0, 15),
  ('box_100', 'discount_25000', '$25.000 de descuento', 'discount', 25000, 5)
) as v(reward_code, code, label, prize_type, amount, weight)
join public.gotas_rewards r on r.code = v.reward_code
on conflict (reward_id, code) do update set
  label = excluded.label,
  prize_type = excluded.prize_type,
  amount = excluded.amount,
  weight = excluded.weight,
  is_active = true;
