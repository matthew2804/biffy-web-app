-- ============================================================================
-- Piezas mínimas de Supabase para probar las migraciones en un Postgres local
-- ============================================================================
-- Supabase ya trae esto (roles, auth.uid(), storage, Realtime). En un Postgres
-- con PostGIS vacío se crea aquí para poder aplicar apply_all.sql y correr
-- supabase/tests/*.sql sin tocar el proyecto real. No se aplica en Supabase.
-- ============================================================================

do $r$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
    create role authenticated nologin;
    create role service_role nologin bypassrls;
  end if;
end $r$;

create extension if not exists postgis;

create schema if not exists auth;
create schema if not exists storage;

create table if not exists auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb,
  created_at timestamptz default now()
);

-- Igual que en Supabase: el usuario sale del JWT de la petición.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon')
$$;

create table if not exists storage.buckets (
  id text primary key,
  name text,
  public boolean default false,
  file_size_limit bigint,
  allowed_mime_types text[]
);

create table if not exists storage.objects (
  id uuid primary key default gen_random_uuid(),
  bucket_id text,
  name text,
  owner uuid
);
alter table storage.objects enable row level security;

create or replace function storage.foldername(name text) returns text[]
language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;

do $p$
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
end $p$;

grant usage on schema auth, storage to anon, authenticated;
grant execute on function auth.uid(), auth.role() to anon, authenticated;
