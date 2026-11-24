-- ============================================================================
-- 0022 · Notificaciones generadas por la base
-- ============================================================================
-- Antes cada app creaba los avisos de los otros roles y la base los rechazaba
-- (solo se puede insertar para uno mismo): el comprador nunca se enteraba de
-- que el restaurante aceptó o que el repartidor iba en camino.
--
-- Ahora un trigger sobre `order_events` (cada transición deja uno) crea una
-- fila por destinatario con su `user_id` y `role`:
--   pedido nuevo           → comprador y dueño del restaurante
--   aceptado / rechazado   → comprador
--   cancelado por cliente  → restaurante
--   listo                  → comprador y repartidores en línea que lo alcanzan
--   repartidor asignado    → comprador, restaurante y el repartidor
--   en camino / entregado  → comprador (y restaurante al entregar)
-- y otro sobre `reviews` avisa al restaurante de cada calificación.
-- La tabla se publica en Realtime; RLS hace que cada quien reciba solo lo suyo.
-- ============================================================================

alter table public.notifications
  add column if not exists role public.user_role,
  add column if not exists order_id uuid references public.orders (id) on delete cascade;

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_order_idx
  on public.notifications (order_id);

-- El usuario solo puede marcar como leída; no puede reescribir el aviso.
revoke update on public.notifications from authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ------------------------------------------------------------ Utilidades
create or replace function public.cop(p_amount int)
returns text
language sql
immutable
as $$
  select '$' || replace(to_char(coalesce(p_amount, 0), 'FM999,999,999'), ',', '.')
$$;

