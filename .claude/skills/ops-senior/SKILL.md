---
name: ops-senior
description: Patterns ops/DevOps senior hmanagement — Coolify, Traefik, Vaultwarden, backups PostgreSQL, monitoring Grafana/Loki/Prometheus, CI GitHub Actions, secrets, observabilité n8n, souveraineté. Trigger pour toute question déploiement, hébergement, secrets, monitoring, sauvegardes, CI/CD, domaines/HTTPS, ou incident ops.
---

# Ops senior — hmanagement

## Stack souveraine (Article 2 constitution — NON NÉGOCIABLE)

```
VPS Hostinger (Europe, RGPD)
└── Coolify (orchestration Docker)
    ├── Traefik (reverse proxy + Let's Encrypt)
    ├── Supabase self-hosted (Postgres + GoTrue + PostgREST + Storage)
    ├── n8n (workflows Pennylane, webhooks)
    ├── Vaultwarden (coffre-fort secrets)
    ├── Grafana + Loki + Prometheus (observabilité)
    ├── Dozzle ou Uptime Kuma (logs + healthcheck)
    └── Next.js hmanagement (l'app)
```

**Aucun service US non conforme RGPD**. Pas de Vercel, Supabase cloud, Sentry SaaS, Datadog, Segment, etc. sans ADR explicite et DPA signé.

## Secrets — Vaultwarden only

1. Source de vérité des secrets = **Vaultwarden** (1 coffre par env : `hma-prod`, `hma-staging`, `hma-dev`)
2. Coolify récupère les secrets via variables d'environnement (UI Coolify → Env Variables)
3. **Jamais** de secret dans `.env.local` committé, dans du code, dans docker-compose.yml committé
4. Rotation trimestrielle minimum pour : service_role Supabase, tokens Pennylane, webhook n8n
5. Un secret compromis = rotation **immédiate** + audit log check

Inventaire du stack : voir `credentials-stack-hma.md` à la racine du repo.

## Traefik — règles de routing

- HTTPS partout, HTTP → HTTPS redirect automatique
- Certificats Let's Encrypt auto-renewed par Coolify
- Headers sécurité par défaut (via middleware Traefik) :
  - `Strict-Transport-Security: max-age=31536000; includeSubDomains`
  - `X-Content-Type-Options: nosniff`
  - `X-Frame-Options: DENY`
  - `Content-Security-Policy` à définir (Next.js + Supabase origins uniquement)
- **Jamais** exposer directement Postgres (5432), Redis, ou un service interne — tout passe par Traefik sur des routes HTTPS
- Supabase Studio sur un sous-domaine avec **restriction IP** ou auth basic Traefik

## PostgreSQL — backups (Article 10.3)

- Dump quotidien automatique via `pg_dump` (cron Coolify) → stockage **chiffré** (gpg) sur S3 souverain (Scaleway/OVH) + copie locale
- Rétention : **30 jours** quotidiens, **12 mois** mensuels, **5 ans** annuels
- **Test de restauration mensuel OBLIGATOIRE** (Article 10.3) :
  - Restaurer un dump sur un Postgres isolé
  - Lancer un `dbt test` complet
  - Vérifier nombre de lignes `raw.*` vs source
  - Documenter résultat dans `docs/restore-tests.md`
- Backup **avant chaque migration** en prod (script `supabase db dump` + tag git)

## Monitoring stack

| Signal | Outil | Alerte |
|---|---|---|
| Logs applicatifs Next.js | Loki (via promtail) | Erreur 5xx > 10/min → Discord |
| Métriques VPS | Prometheus + node_exporter | CPU > 80% 5min, disk > 85% |
| Métriques Postgres | postgres_exporter | Connexions > 80%, replication lag |
| Métriques n8n | n8n webhook Prometheus | Workflow fail, durée > 2× baseline |
| Healthchecks | Uptime Kuma | Ping toutes les 60s, 3 fails → Discord |
| Dashboards | Grafana | Board « hmanagement » figé en JSON committé |

Dashboards Grafana **versionnés en code** (`infra/grafana/dashboards/*.json`) — jamais éditer uniquement l'UI.

## Observabilité n8n (Article 10.1)

