#!/bin/sh
# Rôles PostgREST : authenticator (connexion) -> web_anon (droits minimaux)
set -e
psql -v ON_ERROR_STOP=1 -v pw="$AUTHENTICATOR_PASSWORD" \
     --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<'SQL'
CREATE ROLE authenticator LOGIN NOINHERIT NOCREATEDB NOCREATEROLE NOSUPERUSER PASSWORD :'pw';
CREATE ROLE web_anon NOLOGIN;
GRANT web_anon TO authenticator;
SQL
