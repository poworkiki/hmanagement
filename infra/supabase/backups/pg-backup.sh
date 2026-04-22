#!/usr/bin/env bash
# =============================================================================
#  pg-backup.sh
#  Sauvegarde chiffrée de la base PostgreSQL Supabase vers Cloudflare R2.
#
#  Couverture spec :
#    FR-014 (quotidien), FR-015 (chiffré), FR-016 (rétention 30 + 12),
#    FR-018 (notif échec < 15 min)
#
#  Pré-requis :
#    - restic ≥ 0.17 installé (apt install restic)
#    - docker accessible pour root (pg_dump via docker exec)
#    - /etc/supabase-backup/env lisible root seulement (chmod 600), contenant :
#        RESTIC_REPOSITORY=s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/hma-supabase-backups
#        RESTIC_PASSWORD=<depuis Vaultwarden supabase-selfhost-restic-password>
#        AWS_ACCESS_KEY_ID=<depuis Vaultwarden supabase-selfhost-r2-access-key-id>
#        AWS_SECRET_ACCESS_KEY=<depuis Vaultwarden supabase-selfhost-r2-secret-access-key>
#        SUPABASE_PG_CONTAINER=<nom du conteneur Coolify, ex. supabase-db-<id>>
#        TELEGRAM_BOT_TOKEN=<bot token existant>
#        TELEGRAM_CHAT_ID=<chat id ops>
#
#  Usage :
#    /usr/local/bin/pg-backup.sh              # run normal
#    /usr/local/bin/pg-backup.sh --first-run  # init du repository restic avant 1er backup
#
#  Exit codes :
#    0 = OK
#    1 = erreur config (env manquant)
#    2 = erreur pg_dump
#    3 = erreur restic backup
#    4 = erreur restic forget / prune
# =============================================================================

set -Eeuo pipefail

# -----------------------------------------------------------------------------
# Configuration & chargement secrets
# -----------------------------------------------------------------------------
ENV_FILE="${PG_BACKUP_ENV_FILE:-/etc/supabase-backup/env}"
LOG_PREFIX="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] pg-backup:"

log()  { echo "$LOG_PREFIX $*"; }
die()  { log "FATAL: $*"; exit "${2:-1}"; }

if [[ ! -f "$ENV_FILE" ]]; then
  die "env file not found: $ENV_FILE (chmod 600 root:root)" 1
fi
# shellcheck disable=SC1090
set -a && source "$ENV_FILE" && set +a

for v in RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY \
         SUPABASE_PG_CONTAINER TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do
  [[ -n "${!v:-}" ]] || die "missing env var: $v" 1
done

# -----------------------------------------------------------------------------
# Notification Telegram
# -----------------------------------------------------------------------------
notify() {
  local status="$1" message="$2"
  local emoji
  case "$status" in
    ok)    emoji="✅" ;;
    warn)  emoji="⚠️" ;;
    fail)  emoji="❌" ;;
    *)     emoji="ℹ️" ;;
  esac
  curl -fsS --max-time 10 \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=${emoji} [supabase-backup] ${message}" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null \
    || log "WARN: failed to send telegram notification"
}

# Error trap : toute erreur non capturée → notif échec + exit
trap 'rc=$?; log "ERROR at line $LINENO (exit $rc)"; notify fail "backup failed at line $LINENO (exit $rc) — check /var/log/supabase-backup.log"; exit $rc' ERR

# -----------------------------------------------------------------------------
# Init du repository restic (1er run uniquement)
# -----------------------------------------------------------------------------
if [[ "${1:-}" == "--first-run" ]]; then
  log "first-run mode: checking repository state"
  if restic snapshots >/dev/null 2>&1; then
    log "repository already initialized, skipping init"
  else
    log "initializing restic repository"
    restic init
    notify ok "restic repository initialized on R2 bucket"
  fi
fi

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if ! docker ps --format '{{.Names}}' | grep -Fxq "$SUPABASE_PG_CONTAINER"; then
  die "supabase postgres container not found: $SUPABASE_PG_CONTAINER" 2
fi

if ! restic snapshots >/dev/null 2>&1; then
  die "restic repository unreachable or uninitialized (hint: --first-run)" 3
fi

# -----------------------------------------------------------------------------
# Dump + streaming vers restic (sans fichier intermédiaire sur disque)
# -----------------------------------------------------------------------------
SNAPSHOT_LABEL="postgres-$(date -u +%Y%m%dT%H%M%SZ).dump"
log "starting pg_dump + restic backup: $SNAPSHOT_LABEL"
START=$(date +%s)

docker exec -i "$SUPABASE_PG_CONTAINER" \
  pg_dump -U postgres -Fc -d postgres 2>&1 \
  | restic backup --stdin --stdin-filename "$SNAPSHOT_LABEL" --tag daily --host supabase-hma \
  || die "pg_dump | restic backup failed" 3

DURATION=$(( $(date +%s) - START ))
log "backup OK in ${DURATION}s"

# -----------------------------------------------------------------------------
# Rétention : 30 daily + 12 monthly, prune inline
# -----------------------------------------------------------------------------
log "applying retention policy (keep-daily=30, keep-monthly=12)"
restic forget --keep-daily 30 --keep-monthly 12 --prune --host supabase-hma \
  || die "restic forget/prune failed" 4

# -----------------------------------------------------------------------------
# Rapport
# -----------------------------------------------------------------------------
SNAPSHOT_COUNT=$(restic snapshots --json | python3 -c 'import sys,json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo "?")
REPO_SIZE=$(restic stats --mode raw-data --json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin).get("total_size",0))' 2>/dev/null || echo "?")
REPO_SIZE_H=$(numfmt --to=iec "$REPO_SIZE" 2>/dev/null || echo "${REPO_SIZE}B")

notify ok "backup OK in ${DURATION}s · ${SNAPSHOT_COUNT} snapshots · repo ${REPO_SIZE_H}"
log "done"
