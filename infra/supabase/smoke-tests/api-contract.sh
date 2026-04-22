#!/usr/bin/env bash
# =============================================================================
#  api-contract.sh
#  Smoke-test du contrat d'API Supabase exposé sur supabase.hma.business.
#
#  Couverture spec :
#    User Story 4 scenarios 1-3, SC-006 (< 2s cumulés lecture-écriture)
#
#  Pré-requis côté serveur :
#    Une table temporaire de test créée manuellement dans public :
#      CREATE TABLE public.test_contract_table (
#        id serial PRIMARY KEY,
#        note text,
#        created_at timestamptz DEFAULT now()
#      );
#    (créée en T102, supprimée en T143)
#
#  Usage :
#    BASE_URL=https://supabase.hma.business \
#    ANON_KEY=... SERVICE_ROLE_KEY=... \
#    ./api-contract.sh
#
#  Exit codes :
#    0 = tous les tests passent et SC-006 respecté (< 2s)
#    1 = config invalide
#    2 = test lecture anon KO
#    3 = test POST sans JWT ne renvoie pas 401 comme attendu
#    4 = test POST avec service_role ne renvoie pas 201 comme attendu
#    5 = test persistance après écriture KO
#    6 = SC-006 échoué (temps cumulé > 2s)
# =============================================================================

set -Eeuo pipefail

BASE_URL="${BASE_URL:?BASE_URL requis, ex: https://supabase.hma.business}"
ANON_KEY="${ANON_KEY:?ANON_KEY requis}"
SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY:?SERVICE_ROLE_KEY requis}"
TABLE="${TABLE:-test_contract_table}"
TIME_BUDGET_MS="${TIME_BUDGET_MS:-2000}"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# Helper : curl qui retourne le status code et la durée en ms
curl_timed() {
  local method="$1" url="$2"; shift 2
  local start_ms end_ms status
  start_ms=$(date +%s%3N)
  status=$(curl -sS -o /tmp/api-contract.body -w '%{http_code}' \
            --max-time 5 \
            -X "$method" "$url" "$@") || true
  end_ms=$(date +%s%3N)
  local elapsed=$(( end_ms - start_ms ))
  echo "$status $elapsed"
}

log "BASE_URL = $BASE_URL"
log "target table = $TABLE"
log "time budget cumulé = ${TIME_BUDGET_MS} ms"

TOTAL_MS=0

# -----------------------------------------------------------------------------
# Test 1 : GET /rest/v1/ avec anon key → 200 attendu
# -----------------------------------------------------------------------------
log "— test 1 : GET /rest/v1/ avec anon key"
read -r S1 T1 < <(curl_timed GET "$BASE_URL/rest/v1/" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY")
log "  status=$S1 elapsed=${T1}ms"
[[ "$S1" == "200" ]] || { log "FAIL: attendu 200, reçu $S1"; exit 2; }
TOTAL_MS=$(( TOTAL_MS + T1 ))

# -----------------------------------------------------------------------------
# Test 2 : POST sans JWT → 401 attendu (preuve que RLS bloque)
# -----------------------------------------------------------------------------
log "— test 2 : POST sans JWT → 401 attendu"
read -r S2 T2 < <(curl_timed POST "$BASE_URL/rest/v1/$TABLE" \
  -H "apikey: $ANON_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"note":"unauthorized-attempt"}')
log "  status=$S2 elapsed=${T2}ms"
# 401 Unauthorized (pas de Bearer) OU 403 (RLS) — les deux prouvent que l'anon ne peut pas écrire
if [[ "$S2" != "401" && "$S2" != "403" ]]; then
  log "FAIL: attendu 401/403, reçu $S2 — RLS ou JWT défaillant"; exit 3
fi
TOTAL_MS=$(( TOTAL_MS + T2 ))

# -----------------------------------------------------------------------------
# Test 3 : POST avec service_role → 201 attendu
# -----------------------------------------------------------------------------
log "— test 3 : POST avec service_role → 201 attendu"
UNIQUE_NOTE="contract-test-$(date +%s%N)"
read -r S3 T3 < <(curl_timed POST "$BASE_URL/rest/v1/$TABLE" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "{\"note\":\"$UNIQUE_NOTE\"}")
log "  status=$S3 elapsed=${T3}ms"
[[ "$S3" == "201" ]] || { log "FAIL: attendu 201, reçu $S3"; cat /tmp/api-contract.body; exit 4; }
TOTAL_MS=$(( TOTAL_MS + T3 ))
CREATED_ID=$(python3 -c 'import sys,json; print(json.load(sys.stdin)[0]["id"])' </tmp/api-contract.body 2>/dev/null || echo "?")
log "  created id=$CREATED_ID"

# -----------------------------------------------------------------------------
# Test 4 : GET vérifier persistance
# -----------------------------------------------------------------------------
log "— test 4 : GET row juste inséré"
read -r S4 T4 < <(curl_timed GET "$BASE_URL/rest/v1/$TABLE?note=eq.$UNIQUE_NOTE" \
  -H "apikey: $SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY")
log "  status=$S4 elapsed=${T4}ms"
[[ "$S4" == "200" ]] || { log "FAIL: attendu 200, reçu $S4"; exit 5; }
grep -q "$UNIQUE_NOTE" /tmp/api-contract.body \
  || { log "FAIL: row écrit non relu"; exit 5; }
TOTAL_MS=$(( TOTAL_MS + T4 ))

# -----------------------------------------------------------------------------
# Verdict
# -----------------------------------------------------------------------------
log ""
log "résumé latences (ms) :"
log "  T1 (GET anon)        = ${T1}"
log "  T2 (POST no jwt)     = ${T2}"
log "  T3 (POST service)    = ${T3}"
log "  T4 (GET verif)       = ${T4}"
log "  TOTAL cumulé         = ${TOTAL_MS}ms / budget ${TIME_BUDGET_MS}ms"

if (( TOTAL_MS > TIME_BUDGET_MS )); then
  log "FAIL SC-006: temps cumulé dépasse le budget"
  exit 6
fi

log ""
log "✅ all tests OK — contract honoured, SC-006 passed"
exit 0