create or replace function public.notify(
  p_user uuid,
  p_role public.user_role,
  p_audience text,
  p_title text,
  p_body text,
  p_route text,
  p_order uuid
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.notifications (user_id, role, audience, title, body, route, order_id)
  select p_user, p_role, p_audience, p_title, coalesce(p_body, ''), p_route, p_order
   where p_user is not null
$$;

revoke all on function public.notify(uuid, public.user_role, text, text, text, text, uuid)
  from public, anon, authenticated;

-- -------------------------------------------------- Avisos por transición
create or replace function public.notify_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders;
  v_business uuid;
  v_owner uuid;
  v_items text;
  v_buyer_route text;
  v_biz_audience text;
  c record;
begin
  select * into o from public.orders where id = new.order_id;
  if not found then
    return new;
  end if;

  select b.business_id, bz.owner_id into v_business, v_owner
    from public.branches b
    join public.businesses bz on bz.id = b.business_id
   where b.id = o.branch_id;

  select string_agg(i.qty || '× ' || i.name, ', ' order by i.name)
    into v_items
    from public.order_items i
   where i.order_id = o.id;

  v_buyer_route := '/pedido/' || o.code;
  v_biz_audience := 'business:' || v_business;

  if new.status = 'pending' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido ' || o.code || ' creado',
      'Esperando que ' || o.restaurant_name || ' lo acepte.',
      v_buyer_route, o.id);
    perform public.notify(v_owner, 'restaurant', v_biz_audience,
      'Nuevo pedido ' || o.code,
      coalesce(v_items, ''),
      '/negocio/pedidos', o.id);

  elsif new.status = 'preparing' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido en preparación 👩‍🍳',
      o.restaurant_name || ' aceptó tu pedido ' || o.code || '.',
      v_buyer_route, o.id);

  elsif new.status = 'cancelled' and new.actor_label = 'Comprador' then
    perform public.notify(v_owner, 'restaurant', v_biz_audience,
      'Pedido ' || o.code || ' cancelado por el cliente',
      coalesce(v_items, ''),
      '/negocio/pedidos', o.id);

  elsif new.status = 'cancelled' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido ' || o.code || ' rechazado',
      'Motivo: ' || coalesce(nullif(o.reject_reason, ''), 'sin motivo')
        || '. No se realizó ningún cobro.',
      v_buyer_route, o.id);

  elsif new.status = 'ready' and new.actor_label = 'Repartidor' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Repartidor asignado 🛵',
      coalesce(o.courier_name, 'Un repartidor') || ' recogerá tu pedido ' || o.code || '.',
      v_buyer_route, o.id);
    perform public.notify(v_owner, 'restaurant', v_biz_audience,
      'Repartidor asignado a ' || o.code,
      coalesce(o.courier_name, 'El repartidor') || ' va en camino a recoger.',
      '/negocio/pedidos', o.id);
    perform public.notify(o.courier_id, 'courier', 'courier:' || o.courier_id,
      'Pedido ' || o.code || ' asignado',
      'Ve a ' || o.restaurant_name || case
        when coalesce(o.pickup_code, '') = '' then ' a recoger el pedido.'
        else ' y muestra el código ' || o.pickup_code || '.'
      end,
      '/repartidor/recogida/' || o.code, o.id);
    -- La oferta ya no está disponible para los demás.
    update public.notifications
       set read_at = now()
     where order_id = o.id
       and role = 'courier'
       and user_id is distinct from o.courier_id
       and read_at is null;

  elsif new.status = 'ready' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido listo 🛍️',
      'Tu pedido ' || o.code || ' está listo. Buscando repartidor…',
      v_buyer_route, o.id);
    for c in
      select cp.user_id
        from public.courier_profiles cp
       where cp.online
         and o.distance_km <= public.vehicle_max_km(cp.vehicle)
         and not exists (
           select 1 from public.orders x
            where x.courier_id = cp.user_id
              and x.status in ('ready', 'on_the_way')
         )
    loop
      perform public.notify(c.user_id, 'courier', 'courier:' || c.user_id,
        'Oferta disponible · ' || public.cop(o.courier_pay + o.tip),
        o.restaurant_name || ' → ' || coalesce(o.address_snapshot ->> 'label', 'entrega')
          || ' (' || o.distance_km || ' km).',
        '/repartidor/oferta/' || o.code, o.id);
    end loop;

  elsif new.status = 'on_the_way' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido en camino 🛵',
      coalesce(o.courier_name, 'Tu repartidor') || ' va en camino con tu pedido ' || o.code || '.',
      v_buyer_route, o.id);

  elsif new.status = 'delivered' then
    perform public.notify(o.buyer_id, 'buyer', 'user:' || o.buyer_id,
      'Pedido entregado ✅',
      '¡Buen provecho! Ganaste ' || (o.subtotal / 1000) || ' Gotas con ' || o.code || '.',
      v_buyer_route, o.id);
    perform public.notify(v_owner, 'restaurant', v_biz_audience,
      'Pedido ' || o.code || ' entregado',
      'Entregado por ' || coalesce(o.courier_name, 'el repartidor') || '.',
      '/negocio/pedidos', o.id);
  end if;

  return new;
end;
$$;

drop trigger if exists order_events_notify on public.order_events;
create trigger order_events_notify
  after insert on public.order_events
  for each row execute function public.notify_order_event();

-- ------------------------------------------------- Aviso de calificación
create or replace function public.notify_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  o public.orders;
  v_business uuid;
  v_owner uuid;
begin
  select * into o from public.orders where id = new.order_id;
  select b.business_id, bz.owner_id into v_business, v_owner
    from public.branches b
    join public.businesses bz on bz.id = b.business_id
   where b.id = new.branch_id;

  perform public.notify(v_owner, 'restaurant', 'business:' || v_business,
    'Nueva calificación ⭐',
    coalesce(o.buyer_name, 'Un cliente') || ' calificó ' || coalesce(o.code, 'un pedido')
      || ' con ' || new.rating || ' de 5.',
    '/negocio/pedidos', new.order_id);
  return null;
end;
$$;

drop trigger if exists reviews_notify on public.reviews;
create trigger reviews_notify
  after insert on public.reviews
  for each row execute function public.notify_review();

-- ------------------------------------------------------------ Realtime
do $$
begin
  alter publication supabase_realtime add table public.notifications;
exception
  when duplicate_object then null;
  when undefined_object then
    raise notice 'No existe la publicación supabase_realtime; se omite notifications.';
end $$;
