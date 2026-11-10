#!/usr/bin/env bash
# Aplica todas las migraciones en un Postgres + PostGIS local y corre
# supabase/tests/*.sql. No toca el proyecto de Supabase.
#
#   tool/test_supabase_sql.sh                 # levanta Docker (biffy-pg-test)
#   DB_URL=postgres://... tool/test_supabase_sql.sh   # usa una base existente
set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${DB_URL:-}" ]; then
  name=biffy-pg-test
  if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
    docker rm -f "$name" >/dev/null 2>&1 || true
    docker run -d --name "$name" -e POSTGRES_PASSWORD=postgres \
      -p 55433:5432 postgis/postgis:16-3.4 >/dev/null
  fi
  # La imagen se reinicia una vez al terminar su inicialización.
  until docker logs "$name" 2>&1 | grep -q 'PostgreSQL init process complete' \
    && docker exec "$name" pg_isready -U postgres >/dev/null 2>&1; do
    sleep 1
  done
  psql_() { docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
  psql_ -c 'drop database if exists biffy_test' -c 'create database biffy_test' >/dev/null
  run() { psql_ -d biffy_test "$@"; }
else
  run() { psql "$DB_URL" -v ON_ERROR_STOP=1 -q "$@"; }
fi

run < supabase/tests/_supabase_stubs.sql
run -1 < supabase/apply_all.sql 2>&1 | grep -E 'Biffy OK|ERROR' || true

fail=0
for f in supabase/tests/hu*.sql; do
  if out=$(run < "$f" 2>&1); then
    echo "✅ $f ($(grep -c 'ok ·' <<<"$out") casos)"
  else
    echo "❌ $f"
    grep -E 'ERROR|FALLA' <<<"$out" | head -5 || tail -5 <<<"$out"
    fail=1
  fi
done
exit $fail
