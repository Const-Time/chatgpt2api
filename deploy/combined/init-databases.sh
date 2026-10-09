#!/usr/bin/env bash
set -euo pipefail

# Official PostgreSQL entrypoint runs this only for an empty data directory.
# Hex passwords also remain safe when used in chatgpt2api's connection URL.
for password_name in CPR_DATABASE_PASSWORD CHATGPT2API_DATABASE_PASSWORD; do
  if [[ ! "${!password_name:-}" =~ ^[0-9a-fA-F]{48}$ ]]; then
    printf '%s must contain 48 hexadecimal characters\n' "$password_name" >&2
    exit 1
  fi
done

PGPASSWORD="$POSTGRES_PASSWORD" psql --username "$POSTGRES_USER" --dbname postgres \
  --set=ON_ERROR_STOP=1 \
  --set=cpr_password="$CPR_DATABASE_PASSWORD" \
  --set=chat_password="$CHATGPT2API_DATABASE_PASSWORD" <<'SQL'
CREATE ROLE codex_proxy LOGIN PASSWORD :'cpr_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE ROLE chatgpt2api LOGIN PASSWORD :'chat_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
CREATE DATABASE codex_proxy OWNER codex_proxy;
CREATE DATABASE chatgpt2api OWNER chatgpt2api;
REVOKE ALL ON DATABASE codex_proxy FROM PUBLIC;
REVOKE ALL ON DATABASE chatgpt2api FROM PUBLIC;
SQL
