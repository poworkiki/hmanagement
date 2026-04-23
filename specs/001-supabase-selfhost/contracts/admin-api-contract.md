# Contract — Surface d'accès externe de la plateforme

**Feature** : `001-supabase-selfhost`
**Date** : 2026-04-22
**Nature du contrat** : définit **quelles URLs, ports et méthodes d'accès** la plateforme expose à des consommateurs externes (applications, outils ops, utilisateurs humains). Toute consommation hors de ce contrat est considérée hors scope et potentiellement bloquée côté réseau.

---

## 1. Endpoints HTTPS exposés (routés par Coolify/Traefik)

### 1.1 Supabase Studio (admin humain)

| Propriété | Valeur |
|---|---|
| URL | `https://supabase.hma.business/` |
| Protocole | HTTPS (TLS Let's Encrypt) |
| Authentification | Basic Auth (`DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`) **+** session Supabase via login GoTrue |
| Consommateurs autorisés | Super-admin HMA depuis navigateur |
| Acceptance | Charge en < 3 s depuis FAI standard EU (SC-001) |

### 1.2 GoTrue — Authentification (déléguée OIDC Authentik)

> Décision /speckit-clarify 2026-04-22 : auth déléguée à Authentik. Les endpoints Magic Link natifs (`/magiclink`, `/verify`) sont désactivés (`GOTRUE_EXTERNAL_EMAIL_ENABLED=false`).

| Propriété | Valeur |
|---|---|
| Base URL | `https://supabase.hma.business/auth/v1/` |
| Protocole | HTTPS |
| Authentification | Redirect OIDC vers Authentik, puis JWT |
| Endpoints critiques | `GET /authorize?provider=keycloak` (déclenche flow OIDC), `GET /callback` (retour IdP, échange code → JWT), `GET /user`, `POST /logout`, `POST /token?grant_type=refresh_token` (refresh JWT) |
| Flow utilisateur | Studio → clic "Sign in with Keycloak" → redirect `auth.hma.business` → Magic Link Authentik → TOTP (enforcé par groupe Authentik) → retour `supabase.hma.business/auth/v1/callback` → session JWT valide |
| Rate-limit & HIBP | **Enforcés côté Authentik** (policies dédiées sur le login flow) — pas côté GoTrue |
| Acceptance | User Story 2 : round-trip OIDC complet (click → redirect → Magic Link email ≤ 60 s → TOTP → callback) < 2 min |

### 1.3 PostgREST — API REST auto

| Propriété | Valeur |
|---|---|
| Base URL | `https://supabase.hma.business/rest/v1/` |
| Protocole | HTTPS |
| Authentification | Header `Authorization: Bearer <JWT>` + `apikey: <ANON_KEY ou SERVICE_ROLE_KEY>` |
| Rôles effectifs | Anonyme (via `ANON_KEY`, RLS active) · Admin (via `SERVICE_ROLE_KEY`, bypass RLS — usage restreint) |
| Consommateurs autorisés | App Next.js MVP (future), workflows n8n, scripts ops |
| Acceptance | `SELECT 1` équivalent (`/rest/v1/rpc/healthcheck` ou équivalent) < 800 ms p95 depuis Internet (User Story 4) |

### 1.4 Realtime & Storage — **hors scope MVP**

Les services Realtime (WebSocket) et Storage (fichiers) font partie de l'image Supabase et seront démarrés pour ne pas casser le template Coolify, mais :
- **Realtime** : aucun consommateur autorisé MVP (aucune feature ne l'exploite). Les ports sont exposés mais pas documentés dans ce contrat.
- **Storage** : idem, bucket inactif. Surveillance par Uptime Kuma uniquement pour éviter une panne silencieuse.

---

## 2. Accès PostgreSQL direct (clients SQL et outils internes)

| Propriété | Valeur |
|---|---|
| Hôte | `supabase.hma.business` (DNS → VPS Hostinger) |
| Port | `5432` **non exposé publiquement** en MVP |
| Accès | **Tunnel SSH** depuis le poste du super-admin via `ssh hma` (entrée déjà présente dans `~/.ssh/config`), port-forwarding local `localhost:5433 → localhost:5432` du conteneur PG |
| Credentials | Utilisateur `postgres` + `POSTGRES_PASSWORD` (pour administration) — **jamais** pour l'app |
| Consommateurs autorisés | Super-admin depuis poste local ; scripts cron backup sur le VPS |
| Acceptance | Connexion aboutie et `SELECT 1` renvoie `1` (User Story 1 scenario 3) |

**Rationale** : ne pas exposer 5432 publiquement réduit drastiquement la surface d'attaque. Les futurs outils applicatifs (Next.js, n8n, dbt) passent par PostgREST ou par rôle dédié avec whitelist IP, décidé dans la feature suivante.

---

## 3. Accès interne VPS (ops)

| Usage | Méthode | Consommateurs |
|---|---|---|
| Déploiement / redéploiement | Coolify UI `https://coolify.hma.business` | Super-admin humain |
| Redémarrage manuel | Coolify UI "Restart" | Super-admin humain |
| Consultation logs conteneurs | Coolify UI Logs | Super-admin humain |
| Exécution script backup ad hoc | SSH + `/usr/local/bin/pg-backup.sh` (installé par l'implémentation) | Super-admin |
| Exécution drill restauration | SSH + `/usr/local/bin/pg-restore-drill.sh` | Cron système + super-admin à la demande |

---

## 4. Monitoring — ce que Uptime Kuma observe

| Probe | URL/méthode | Assertion | Notif si |
|---|---|---|---|
| Studio | `HEAD https://supabase.hma.business/` | Status 200 | 2 échecs consécutifs (2 min) |
| Auth | `GET https://supabase.hma.business/auth/v1/health` | Status 200 + body `{"version":...}` | 2 échecs consécutifs |
| REST | `GET https://supabase.hma.business/rest/v1/` | Status 200 | 2 échecs consécutifs |
| TLS cert | Le même sur chaque probe HTTPS | Expiration > 14 jours | Expiration < 14 jours |

Cible du canal de notif : Telegram `hmagents_bot` + email `hmagestion@gmail.com`.

---

## 5. Flux "externe → plateforme" autorisés

```
┌─────────────────────────────┐
│ Super-admin (navigateur)    │──HTTPS (443)──▶  supabase.hma.business (Studio, Auth, REST)
└─────────────────────────────┘

┌─────────────────────────────┐
│ App Next.js MVP (future)    │──HTTPS (443)──▶  /rest/v1  +  /auth/v1
└─────────────────────────────┘

┌─────────────────────────────┐
│ Workflows n8n (même VPS)    │──réseau Docker interne──▶  kong / postgrest / gotrue
└─────────────────────────────┘

┌─────────────────────────────┐
│ Super-admin (ssh hma)       │──SSH (22)──▶  VPS Hostinger ──tunnel──▶ PG 5432
└─────────────────────────────┘

┌─────────────────────────────┐
│ Cron backup sur VPS         │──local + R2 S3 API──▶  Cloudflare R2 (backups chiffrés)
└─────────────────────────────┘

┌─────────────────────────────┐
│ Uptime Kuma (même VPS)      │──HTTPS interne──▶  endpoints Supabase
└─────────────────────────────┘
```

**Flux interdits** : accès direct PG depuis Internet (port 5432 non mappé), accès HTTP non-TLS (Traefik redirige 80→443 automatiquement).

---

## 6. Acceptance globale du contrat

Le contrat est satisfait si :
1. Tous les endpoints de la section 1 répondent 200 (ou 401 si JWT manquant) depuis un client extérieur au VPS,
2. L'assertion de la section 2 (tunnel SSH + `SELECT 1`) est validée,
3. Les 4 probes Uptime Kuma sont en état "Up" depuis ≥ 10 minutes consécutives,
4. Un `nmap` externe sur `supabase.hma.business` ne liste **que** les ports 80 (redirect) et 443 ouverts.
