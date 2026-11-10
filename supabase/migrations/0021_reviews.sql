-- ============================================================================
-- 0021 · Reseñas por RPC y promedio de la sede
-- ============================================================================
-- Antes el comprador insertaba directo en `reviews` y la política no validaba
-- que `branch_id` fuera la sede del pedido: se podía calificar cualquier sede.
-- Ahora las reseñas solo entran por `rate_order`, que toma la sede del pedido,
-- y un trigger recalcula `branches.rating` con el promedio real.
-- ============================================================================

drop policy if exists reviews_insert on public.reviews;
revoke insert, update, delete on public.reviews from anon, authenticated;

-- ------------------------------------------------------------ Calificar
-- payload: { order_id, rating (1..5), comment? }
create or replace function public.rate_order(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders;
  v_rating int;
  v_comment text := trim(coalesce(p_payload ->> 'comment', ''));
  v_review public.reviews;
begin
  if v_uid is null then
    return jsonb_build_object('result', 'not_authenticated');
  end if;

  v_rating := case
    when (p_payload ->> 'rating') ~ '^[0-9]+$' then (p_payload ->> 'rating')::int
  end;
  if v_rating is null or v_rating not between 1 and 5 then
    return jsonb_build_object('result', 'invalid_rating');
  end if;
  if char_length(v_comment) > 500 then
    return jsonb_build_object('result', 'comment_too_long', 'max', 500);
  end if;

  select * into v_order
    from public.orders
   where id = nullif(p_payload ->> 'order_id', '')::uuid;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;
  if v_order.buyer_id <> v_uid then
    return jsonb_build_object('result', 'forbidden');
  end if;
  if v_order.status <> 'delivered' then
    return jsonb_build_object('result', 'invalid_state');
  end if;

  insert into public.reviews (order_id, user_id, branch_id, rating, comment)
  values (v_order.id, v_uid, v_order.branch_id, v_rating, v_comment)
  on conflict (order_id) do nothing
  returning * into v_review;

  if v_review.id is null then
    return jsonb_build_object('result', 'already_rated');
  end if;

  return jsonb_build_object(
    'result', 'ok',
    'review', to_jsonb(v_review),
    'branch_rating', (select rating from public.branches where id = v_order.branch_id)
  );
end;
$$;

revoke all on function public.rate_order(jsonb) from public, anon;
grant execute on function public.rate_order(jsonb) to authenticated;

-- ------------------------------------------------- Promedio de la sede
create or replace function public.refresh_branch_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_branch uuid := coalesce(new.branch_id, old.branch_id);
  v_avg numeric;
begin
  select round(avg(rating)::numeric, 1) into v_avg
    from public.reviews
   where branch_id = v_branch;

  if v_avg is not null then
    update public.branches set rating = v_avg where id = v_branch;
  end if;
  return null;
end;
$$;

drop trigger if exists reviews_branch_rating on public.reviews;
create trigger reviews_branch_rating
  after insert or update or delete on public.reviews
  for each row execute function public.refresh_branch_rating();
