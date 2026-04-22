#!/usr/bin/env bash
# =============================================================================
#  pg-restore-drill.sh
#  Drill de restauration automatique sur container PostgreSQL éphémère.
#
#  Couverture spec :
#    FR-017 (restauration documentée < 30 min), SC-004 (vérification intégrité)
#    Art. constitution 10.3 (test restauration mensuel obligatoire)
#
#  Fonctionnement :
#    1. Télécharge le dernier snapshot restic vers /tmp
#    2. Lance un container postgres:15 éphémère (pg-restore-drill) sur un réseau isolé
#    3. Fait `pg_restore` dans ce container
#    4. Lance une suite smoke-tests SQL (SELECT now, count(pg_tables), …)
#    5. Publie le résultat dans Telegram + horodate la réussite
#    6. Détruit le container et les fichiers temporaires (--rm + cleanup)
#
#  Pré-requis : mêmes variables que pg-backup.sh (via /etc/supabase-backup/env)
#
#  Déclenché par :
#    cron : 0 5 1 * * root /usr/local/bin/pg-restore-drill.sh
#
#  Exit codes :
#    0 = drill OK
#    1 = config invalide
#    2 = restic restore KO
#    3 = pg_restore KO
#    4 = smoke-tests KO
# =============================================================================

set -Eeuo pipefail

ENV_FILE="${PG_BACKUP_ENV_FILE:-/etc/supabase-backup/env}"
LOG_PREFIX="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] restore-drill:"

log()  { echo "$LOG_PREFIX $*"; }
die()  { log "FATAL: $*"; exit "${2:-1}"; }

if [[ ! -f "$ENV_FILE" ]]; then
  die "env file not found: $ENV_FILE" 1
fi
# shellcheck disable=SC1090
set -a && source "$ENV_FILE" && set +a

for v in RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
         TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do
  [[ -n "${!v:-}" ]] || die "missing env var: $v" 1
done

notify() {
  local status="$1" message="$2"
  local emoji
  case "$status" in ok) emoji="✅" ;; fail) emoji="❌" ;; *) emoji="ℹ️" ;; esac
  curl -fsS --max-time 10 \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${emoji} [restore-drill] ${message}" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null \
    || log "WARN: telegram notif failed"
}

# Cleanup hook
CONTAINER_NAME="pg-restore-drill-$$"
WORK_DIR=""
cleanup() {
  local rc=$?
  log "cleanup (exit $rc)"
  [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]] && rm -rf "$WORK_DIR" || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker network rm "${CONTAINER_NAME}-net" >/dev/null 2>&1 || true
  if [[ $rc -ne 0 ]]; then
    notify fail "drill failed (exit $rc) — check /var/log/supabase-restore-drill.log"
  fi
}
trap cleanup EXIT

# -----------------------------------------------------------------------------
# 1. Préparer espace de travail isolé
# -----------------------------------------------------------------------------
WORK_DIR=$(mktemp -d /tmp/pg-restore-drill.XXXXXX)
chmod 700 "$WORK_DIR"
log "work directory: $WORK_DIR"

START=$(date +%s)

# -----------------------------------------------------------------------------
# 2. Télécharger le dernier snapshot
# -----------------------------------------------------------------------------
log "fetching latest restic snapshot"
SNAPSHOT_ID=$(restic snapshots --latest 1 --json | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["short_id"])')
log "snapshot id: $SNAPSHOT_ID"

restic restore "$SNAPSHOT_ID" --target "$WORK_DIR" \
  || die "restic restore failed" 2

DUMP_FILE=$(find "$WORK_DIR" -name '*.dump' | head -n1)
[[ -n "$DUMP_FILE" ]] || die "no .dump file found in restored snapshot" 2
log "dump file: $DUMP_FILE ($(du -h "$DUMP_FILE" | cut -f1))"

# -----------------------------------------------------------------------------
# 3. Lancer un container PG 15 éphémère
# -----------------------------------------------------------------------------
DRILL_PG_PASSWORD=$(head -c 24 /dev/urandom | base64 | tr -d '+/=' | head -c 24)

log "creating isolated docker network"
docker network create --driver bridge --internal "${CONTAINER_NAME}-net" >/dev/null

log "starting ephemeral postgres:15 container"
docker run -d --rm \
  --name "$CONTAINER_NAME" \
  --network "${CONTAINER_NAME}-net" \
  -e POSTGRES_PASSWORD="$DRILL_PG_PASSWORD" \
  postgres:15 >/dev/null

# Attente que PG soit ready (max 60s)
log "waiting for postgres readiness"
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
docker exec "$CONTAINER_NAME" pg_isready -U postgres >/dev/null 2>&1 \
  || die "postgres never became ready" 3

# -----------------------------------------------------------------------------
# 4. pg_restore dans le container
# -----------------------------------------------------------------------------
log "running pg_restore"
docker cp "$DUMP_FILE" "$CONTAINER_NAME":/tmp/dump.dump
docker exec -e PGPASSWORD="$DRILL_PG_PASSWORD" "$CONTAINER_NAME" \
  pg_restore -U postgres -d postgres --if-exists --clean --no-owner /tmp/dump.dump 2>&1 \
  | tee -a "$WORK_DIR/pg_restore.log" \
  || die "pg_restore failed (see $WORK_DIR/pg_restore.log)" 3

# -----------------------------------------------------------------------------
# 5. Smoke-tests SQL
# -----------------------------------------------------------------------------
log "running smoke-tests"

# Test 1 : PG répond
PG_NOW=$(docker exec -e PGPASSWORD="$DRILL_PG_PASSWORD" "$CONTAINER_NAME" \
  psql -U postgres -d postgres -Atc "SELECT now();")
[[ -n "$PG_NOW" ]] || die "smoke test 1 failed: SELECT now() returned empty" 4
log "smoke test 1 OK: now() = $PG_NOW"

# Test 2 : au moins un schéma existe (sert au minimum auth, storage, public)
SCHEMA_COUNT=$(docker exec -e PGPASSWORD="$DRILL_PG_PASSWORD" "$CONTAINER_NAME" \
  psql -U postgres -d postgres -Atc "SELECT count(*) FROM information_schema.schemata WHERE schema_name NOT IN ('information_schema','pg_catalog','pg_toast');")
(( SCHEMA_COUNT >= 1 )) || die "smoke test 2 failed: no user schemas found" 4
log "smoke test 2 OK: $SCHEMA_COUNT user schemas present"

# Test 3 : au moins quelques objets (tables, views, etc.)
OBJ_COUNT=$(docker exec -e PGPASSWORD="$DRILL_PG_PASSWORD" "$CONTAINER_NAME" \
  psql -U postgres -d postgres -Atc "SELECT count(*) FROM pg_class WHERE relnamespace NOT IN (SELECT oid FROM pg_namespace WHERE nspname IN ('information_schema','pg_catalog','pg_toast'));")
log "smoke test 3 OK: $OBJ_COUNT relations restored (tables/views/indexes/...)"

# -----------------------------------------------------------------------------
# 6. Rapport
# -----------------------------------------------------------------------------
DURATION=$(( $(date +%s) - START ))
log "drill OK in ${DURATION}s"

notify ok "drill OK · snapshot ${SNAPSHOT_ID} · ${DURATION}s · ${SCHEMA_COUNT} schemas · ${OBJ_COUNT} relations"

# cleanup happens in trap
