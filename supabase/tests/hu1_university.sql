-- ============================================================================
-- HU-1 · Verificación institucional con código y vencimiento
-- ============================================================================
-- Corre en una transacción y hace rollback: no deja datos.
--   psql "$DB_URL" -v ON_ERROR_STOP=1 -f supabase/tests/hu1_university.sql
-- ============================================================================

begin;

insert into auth.users (id, email, raw_user_meta_data) values
  (
    '00000000-0000-0000-0000-0000000000e1',
    'ana.hu1@icesi.edu.co',
    '{"role":"buyer","full_name":"Ana HU1"}'
  );

-- Ejecuta una expresión como el usuario autenticado `p_user`.
create function pg_temp.como(p_user uuid, p_sql text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  execute 'select ' || p_sql into r;
  reset role;
  return r;
exception when others then
  reset role;
  return jsonb_build_object(
    'result', 'error', 'sqlstate', sqlstate, 'message', sqlerrm
  );
end $$;

-- Ejecuta una sentencia como el usuario autenticado; devuelve error o filas.
create function pg_temp.intentar(p_user uuid, p_sql text)
returns jsonb language plpgsql as $$
declare n int;
begin
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  perform set_config('request.jwt.claim.role', 'authenticated', true);
  set local role authenticated;
  execute p_sql;
  get diagnostics n = row_count;
  reset role;
  return jsonb_build_object('result', 'ok', 'n', n);
exception when others then
  reset role;
  return jsonb_build_object(
    'result', 'error', 'sqlstate', sqlstate, 'message', sqlerrm
  );
end $$;

do $$
declare
  v_user uuid := '00000000-0000-0000-0000-0000000000e1';
  v_email text := 'ana.hu1@icesi.edu.co';
  v_r jsonb;
  v_token text;
begin
  -- 1) Código inicial generado por el servicio.
  select public.create_university_verification(v_user, 'icesi', v_email)
    into v_r;
  if v_r ->> 'result' <> 'ok' then
    raise exception 'FALLA [crear código]: %', v_r;
  end if;
  v_token := v_r ->> 'token';
  if v_token is null or length(v_token) <> 6 then
    raise exception 'FALLA [código de 6 dígitos]: %', v_token;
  end if;
  raise notice 'ok · código generado';

  -- 2) El usuario confirma el código y queda verificado 30 días.
  select pg_temp.como(
    v_user,
    format(
      'public.confirm_university_verification(%L, %L)',
      v_email,
      v_token
    )
  ) into v_r;
  if v_r ->> 'result' <> 'ok' then
    raise exception 'FALLA [confirmar código]: %', v_r;
  end if;
  if not exists (
    select 1 from public.profiles
     where id = v_user
       and verified
       and university_status = 'active'
       and university_expires_at > now()
  ) then
    raise exception 'FALLA [perfil verificado 30 días]';
  end if;
  raise notice 'ok · verificación activa por 30 días';

  -- 3) Un update directo no puede cambiar la verificación.
  select pg_temp.intentar(
    v_user,
    'update public.profiles set verified = false where id = auth.uid()'
  ) into v_r;
  if v_r ->> 'result' <> 'error' then
    raise exception 'FALLA [update directo permitido]: %', v_r;
  end if;
  raise notice 'ok · update directo bloqueado';

  -- 4) Revalidación: extiende la fecha sin apagar Campus.
  update public.university_verifications
     set last_sent_at = now() - interval '3 minutes'
   where user_id = v_user;

  select public.create_university_verification(
    v_user, 'icesi', v_email, true
  ) into v_r;
  if v_r ->> 'result' <> 'ok' then
    raise exception 'FALLA [revalidar]: %', v_r;
  end if;
  v_token := v_r ->> 'token';

  select pg_temp.como(
    v_user,
    format(
      'public.confirm_university_verification(%L, %L)',
      v_email,
      v_token
    )
  ) into v_r;
  if v_r ->> 'result' <> 'ok' then
    raise exception 'FALLA [confirmar revalidación]: %', v_r;
  end if;
  raise notice 'ok · revalidación extendida';

  -- 5) Revocar por rebote deshabilita Campus, pero no la cuenta.
  perform public.revoke_university_verification(v_user, 'bounce');
  if exists (
    select 1 from public.profiles
     where id = v_user and verified
  ) then
    raise exception 'FALLA [Campus seguía activo tras revocar]';
  end if;
  if not exists (
    select 1 from public.notifications
     where user_id = v_user and title = 'Campus deshabilitado'
  ) then
    raise exception 'FALLA [no se creó el aviso de Campus]';
  end if;
  raise notice 'ok · Campus deshabilitado y aviso creado';

  -- 6) Un dominio distinto no puede pedir código.
  select public.create_university_verification(
    v_user, 'icesi', 'ana@gmail.com'
  ) into v_r;
  if v_r ->> 'result' <> 'domain_mismatch' then
    raise exception 'FALLA [dominio distinto]: %', v_r;
  end if;
  raise notice 'ok · dominio distinto rechazado';
end $$;

rollback;
