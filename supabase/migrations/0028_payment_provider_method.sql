-- ============================================================================
-- 0028 · Método real con el que Wompi cobró (no la preferencia del carrito)
-- ============================================================================
-- El Checkout Web muestra todos los métodos habilitados: la app solo guarda
-- una preferencia. Al aprobar/rechazar, el webhook consulta la transacción y
-- aquí se conserva `payment_method_type` (CARD, NEQUI, PSE, DAVIPLATA…).
-- ============================================================================

alter table public.payments
  add column if not exists provider_method text;

-- Cambia la firma de la RPC: se elimina la versión de 4 argumentos para que
-- PostgREST no quede con dos sobrecargas y las llamadas sigan siendo únicas.
drop function if exists public.payment_apply(
  uuid, public.payment_status, text, text
);

-- Aplica el estado que confirmó Wompi. Idempotente.
create or replace function public.payment_apply(
  p_payment uuid,
  p_status public.payment_status,
  p_tx_id text default null,
  p_detail text default null,
  p_method_type text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments;
  v_order public.orders;
  v_business uuid;
  v_owner uuid;
  v_items text;
begin
  select * into v_payment from public.payments where id = p_payment for update;
  if not found then
    return jsonb_build_object('result', 'not_found');
  end if;

  -- Mismo estado (o repetido): no se vuelve a procesar.
  if v_payment.status = p_status
     and (p_tx_id is null or v_payment.provider_transaction_id = p_tx_id) then
    return jsonb_build_object('result', 'duplicate', 'status', v_payment.status);
  end if;

  if not (
    (v_payment.status in ('pending', 'processing')
      and p_status in ('approved', 'rejected', 'expired', 'refunded'))
    or (v_payment.status = 'approved' and p_status = 'refunded')
  ) then
    return jsonb_build_object(
      'result', 'invalid_state',
      'from', v_payment.status,
      'to', p_status
    );
  end if;

  select * into v_order
    from public.orders where id = v_payment.order_id for update;
  if not found then
    return jsonb_build_object('result', 'order_not_found');
  end if;

  -- Llegó aprobado pero el pedido ya se había cancelado: hay que reembolsar.
  if p_status = 'approved' and v_order.status <> 'pending' then
    update public.payments
       set status = 'refunded',
           provider_method = coalesce(nullif(p_method_type, ''), provider_method),
           refunded_at = now(),
           refund_amount = v_payment.amount,
           refund_reason = 'El pedido ya estaba cancelado',
           updated_at = now()
     where id = p_payment;
    return jsonb_build_object('result', 'refund_required');
  end if;

  update public.payments
     set status = p_status,
         provider_transaction_id = coalesce(p_tx_id, provider_transaction_id),
         provider_method = coalesce(nullif(p_method_type, ''), provider_method),
         status_detail = coalesce(p_detail, status_detail),
         updated_at = now(),
         approved_at = case when p_status = 'approved'
                            then coalesce(approved_at, now()) else approved_at end,
         rejected_at = case when p_status = 'rejected'
                            then coalesce(rejected_at, now()) else rejected_at end,
         expired_at = case when p_status = 'expired'
                           then coalesce(expired_at, now()) else expired_at end,
         refunded_at = case when p_status = 'refunded'
                            then coalesce(refunded_at, now()) else refunded_at end
   where id = p_payment;

  if p_status = 'approved' then
    update public.orders
       set payment_status = 'approved',
           payment_expires_at = null
     where id = v_order.id
     returning * into v_order;

    select b.business_id, bz.owner_id into v_business, v_owner
      from public.branches b
      join public.businesses bz on bz.id = b.business_id
     where b.id = v_order.branch_id;
    select string_agg(i.qty || '× ' || i.name, ', ' order by i.name)
      into v_items
      from public.order_items i
     where i.order_id = v_order.id;

    perform public.notify(v_owner, 'restaurant', 'business:' || v_business,
      'Nuevo pedido ' || v_order.code || ' pagado',
      coalesce(v_items, '') || ' · Pago aprobado',
      '/negocio/pedidos', v_order.id);
    perform public.notify(v_order.buyer_id, 'buyer', 'user:' || v_order.buyer_id,
      'Pago aprobado ✅',
      'Tu pedido ' || v_order.code || ' ya está con ' || v_order.restaurant_name || '.',
      '/pedido/' || v_order.code, v_order.id);

  elsif p_status = 'rejected' then
    update public.orders
       set payment_status = 'rejected'
     where id = v_order.id;
    perform public.notify(v_order.buyer_id, 'buyer', 'user:' || v_order.buyer_id,
      'Pago rechazado',
      coalesce(nullif(p_detail, ''), 'El pago no se pudo completar') ||
        '. Puedes intentarlo de nuevo.',
      '/pedido/' || v_order.code, v_order.id);

  elsif p_status = 'expired' then
    -- Si otro intento ya está aprobado, no se cancela.
    if exists (
      select 1 from public.payments p
       where p.order_id = v_order.id and p.status = 'approved'
    ) then
      return jsonb_build_object('result', 'already_paid');
    end if;
    update public.orders
       set status = 'cancelled',
           reject_reason = 'El pago venció',
           cancelled_at = now(),
           payment_status = 'expired'
     where id = v_order.id
     returning * into v_order;
    perform public.order_event(v_order.id, 'cancelled', 'Pasarela', 'pending');
    perform public.refund_order(v_order);

  elsif p_status = 'refunded' then
    update public.orders
       set payment_status = 'refunded'
     where id = v_order.id;
  end if;

  select * into v_order from public.orders where id = v_payment.order_id;
  return jsonb_build_object(
    'result', 'ok',
    'status', p_status,
    'order_status', v_order.status,
    'payment_status', v_order.payment_status
  );
end;
$$;

-- La RPC solo la usa el webhook con service_role; nunca el cliente.
revoke execute on function public.payment_apply(
  uuid, public.payment_status, text, text, text
) from public, anon, authenticated;
