-- ============================================================================
-- 0012 · Cajas configurables por restaurante y límites por recompensa
-- ============================================================================
-- Cambios:
--   1. Cada recompensa define su enfriamiento y su límite diario en la base,
--      para poder ajustarlos sin tocar código.
--   2. Los restaurantes pueden meter y sacar SUS platos de una caja.
--   3. El sorteo usa primero los platos de los restaurantes y, si no hay,
--      cae a los premios de plataforma.
--
-- Reglas pedidas (configurables en `gotas_rewards`):
--   · Caja de 5 Gotas      -> ilimitada (cooldown_hours = 0)
--   · Resto de recompensas -> cada 12 horas (cooldown_hours = 12)
--   · La caja más grande   -> cada 24 horas (cooldown_hours = 24)
-- ============================================================================

-- ------------------------------------------------------- Configuración
alter table public.gotas_rewards
  add column if not exists cooldown_hours int not null default 0
    check (cooldown_hours >= 0);
alter table public.gotas_rewards
  add column if not exists daily_limit int
    check (daily_limit is null or daily_limit > 0);
alter table public.gotas_rewards
  add column if not exists merchant_managed boolean not null default false;
alter table public.gotas_rewards
  add column if not exists sort int not null default 0;

comment on column public.gotas_rewards.cooldown_hours is
  'Horas mínimas entre dos canjes del mismo usuario. 0 = sin límite.';
comment on column public.gotas_rewards.daily_limit is
  'Canjes máximos por usuario en 24 h. NULL = sin límite.';
comment on column public.gotas_rewards.merchant_managed is
  'Si es true, los restaurantes pueden meter sus platos en la caja.';

-- ------------------------------------------------- Productos dentro de caja
create table if not exists public.box_items (
  id uuid primary key default gen_random_uuid(),
  reward_id uuid not null references public.gotas_rewards (id) on delete cascade,
  branch_id uuid not null references public.branches (id) on delete cascade,
  dish_id uuid not null references public.dishes (id) on delete cascade,
  quantity int not null default 1 check (quantity > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (reward_id, branch_id, dish_id)
);

create index if not exists box_items_reward_idx
  on public.box_items (reward_id) where is_active;
create index if not exists box_items_branch_idx
  on public.box_items (branch_id);

drop trigger if exists set_updated_at on public.box_items;
create trigger set_updated_at
  before update on public.box_items
  for each row execute function public.touch_updated_at();

-- Premio entregado cuando sale un plato de restaurante.
alter table public.reward_redemptions
  add column if not exists prize_dish_id uuid
    references public.dishes (id) on delete set null;
alter table public.reward_redemptions
  add column if not exists prize_branch_id uuid
    references public.branches (id) on delete set null;

-- ------------------------------------------------------------------- RLS
alter table public.box_items enable row level security;

drop policy if exists box_items_read on public.box_items;
create policy box_items_read on public.box_items
  for select to anon, authenticated using (is_active);

drop policy if exists box_items_write on public.box_items;
create policy box_items_write on public.box_items
  for all to authenticated
  using (public.is_my_branch(branch_id))
  with check (public.is_my_branch(branch_id));

grant select on public.box_items to anon, authenticated;

-- ------------------------------------------------------- Canje con límites
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

  -- 2) Si no hay platos, premios de plataforma (descuentos, envío, boleto).
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

  insert into public.reward_redemptions (
    user_id, reward_id, gotas_spent,
    prize_id, prize_label, prize_type, prize_amount,
    prize_dish_id, prize_branch_id
  ) values (
    v_uid, v_reward.id, v_reward.gotas_cost,
    case when v_dish_id is null then v_prize.id else null end,
    coalesce(v_item_label, v_prize.label),
    case
      when v_dish_id is not null then 'product'
      else v_prize.prize_type
    end,
    case when v_dish_id is null then coalesce(v_prize.amount, 0) else 0 end,
    v_dish_id,
    v_branch_id
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
        'branch_id', v_branch_id
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

-- --------------------------------------------------------------- Catálogo
-- La caja de 5 es ilimitada; el resto se recarga cada 12 h; la grande cada 24 h.
insert into public.gotas_rewards
  (code, name, reward_type, gotas_cost, tier, draw_frequency, is_active,
   cooldown_hours, daily_limit, merchant_managed, sort)
values
  ('box_5', 'Caja básica', 'mystery_box', 5, null, null, true, 0, null, true, 1),
  ('free_shipping', 'Envío gratis', 'free_shipping', 10, null, null, true, 12, null, false, 2),
  ('box_25', 'Caja sorpresa', 'mystery_box', 25, 1, null, true, 12, null, true, 3),
  ('box_50', 'Caja premium', 'mystery_box', 50, 2, null, true, 12, null, true, 4),
  ('box_100', 'Caja sorteo', 'monthly_raffle', 100, 3, 'monthly', true, 24, null, true, 5)
on conflict (code) do update set
  name = excluded.name,
  reward_type = excluded.reward_type,
  gotas_cost = excluded.gotas_cost,
  tier = excluded.tier,
  draw_frequency = excluded.draw_frequency,
  is_active = excluded.is_active,
  cooldown_hours = excluded.cooldown_hours,
  daily_limit = excluded.daily_limit,
  merchant_managed = excluded.merchant_managed,
  sort = excluded.sort;

-- Premios de plataforma para la caja de 5 (se usan si ningún restaurante
-- ha metido platos todavía).
insert into public.gotas_reward_prizes
  (reward_id, code, label, prize_type, amount, weight)
select r.id, v.code, v.label, v.prize_type, v.amount, v.weight
from (values
  ('box_5', 'discount_1000', '$1.000 de descuento', 'discount', 1000, 50),
  ('box_5', 'free_shipping', 'Envío gratis', 'free_shipping', 0, 30),
  ('box_5', 'product_snack', 'Snack sorpresa', 'product', 0, 20)
) as v(reward_code, code, label, prize_type, amount, weight)
join public.gotas_rewards r on r.code = v.reward_code
on conflict (reward_id, code) do update set
  label = excluded.label,
  prize_type = excluded.prize_type,
  amount = excluded.amount,
  weight = excluded.weight,
  is_active = true;
