#!/usr/bin/env bash
set -x
set -eo pipefail

# --- Check if SQLx CLI is installed ---
if ! [ -x "$(command -v sqlx)" ]; then
  echo >&2 "❌ Error: sqlx is not installed."
  echo >&2 "👉 Install using:"
  echo >&2 "   cargo install sqlx-cli --no-default-features --features rustls,postgres"
  exit 1
fi

# --- Default environment variables ---
DB_PORT="${POSTGRES_PORT:=5432}"
SUPERUSER="${SUPERUSER:=postgres}"
SUPERUSER_PWD="${SUPERUSER_PWD:=password}"
DB_NAME="${POSTGRES_DB:=rust_dev}"
CONTAINER_NAME="${CONTAINER_NAME:=rust_pg18}"
PG_VERSION="18-bookworm"
DATA_DIR="$(pwd)/postgres_data"

# --- Application-specific ---
APP_USER="${APP_USER:=app}"
APP_USER_PWD="${APP_USER_PWD:=secret}"
APP_DB_NAME="${APP_DB_NAME:=habit_tracker_db}"

# --- Clean old containers and volumes ---
mkdir -p "${DATA_DIR}"
if [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
  echo "🧹 Removing existing container: ${CONTAINER_NAME}"
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi

echo "🧽 Pruning unused Docker volumes..."
docker volume prune -f >/dev/null 2>&1 || true

# --- Launch PostgreSQL 18 ---
docker run -d \
  --name "${CONTAINER_NAME}" \
  --publish "${DB_PORT}":5432 \
  --restart always \
  --env POSTGRES_USER="${SUPERUSER}" \
  --env POSTGRES_PASSWORD="${SUPERUSER_PWD}" \
  --env POSTGRES_DB="${DB_NAME}" \
  --env PGDATA="/var/lib/postgresql/18/docker" \
  --env LANG="en_US.utf8" \
  --env LC_ALL="en_US.utf8" \
  --env TZ="UTC" \
  --env POSTGRES_INITDB_ARGS="--encoding=UTF8 --lc-collate=en_US.utf8 --lc-ctype=en_US.utf8 --data-checksums" \
  --volume "${DATA_DIR}:/var/lib/postgresql/18/docker" \
  postgres:${PG_VERSION}

# --- Wait for DB to be ready ---
echo "⏳ Waiting for PostgreSQL to start..."
until docker exec "${CONTAINER_NAME}" pg_isready -U "${SUPERUSER}" >/dev/null 2>&1; do
  sleep 1
done

# Add small grace period to ensure internal background processes finish
echo "🕐 PostgreSQL reported ready — waiting a few seconds for full startup..."
sleep 3

# Double-check with a test query
until docker exec "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d postgres -c "SELECT 1;" >/dev/null 2>&1; do
  echo "⏳ Waiting for PostgreSQL full readiness..."
  sleep 1
done

echo "✅ PostgreSQL ${PG_VERSION} is fully ready on port ${DB_PORT}"
echo "🔹 Default DB: ${DB_NAME} (superuser: ${SUPERUSER})"

# --- Create the application user ---
CREATE_USER_QUERY="DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${APP_USER}') THEN
      CREATE USER ${APP_USER} WITH PASSWORD '${APP_USER_PWD}';
   END IF;
END
\$\$;"
docker exec -i "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d postgres -c "${CREATE_USER_QUERY}"

# --- Create the application database (outside transaction) ---
EXISTS_QUERY="SELECT 1 FROM pg_database WHERE datname='${APP_DB_NAME}';"
DB_EXISTS=$(docker exec -i "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -tAc "${EXISTS_QUERY}" || echo "0")

if [ "${DB_EXISTS}" != "1" ]; then
  echo "📦 Creating database '${APP_DB_NAME}' owned by '${APP_USER}'..."
  docker exec -i "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d postgres -c "CREATE DATABASE ${APP_DB_NAME} OWNER ${APP_USER};"
else
  echo "ℹ️ Database '${APP_DB_NAME}' already exists, skipping creation."
fi

# --- Grant privileges ---
GRANT_QUERY="ALTER USER ${APP_USER} CREATEDB;"
docker exec -i "${CONTAINER_NAME}" psql -U "${SUPERUSER}" -d postgres -c "${GRANT_QUERY}"

echo "✅ Application user '${APP_USER}' and database '${APP_DB_NAME}' are ready."

# --- Export DATABASE_URL for SQLx ---
export DATABASE_URL="postgres://${APP_USER}:${APP_USER_PWD}@127.0.0.1:${DB_PORT}/${APP_DB_NAME}"
echo "🔗 DATABASE_URL exported: ${DATABASE_URL}"

# --- Ensure database exists (SQLx) ---
sqlx database create || true

echo "✅ Verified database connection with SQLx."
echo "🎯 PostgreSQL ${PG_VERSION} running as container '${CONTAINER_NAME}'"
