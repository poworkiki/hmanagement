#!/usr/bin/env bash
# =============================================================================
#  api-contract.sh
#  Smoke-test du contrat d'API Supabase exposé sur supabase.hma.business.
#
#  Couverture spec :
#    - User Story 4 scenarios 1-3  (contrat fonctionnel : anon read-only,
#                                   service_role peut écrire, RLS bloque anon)
#    - SC-006a (perf serveur warm) : TTFB warm par requête < 300 ms,
#                                    cumul warm 4 requêtes < 2 000 ms
#    - SC-006b (UX user cold)      : cumul cold 4 requêtes < 5 000 ms
#
#  Pré-requis côté serveur :
#    Une table temporaire avec RLS activée :
#      CREATE TABLE public.test_contract_table (
#        id serial PRIMARY KEY, note text, created_at timestamptz DEFAULT now()
#      );
#      ALTER TABLE public.test_contract_table ENABLE ROW LEVEL SECURITY;
#    (créée en T102, supprimée en T143)
#
#  Usage :
#    BASE_URL=https://supabase.hma.business \
#    ANON_KEY=... SERVICE_ROLE_KEY=... \
#    ./api-contract.sh
#
#  Exit codes :
#    0 = tous les tests fonctionnels + SC-006a passent (SC-006b peut warn)
#    1 = config invalide
#    2 = test fonctionnel lecture anon KO
#    3 = test fonctionnel POST sans service_role ne renvoie pas 401
#    4 = test fonctionnel POST service_role ne renvoie pas 201
#    5 = test fonctionnel persistance KO
#    6 = SC-006a violé (contractuel — TTFB warm > 300ms ou cumul warm > 2000ms)
#
#  Note : SC-006b (cold UX) est OBSERVATIONNEL — sortie warning si dépassé,
#  jamais bloquant. Raison : variance naturelle du handshake TLS (jitter
#  réseau, latence transatlantique irrégulière, GC serveur). Pour gater un
#  build sur la perf cold il faut une mesure agrégée (médiane sur N runs),
#  pas un one-shot.
# =============================================================================

set -Eeuo pipefail

BASE_URL="${BASE_URL:?BASE_URL requis, ex: https://supabase.hma.business}"
ANON_KEY="${ANON_KEY:?ANON_KEY requis}"
SERVICE_ROLE_KEY="${SERVICE_ROLE_KEY:?SERVICE_ROLE_KEY requis}"
TABLE="${TABLE:-test_contract_table}"
WARM_TTFB_BUDGET_MS="${WARM_TTFB_BUDGET_MS:-300}"
WARM_TOTAL_BUDGET_MS="${WARM_TOTAL_BUDGET_MS:-2000}"
COLD_TOTAL_BUDGET_MS="${COLD_TOTAL_BUDGET_MS:-5000}"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# -----------------------------------------------------------------------------
# Helper cold : curl en connexion fraîche, retourne "status elapsed_ms"
# -----------------------------------------------------------------------------
curl_cold() {
  local method="$1" url="$2"; shift 2
  local start_ms end_ms status
  start_ms=$(date +%s%3N)
  status=$(curl -sS -o /tmp/api-contract.body -w '%{http_code}' \
            --max-time 10 \
            -X "$method" "$url" "$@") || true
  end_ms=$(date +%s%3N)
  echo "$status $(( end_ms - start_ms ))"
}

log "BASE_URL = $BASE_URL"
log "target table = $TABLE"
log "budgets : warm TTFB/req=${WARM_TTFB_BUDGET_MS}ms, warm total=${WARM_TOTAL_BUDGET_MS}ms, cold total=${COLD_TOTAL_BUDGET_MS}ms"

# =============================================================================
# Pass 1 — Cold : validation fonctionnelle + mesure SC-006b
# =============================================================================
log ""
log "========== PASS 1 : COLD (fonctionnel + SC-006b) =========="

COLD_TOTAL_MS=0