Chaque workflow **doit** :
1. Se terminer par un node `HTTP Request` → webhook Discord (succès ET échec, 2 branches)
2. Exposer ses métriques Prometheus (durée, rows traitées, errors) via node dédié
3. Idempotent (clé `source_id` côté raw)
4. Avoir un timeout explicite (défaut : 30min)
5. Logger le `run_id` dans `app.audit_log` à la fin

Template de notif Discord :
```
✅/❌ n8n: <nom_workflow>
Durée: <X>s | Rows: <N> | Sync: <timestamp>
Lien: <n8n_run_url>
```

## CI/CD GitHub Actions (Article 6.6 — bloquant merge)

`.github/workflows/ci.yml` — pipeline obligatoire sur toute PR :

1. **Lint** : `npm run lint` (ESLint + Prettier check)
2. **Typecheck** : `npm run typecheck`
3. **Tests unitaires** : `npm run test:unit` (Vitest)
4. **Tests intégration** : `npm run test:integration` (nécessite Postgres service container)
5. **Tests dbt** : `dbt deps && dbt build --select state:modified+` (sur manifest artifact)
6. **Tests E2E** : `npm run test:e2e` (Playwright, headless) — **uniquement PR**, pas sur push main
7. **Coverage calculs financiers = 100%** → fail si régression

Aucun merge possible si un step échoue (branch protection rules GitHub). `main` protégé + 1 review requise (auto-review mode review acceptable en MVP solo).

## Déploiement Coolify

- **Git auto-deploy** sur push `main` vers app de prod
- **Pre-deploy hook** : `supabase db push` + `dbt run --select state:modified+` avant bascule du front
- **Rollback** : en 1 clic via Coolify (conserve les 5 dernières images Docker)
- **Feature flag** (simple env var MVP) pour désactiver une feature en prod sans rollback
- Staging environment identique à prod (VPS séparé ou namespace Coolify)

## Session & auth ops (Article 4.3)

- Session timeout : **8h user, 1h admin** — enforced dans `middleware.ts` ET dans Supabase JWT settings
- MFA TOTP obligatoire pour `super_admin`/`admin` — check au login
- Magic Link SMTP via service souverain (Brevo, OVH, ou SMTP interne VPS)
- Bruteforce protection : rate limit sur `/login` via Traefik middleware (5 tentatives / 15 min / IP)

## Incident response — runbook minimal

1. **Détection** (Discord alert, user report)
2. **Contenir** : si fuite de données suspectée → désactiver compte impacté + invalider toutes sessions (`auth.users` → logout all)
3. **Investiguer** : `app.audit_log` + Loki logs Next.js + logs Traefik
4. **Remédier** : rollback Coolify si déploiement récent, hotfix branch + CI + merge
5. **Post-mortem** : doc dans `docs/incidents/YYYYMMDD-titre.md` + mise à jour `tech-debt.md` si besoin

## Souveraineté — checklist avant d'ajouter un service externe

Avant d'ajouter **toute** dépendance externe (SaaS, API, CDN, lib analytics) :

- [ ] Hébergement UE ?
- [ ] DPA RGPD signable ?
- [ ] Alternative self-hosted existe-t-elle ? (et ne l'ai-je pas ignorée par paresse ?)
- [ ] Données transmises minimisées (hash, pseudonymisées) ?
- [ ] ADR créé dans `docs/adr/` ?
- [ ] Secret ajouté à Vaultwarden ?
- [ ] Notif fallback si le service tombe ?

Si **un seul** ❌ : pas d'intégration.

## Anti-patterns ops (refus)
- ❌ Secret en clair dans Coolify Env UI « temporairement » (fuit dans les logs)
- ❌ Dump Postgres stocké en clair
- ❌ Dashboard Grafana éditable uniquement via UI (pas reproductible)
- ❌ Backup sans test de restauration (backup Schrödinger)
- ❌ `NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY` (service_role = serveur only, **jamais** public)
- ❌ Déploiement prod le vendredi soir (règle non écrite mais sacrée — sauf hotfix sécu)
- ❌ n8n workflow sans notification de fin
- ❌ Désactiver RLS « le temps de debugger » sur la prod
- ❌ Monter Postgres en local sur le VPS sans sauvegarde avant
- ❌ Laisser un port exposé publiquement « parce que ça marche »
