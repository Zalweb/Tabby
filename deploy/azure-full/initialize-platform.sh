#!/usr/bin/env bash
set -euo pipefail
cd /srv/tabby
query() { docker compose exec -T db psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
# Some image builds ship a prepared cluster and skip mounted first-init SQL.
# Apply the upstream platform prerequisites without deleting or reinitializing it.
if test "$(query -Atc "SELECT count(*) FROM pg_database WHERE datname='_supabase'")" = '0'; then
  query -f /docker-entrypoint-initdb.d/migrations/97-_supabase.sql
fi
if test "$(query -Atc "SELECT count(*) FROM pg_namespace WHERE nspname='supabase_functions'")" = '0'; then
  query -f /docker-entrypoint-initdb.d/init-scripts/98-webhooks.sql
fi
query -f /docker-entrypoint-initdb.d/init-scripts/99-roles.sql
query -f /docker-entrypoint-initdb.d/init-scripts/99-jwt.sql
query -f /docker-entrypoint-initdb.d/migrations/99-realtime.sql
query -f /docker-entrypoint-initdb.d/migrations/99-logs.sql
query -f /docker-entrypoint-initdb.d/migrations/99-pooler.sql
# GoTrue must own the prepared Auth schema objects before its own migrations.
# This changes ownership only; no Auth/financial rows are removed or rewritten.
query <<'SQL'
CREATE SCHEMA IF NOT EXISTS graphql_public;
GRANT USAGE ON SCHEMA graphql_public TO anon, authenticated, service_role;
-- Storage performs requests under the verified JWT's API role. Prepared
-- clusters may lack the membership normally installed by storage init SQL.
GRANT anon, authenticated, service_role TO supabase_storage_admin;
ALTER SCHEMA auth OWNER TO supabase_auth_admin;
DO $ownership$
DECLARE obj record;
BEGIN
  FOR obj IN SELECT p.oid::regprocedure AS signature FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='auth'
  LOOP EXECUTE format('ALTER ROUTINE %s OWNER TO supabase_auth_admin', obj.signature); END LOOP;
  FOR obj IN SELECT c.relname,c.relkind FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='auth' AND c.relkind IN ('r','p','v','m')
  LOOP
    EXECUTE format('ALTER %s auth.%I OWNER TO supabase_auth_admin',
      CASE obj.relkind WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END, obj.relname);
  END LOOP;
  -- Table ownership updates owned sequences automatically. Only standalone
  -- sequences still owned by another role need an explicit change afterwards.
  FOR obj IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='auth' AND c.relkind='S'
      AND c.relowner<>(SELECT oid FROM pg_roles WHERE rolname='supabase_auth_admin')
  LOOP EXECUTE format('ALTER SEQUENCE auth.%I OWNER TO supabase_auth_admin',obj.relname); END LOOP;
  FOR obj IN SELECT t.typname,t.typtype FROM pg_type t
    JOIN pg_namespace n ON n.oid=t.typnamespace
    WHERE n.nspname='auth' AND t.typtype IN ('e','d')
  LOOP EXECUTE format('ALTER %s auth.%I OWNER TO supabase_auth_admin',
    CASE obj.typtype WHEN 'd' THEN 'DOMAIN' ELSE 'TYPE' END,obj.typname); END LOOP;
END
$ownership$;
SQL
echo 'Upstream platform prerequisites initialized.'
