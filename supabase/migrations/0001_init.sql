-- ============================================================================
-- 0001 · Extensiones, tipos y utilidades
-- ============================================================================

create extension if not exists pgcrypto;

do $$ begin
  create type public.user_role as enum ('buyer', 'courier', 'restaurant');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_status as enum
    ('pending', 'preparing', 'ready', 'on_the_way', 'delivered', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.vehicle_type as enum ('moto', 'bicycle', 'scooter', 'walking');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.courier_zone as enum ('general', 'campus');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.coupon_kind as enum ('free_delivery', 'fixed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.dish_option_kind as enum ('size', 'side', 'extra');
exception when duplicate_object then null; end $$;

-- Códigos de pedido legibles: BF-2041, BF-2042, ...
create sequence if not exists public.order_code_seq start with 2041;

-- Código de entrega de 4 dígitos (único por pedido mientras la secuencia no
-- dé la vuelta; la columna además es NOT NULL).
create sequence if not exists public.delivery_code_seq start with 1000;

-- Marca updated_at en cada UPDATE.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