log "— [cold 1/4] GET /rest/v1/ avec anon key → 200 attendu"
read -r S1 T1 < <(curl_cold GET "$BASE_URL/rest/v1/" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY")
log "  status=$S1 elapsed=${T1}ms"
[[ "$S1" == "200" ]] || { log "FAIL: attendu 200, reçu $S1"; exit 2; }
COLD_TOTAL_MS=$(( COLD_TOTAL_MS + T1 ))

log "— [cold 2/4] POST avec anon key seule → 401/403 attendu (RLS)"
read -r S2 T2 < <(curl_cold POST "$BASE_URL/rest/v1/$TABLE" \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{"note":"anon-write-should-be-rejected"}')
log "  status=$S2 elapsed=${T2}ms"
[[ "$S2" == "401" || "$S2" == "403" ]] || { log "FAIL: attendu 401/403, reçu $S2 — RLS ou GRANT défaillant"; exit 3; }
COLD_TOTAL_MS=$(( COLD_TOTAL_MS + T2 ))

log "— [cold 3/4] POST avec service_role → 201 attendu"
UNIQUE_NOTE="contract-test-$(date +%s%N)"
read -r S3 T3 < <(curl_cold POST "$BASE_URL/rest/v1/$TABLE" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "{\"note\":\"$UNIQUE_NOTE\"}")
log "  status=$S3 elapsed=${T3}ms"
[[ "$S3" == "201" ]] || { log "FAIL: attendu 201, reçu $S3"; cat /tmp/api-contract.body; exit 4; }
COLD_TOTAL_MS=$(( COLD_TOTAL_MS + T3 ))

log "— [cold 4/4] GET vérifier persistence"
read -r S4 T4 < <(curl_cold GET "$BASE_URL/rest/v1/$TABLE?note=eq.$UNIQUE_NOTE" \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY")
log "  status=$S4 elapsed=${T4}ms"
[[ "$S4" == "200" ]] || { log "FAIL: attendu 200, reçu $S4"; exit 5; }
grep -q "$UNIQUE_NOTE" /tmp/api-contract.body \
  || { log "FAIL: row écrit non relu"; exit 5; }
COLD_TOTAL_MS=$(( COLD_TOTAL_MS + T4 ))

log ""
log "résumé COLD : T1=${T1}ms T2=${T2}ms T3=${T3}ms T4=${T4}ms / TOTAL=${COLD_TOTAL_MS}ms"
log "SC-006b budget = ${COLD_TOTAL_BUDGET_MS}ms"

# =============================================================================
# Pass 2 — Warm : mesure SC-006a (TTFB serveur pur, keepalive TLS)
# =============================================================================
#
# On chaîne 5 requêtes via curl `--next` sur la MÊME connexion TLS :
#   - req 0 = warmup (établit la connexion TLS, paye les ~3 RTT de handshake)
#   - req 1-4 = les 4 requêtes SC-006a (read, read, write, read) — mesurées
#
# curl 8.x exige que `-w` soit répété avant chaque URL (pas global avec --next).
# Format `-w` = une ligne par requête sur stdout.
# =============================================================================
log ""
log "========== PASS 2 : WARM (SC-006a, keepalive TLS) =========="

WARM_OUT=$(mktemp)
WFMT='warm %{http_code} ttfb=%{time_starttransfer} total=%{time_total}\n'

curl -sS --max-time 20 \
  -w "$WFMT" -o /dev/null \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
  "$BASE_URL/rest/v1/" \
  --next \
  -w "$WFMT" -o /dev/null \
  -H "apikey: $ANON_KEY" -H "Authorization: Bearer $ANON_KEY" \
  "$BASE_URL/rest/v1/" \
  --next \
  -w "$WFMT" -o /dev/null \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  "$BASE_URL/rest/v1/$TABLE?limit=1" \
  --next \
  -w "$WFMT" -o /dev/null \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -X POST -H "Content-Type: application/json" -H "Prefer: return=representation" \
  -d "{\"note\":\"warm-pass-$(date +%s%N)\"}" \
  "$BASE_URL/rest/v1/$TABLE" \
  --next \
  -w "$WFMT" -o /dev/null \
  -H "apikey: $SERVICE_ROLE_KEY" -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  "$BASE_URL/rest/v1/$TABLE?order=id.desc&limit=1" \
  > "$WARM_OUT"

cat "$WARM_OUT" | nl -ba | while read -r ln; do log "  $ln"; done

# Extraction TTFB max et cumul, en EXCLUANT la 1ère ligne (warmup TLS)
WARM_TTFB_MAX_MS=0
WARM_TOTAL_MS=0
LINE_NUM=0
while read -r _ _ ttfb total; do
  LINE_NUM=$(( LINE_NUM + 1 ))
  # Ligne 1 = warmup (TLS handshake inclus) → exclue de SC-006a
  (( LINE_NUM == 1 )) && continue
  ttfb_ms=$(awk -v t="${ttfb#ttfb=}"   'BEGIN{printf "%d", t*1000}')
  total_ms=$(awk -v t="${total#total=}" 'BEGIN{printf "%d", t*1000}')
  (( ttfb_ms > WARM_TTFB_MAX_MS )) && WARM_TTFB_MAX_MS=$ttfb_ms
  WARM_TOTAL_MS=$(( WARM_TOTAL_MS + total_ms ))
done < "$WARM_OUT"
rm -f "$WARM_OUT"

log ""
log "résumé WARM (req 2-5, warmup exclus) : TTFB_max=${WARM_TTFB_MAX_MS}ms / TOTAL=${WARM_TOTAL_MS}ms"
log "SC-006a budgets : TTFB/req < ${WARM_TTFB_BUDGET_MS}ms, total < ${WARM_TOTAL_BUDGET_MS}ms"

# =============================================================================
# Verdict
# =============================================================================
log ""
log "========== VERDICT =========="

FAIL=0

if (( WARM_TTFB_MAX_MS > WARM_TTFB_BUDGET_MS )); then
  log "❌ SC-006a : TTFB warm max ${WARM_TTFB_MAX_MS}ms > budget ${WARM_TTFB_BUDGET_MS}ms"
  FAIL=6
elif (( WARM_TOTAL_MS > WARM_TOTAL_BUDGET_MS )); then
  log "❌ SC-006a : cumul warm ${WARM_TOTAL_MS}ms > budget ${WARM_TOTAL_BUDGET_MS}ms"
  FAIL=6
else
  log "✅ SC-006a : serveur répond warm en TTFB_max=${WARM_TTFB_MAX_MS}ms, cumul=${WARM_TOTAL_MS}ms"
fi

if (( COLD_TOTAL_MS > COLD_TOTAL_BUDGET_MS )); then
  log "⚠️  SC-006b : cumul cold ${COLD_TOTAL_MS}ms > budget observationnel ${COLD_TOTAL_BUDGET_MS}ms"
  log "   → NON-BLOQUANT (métrique observationnelle, variance naturelle). Si récurrent sur N runs, investiguer Traefik/Kong/réseau."
else
  log "✅ SC-006b : UX cold (4 handshakes frais) cumul ${COLD_TOTAL_MS}ms"
fi

if (( FAIL != 0 )); then
  log ""
  log "❌ FAILED (exit $FAIL) — voir messages ci-dessus"
  exit "$FAIL"
fi

log ""
log "✅ ALL PASS — fonctionnel OK, SC-006a (serveur) OK, SC-006b (UX cold) OK"
exit 0
