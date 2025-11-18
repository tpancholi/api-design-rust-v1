#!/usr/bin/env bash
set -euo pipefail

##############################################
# Helper functions
##############################################
log() { echo "👉 $*"; }
err() { echo "❌ $*" >&2; exit 1; }

##############################################
# Configuration (with defaults)
##############################################
PG_VERSION="18-bookworm"
CONTAINER_NAME="${CONTAINER_NAME:=rust_pg18}"
DATA_DIR="$(pwd)/postgres_data"

DB_PORT="${POSTGRES_PORT:=5432}"
SUPERUSER="${SUPERUSER:=postgres}"
SUPERUSER_PWD="${SUPERUSER_PWD:=password}"
DB_NAME="${POSTGRES_DB:=dev_db}"

APP_USER="${APP_USER:=app_user}"
APP_USER_PWD="${APP_USER_PWD:=secret}"
APP_DB_NAME="${APP_DB_NAME:=app_db}"

# Extensions to enable in APP_DB_NAME
POSTGRES_EXTENSIONS=(
  "citext"
  "pgcrypto"
  "pg_stat_statements"
)

##############################################
# Ensure sqlx-cli installed
##############################################
if ! command -v sqlx >/dev/null; then
  err "sqlx CLI not installed. Install with:
  cargo install sqlx-cli --no-default-features --features rustls,postgres"
fi

##############################################
# Start Docker if SKIP_DOCKER is NOT set
##############################################
use_docker=false

if [[ -z "${SKIP_DOCKER:-}" ]]; then
  use_docker=true
  log "🐘 Starting PostgreSQL ${PG_VERSION} via Docker..."

  mkdir -p "${DATA_DIR}"

  # Remove old container if exists
  if docker ps -aq -f name=^${CONTAINER_NAME}$ >/dev/null; then
    log "🧹 Removing old container ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >/dev/null || true
  fi

  docker run -d \
    --name "${CONTAINER_NAME}" \
    --publish "${DB_PORT}:5432" \
    --restart always \
    --env POSTGRES_USER="${SUPERUSER}" \
    --env POSTGRES_PASSWORD="${SUPERUSER_PWD}" \
    --env POSTGRES_DB="${DB_NAME}" \
    --env PGDATA="/var/lib/postgresql/18/docker" \
    --volume "${DATA_DIR}:/var/lib/postgresql/18/docker" \
    postgres:${PG_VERSION}

  log "⏳ Waiting for container PostgreSQL to be ready…"
  until docker exec "${CONTAINER_NAME}" pg_isready -U "${SUPERUSER}" >/dev/null 2>&1; do
    sleep 1
  done

  sleep 2
  log "✅ PostgreSQL container is ready."

else
  log "⚡ SKIP_DOCKER enabled → using existing PostgreSQL"

  # socket-first → fallback to tcp
  until pg_isready -U "${SUPERUSER}" >/dev/null 2>&1 || \
        pg_isready -h 127.0.0.1 -p "${DB_PORT}" -U "${SUPERUSER}" >/dev/null 2>&1; do
    log "⏳ Waiting for local PostgreSQL (user=${SUPERUSER}, port=${DB_PORT})…"
    sleep 1
  done

  log "🔌 Local PostgreSQL is reachable."
fi

##############################################
# Unified exec helpers
##############################################
pg_exec() {
  local sql="$1"
  if $use_docker; then
    docker exec -i "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d postgres -c "${sql}"
  else
    psql -h 127.0.0.1 -U "${SUPERUSER}" -d postgres -c "${sql}"
  fi
}

pg_exec_db() {
  local db="$1"
  local sql="$2"
  if $use_docker; then
    docker exec -i "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d "${db}" -c "${sql}"
  else
    psql -h 127.0.0.1 -U "${SUPERUSER}" -d "${db}" -c "${sql}"
  fi
}

##############################################
# Create application user (idempotent)
##############################################
log "👤 Ensuring PostgreSQL user '${APP_USER}' exists…"

pg_exec "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${APP_USER}') THEN
    CREATE USER ${APP_USER} WITH PASSWORD '${APP_USER_PWD}';
  END IF;
END
\$\$;
"

##############################################
# Create app DB if needed
##############################################
log "📦 Ensuring database '${APP_DB_NAME}' exists…"

DB_EXISTS=$(pg_exec "SELECT 1 FROM pg_database WHERE datname='${APP_DB_NAME}';" \
           2>/dev/null | grep -q 1 && echo 1 || echo 0)

if [[ "$DB_EXISTS" != 1 ]]; then
  log "📌 Creating database '${APP_DB_NAME}' owned by '${APP_USER}'…"
  pg_exec "CREATE DATABASE ${APP_DB_NAME} OWNER ${APP_USER};"
else
  log "ℹ️ Database '${APP_DB_NAME}' already exists."
fi

##############################################
# Fix schema ownership BEFORE migrations
##############################################
log "🔐 Ensuring APP_USER owns schema public…"

pg_exec_db "${APP_DB_NAME}" "
ALTER SCHEMA public OWNER TO ${APP_USER};
GRANT ALL PRIVILEGES ON SCHEMA public TO ${APP_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO ${APP_USER};
"

##############################################
# Fix ownership of existing tables, sequences, views
##############################################
log "🛠 Fixing ownership of all existing objects…"

pg_exec_db "${APP_DB_NAME}" "
DO \$\$
DECLARE r RECORD;
BEGIN
  -- Tables
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public'
  LOOP
    EXECUTE format('ALTER TABLE public.%I OWNER TO ${APP_USER}', r.tablename);
  END LOOP;

  -- Sequences
  FOR r IN SELECT sequencename FROM pg_sequences WHERE schemaname='public'
  LOOP
    EXECUTE format('ALTER SEQUENCE public.%I OWNER TO ${APP_USER}', r.sequencename);
  END LOOP;

  -- Views
  FOR r IN SELECT viewname FROM pg_views WHERE schemaname='public'
  LOOP
    EXECUTE format('ALTER VIEW public.%I OWNER TO ${APP_USER}', r.viewname);
  END LOOP;
END
\$\$;
"

##############################################
# Enable extensions
##############################################
log "🧩 Enabling extensions…"

for ext in "${POSTGRES_EXTENSIONS[@]}"; do
  log "   → ${ext}"
  pg_exec_db "${APP_DB_NAME}" "CREATE EXTENSION IF NOT EXISTS \"${ext}\";"
done

##############################################
# Export SQLx DATABASE_URL
##############################################
export DATABASE_URL="postgres://${APP_USER}:${APP_USER_PWD}@127.0.0.1:${DB_PORT}/${APP_DB_NAME}"
log "🔗 DATABASE_URL='${DATABASE_URL}'"

##############################################
# Run SQLx migrations
##############################################
log "🚀 Running SQLx migrations…"

sqlx database create || true
sqlx migrate run

log "🎉 PostgreSQL is fully initialized and ready!"
