-- ============================================================================
-- 0005 · Storage (buckets y políticas)
-- ============================================================================
-- dish-images        público   fotos de platos (carpeta = business_id)
-- delivery-evidence  privado   evidencia de entrega (carpeta = order_id)
-- merchant-docs      privado   documentos del negocio (carpeta = business_id)
-- ============================================================================

insert into storage.buckets (id, name, public)
values
  ('dish-images', 'dish-images', true),
  ('delivery-evidence', 'delivery-evidence', false),
  ('merchant-docs', 'merchant-docs', false)
on conflict do nothing;

-- Cast seguro de texto a uuid (evita errores en rutas que no son de pedido).
create or replace function public.try_uuid(p_value text)
returns uuid
language plpgsql
immutable
as $$
begin
  return p_value::uuid;
exception when others then
  return null;
end;
$$;

-- ---------------------------------------------------------------- dish-images

drop policy if exists dish_images_read on storage.objects;
create policy dish_images_read on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'dish-images');

drop policy if exists dish_images_insert on storage.objects;
create policy dish_images_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'dish-images'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists dish_images_update on storage.objects;
create policy dish_images_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'dish-images'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists dish_images_delete on storage.objects;
create policy dish_images_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'dish-images'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

-- ---------------------------------------------------------- delivery-evidence

drop policy if exists delivery_evidence_read on storage.objects;
create policy delivery_evidence_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'delivery-evidence'
    and public.can_read_order(public.try_uuid((storage.foldername(name))[1]))
  );

drop policy if exists delivery_evidence_insert on storage.objects;
create policy delivery_evidence_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'delivery-evidence'
    and exists (
      select 1 from public.orders o
      where o.id = public.try_uuid((storage.foldername(name))[1])
        and o.courier_id = auth.uid()
    )
  );

-- --------------------------------------------------------------- merchant-docs

drop policy if exists merchant_docs_read on storage.objects;
create policy merchant_docs_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'merchant-docs'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists merchant_docs_insert on storage.objects;
create policy merchant_docs_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'merchant-docs'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );

drop policy if exists merchant_docs_delete on storage.objects;
create policy merchant_docs_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'merchant-docs'
    and (storage.foldername(name))[1] = public.my_business_id()::text
  );
