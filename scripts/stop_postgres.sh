#!/usr/bin/env bash
set -eo pipefail

# Optional flags:
#   ./stop_postgres.sh --force   → skip confirmation
#   QUIET=true ./stop_postgres.sh → suppress extra logs

CONTAINER_NAME="${CONTAINER_NAME:=rust_pg18}"
DATA_DIR="$(pwd)/postgres_data"
AUTO_CONFIRM=false
QUIET="${QUIET:-false}"

# Parse flags
for arg in "$@"; do
  case $arg in
    -f|--force)
      AUTO_CONFIRM=true
      shift
      ;;
    -q|--quiet)
      QUIET=true
      shift
      ;;
  esac
done

log() {
  if [ "$QUIET" != "true" ]; then
    echo -e "$@"
  fi
}

# --- Stop container gracefully ---
if [ "$(docker ps -q -f name=^${CONTAINER_NAME}$)" ]; then
  log "🛑 Stopping PostgreSQL container: ${CONTAINER_NAME}..."
  docker stop -t 10 "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  sleep 2
else
  log "ℹ️ No running container named ${CONTAINER_NAME} found."
fi

# --- Wait for full shutdown ---
if [ "$(docker ps -aq -f name=^${CONTAINER_NAME}$)" ]; then
  log "🧹 Removing container ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  log "✅ Container ${CONTAINER_NAME} removed."
fi

# --- Optionally remove data directory ---
if [ "$AUTO_CONFIRM" = true ]; then
  CONFIRM="y"
else
  read -p "❓ Remove local data directory at ${DATA_DIR}? (y/N): " CONFIRM
fi

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
  if [ -d "${DATA_DIR}" ]; then
    rm -rf "${DATA_DIR}"
    log "✅ Data directory removed: ${DATA_DIR}"
  else
    log "ℹ️ Data directory not found (already deleted)."
  fi
else
  log "ℹ️ Data directory preserved at ${DATA_DIR}."
fi

# --- Optional cleanup: old volumes or networks ---
if [ "$AUTO_CONFIRM" = true ]; then
  docker volume prune -f >/dev/null 2>&1 || true
  docker network prune -f >/dev/null 2>&1 || true
  log "🧽 Pruned unused Docker volumes and networks."
fi

log "🎯 PostgreSQL container '${CONTAINER_NAME}' stopped successfully."
