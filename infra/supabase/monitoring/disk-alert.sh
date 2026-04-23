#!/usr/bin/env bash
# =============================================================================
#  disk-alert.sh
#  Alerte Telegram si utilisation disque dépasse un seuil.
#
#  Couverture spec : FR-022
#
#  Usage :
#    DISK_PATH=/var/lib/docker DISK_THRESHOLD=80 /usr/local/bin/disk-alert.sh
#
#  Config :
#    DISK_PATH       — chemin à surveiller (défaut /var/lib/docker)
#    DISK_THRESHOLD  — seuil % (défaut 80)
#    ENV_FILE        — chemin env avec TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID
#                      (défaut /etc/supabase-backup/env — même fichier que pg-backup)
#
#  Cron suggéré :
#    */15 * * * * root /usr/local/bin/disk-alert.sh >> /var/log/disk-alert.log 2>&1
# =============================================================================

set -Eeuo pipefail

DISK_PATH="${DISK_PATH:-/var/lib/docker}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
ENV_FILE="${ENV_FILE:-/etc/supabase-backup/env}"
STATE_DIR="${STATE_DIR:-/var/lib/disk-alert}"
LOG_PREFIX="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] disk-alert:"

log() { echo "$LOG_PREFIX $*"; }

# Charge TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID depuis l'env file
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a && source "$ENV_FILE" && set +a
fi
[[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] \
  || { log "WARN: telegram creds missing, running silent"; }

notify() {
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || return 0
  curl -fsS --max-time 10 \
    -d "chat_id=${TELEGRAM_CHAT_ID}" \
    -d "text=$1" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" >/dev/null \
    || log "WARN: telegram notif failed"
}

# -----------------------------------------------------------------------------
# Lecture utilisation disque
# -----------------------------------------------------------------------------
if [[ ! -e "$DISK_PATH" ]]; then
  log "ERROR: path does not exist: $DISK_PATH"
  exit 1
fi

USED_PCT=$(df --output=pcent "$DISK_PATH" | tail -n1 | tr -d ' %')

if ! [[ "$USED_PCT" =~ ^[0-9]+$ ]]; then
  log "ERROR: could not parse disk usage: '$USED_PCT'"
  exit 1
fi

log "disk usage on $DISK_PATH: ${USED_PCT}% (threshold ${DISK_THRESHOLD}%)"

# -----------------------------------------------------------------------------
# Anti-spam : on n'envoie qu'un alert par tranche de 4 h si le seuil est franchi
# -----------------------------------------------------------------------------
mkdir -p "$STATE_DIR"
STATE_FILE="${STATE_DIR}/last-alert-$(echo "$DISK_PATH" | tr '/' '_')"

if (( USED_PCT >= DISK_THRESHOLD )); then
  NOW=$(date +%s)
  LAST_ALERT=0
  [[ -f "$STATE_FILE" ]] && LAST_ALERT=$(cat "$STATE_FILE")
  if (( NOW - LAST_ALERT >= 14400 )); then
    notify "⚠️ [disk-alert] ${DISK_PATH} utilisé à ${USED_PCT}% (seuil ${DISK_THRESHOLD}%) — host $(hostname)"
    echo "$NOW" > "$STATE_FILE"
    log "alert sent"
  else
    log "alert suppressed (anti-spam window, last alert $(( (NOW - LAST_ALERT) / 60 )) min ago)"
  fi
else
  # en dessous du seuil : on purge le state (prochaine alerte = immédiate)
  [[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE" && log "cleared alert state (below threshold)"
fi
