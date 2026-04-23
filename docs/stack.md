# Stack technique — hmanagement

> **Statut** : validé Sprint 0 — version de référence avant `npm init`.
> **Principe directeur** : un seul outil par besoin, auto-hébergeable, stable ≥ 2 ans. Tout changement = ADR.

---

## 1. Vue d'ensemble

| Couche | Outil | Version min | Auto-hébergé |
|---|---|---|---|
| Runtime | Node.js | 20 LTS | — |
| Framework web | Next.js (App Router) | 15.x | ✅ (Coolify) |
| Langage | TypeScript `strict` | 5.4+ | — |
| Styling | Tailwind CSS | v4 | — |
| UI kit | shadcn/ui (Radix) | dernière | — |
| Data-viz | Tremor (wraps Recharts) | 3.18+ | — |
| Tables | TanStack Table + Virtual | v8 | — |
| Data client | TanStack Query | v5 | — |
| Forms | React Hook Form + Zod | 7 / 3.23+ | — |
| SDK Supabase | `@supabase/ssr` | dernière | — |
| Backend | Supabase self-hosted | dernière stable | ✅ |
| DB | PostgreSQL | 16 | ✅ (via Supabase) |
| Transformations | dbt Core | 1.7+ | ✅ |
| Orchestration | n8n | déjà déployé | ✅ |
| Tests unit | Vitest + Testing Library | dernière | — |
| Tests DOM | happy-dom | dernière | — |
| Tests E2E | Playwright | dernière | — |
| Lint / format | ESLint 9 flat + Prettier 3 | dernière | — |
| Git hooks | Husky + lint-staged | dernière | — |
| Reverse proxy | Traefik (via Coolify) | intégré | ✅ |
| Secrets | Vaultwarden | déjà déployé | ✅ |
| Monitoring | Grafana + Loki + Prometheus | déjà déployé | ✅ |
| Healthcheck | Uptime Kuma | déjà déployé | ✅ |
| CI | GitHub Actions | — | — |

## 2. Frontend — Next.js 15 App Router

### Pourquoi ce choix
- **Server Components natifs** : permettent de lire les marts Supabase sans JSON roundtrip + RLS appliquée au niveau DB
- **Server Actions** : mutations typées sans construire d'API REST parallèle
- **Streaming + Suspense** : drill-down UI perçu instantané même sur marts lourds
- **Caching granularité route/fetch** : contrôle fin pour data financière

### Règle d'or
Tout composant est **Server Component par défaut**. `'use client'` uniquement si : state, effects, event handlers, browser APIs, ou hook client. Interdit sur un layout ou une page sans commentaire justificatif.

### Fetching
| Cas | Outil |
|---|---|
| Lecture mart en page | Server Component + `@supabase/ssr` serveur |
| Mutation | Server Action + `revalidatePath` |
| Filtre interactif | Server Action + TanStack Query côté Client |
| Table tri/pagination client | TanStack Table (data chargée serveur) |
| Temps réel | ❌ Hors scope MVP |

### Styling / UI
- **shadcn/ui** pour Layout, formulaires, navigation, dialogs — copy/paste dans `src/components/ui/`
- **Tremor** pour KPI Cards, BadgeDelta, SparkChart, AreaChart, BarChart — via `@tremor/react`
- **Tailwind v4** — pas de CSS module, pas de styled-components

### Data-viz — position tranchée
- Tremor **uniquement** pour les graphiques financiers (couvre 100% du besoin MVP)
- Recharts **interdit en import direct** (Tremor l'embarque, c'est ok indirect)
- **Jamais** : Chart.js, Nivo, Victory, ApexCharts

## 3. Backend — Supabase self-hosted

### Pourquoi ce choix
- **Tout-en-un** : Postgres + Auth + PostgREST + Storage + Realtime
- **RLS natif** : sécurité au niveau DB, impossible à bypasser depuis le front
- **Auto-REST via PostgREST** : pas d'API à écrire pour 80% des lectures
- **TypeScript types générés** depuis le schéma (`supabase gen types typescript`)
- **Self-hosted obligatoire** (Article 2 constitution) : souveraineté Guyane / RGPD

### Ce qu'on utilise
- **Postgres 16** pour toutes les données (OLTP + OLAP — volume HMA ne justifie pas un DW séparé)
- **GoTrue** pour auth Magic Link + MFA TOTP
- **PostgREST** pour les lectures marts simples
- **Storage** pour les exports CSV, PDF futurs
- **Studio** pour l'admin technique (Kiki uniquement, IP whitelist Traefik)

### Ce qu'on n'utilise PAS en MVP
- **Edge Functions Deno** : Next.js Server Actions suffisent pour le MVP. On y viendra si besoin de webhook Pennylane push ou traitement async service_role.
- **Realtime** : hors scope MVP (pas besoin de collaboration live).
- **pgvector** : reporté V2 (stack IA).

### Décision — Supabase self-hosted vs Cloud
Cloud interdit (Article 2). 2 entrées Supabase Cloud existent dans Vaultwarden « en veille » — à désactiver formellement (voir ADR-0001).

## 4. Transformations — dbt Core

### Pourquoi ce choix
- **SQL versionné + tests de qualité** = calculs financiers auditables
- **Macros réutilisables** (ex: `cents_to_euros`) = une formule, un endroit
- **Docs auto-générées** + DAG visuel = onboarding V2 facile
- **`dbt build --select state:modified+`** = CI rapide, pas de re-run complet

### Structure (stricte)
```
dbt/models/
├── staging/        stg_<source>__<entity>.sql  (1:1, nettoyage uniquement)
├── intermediate/   int_*.sql                   (jointures intermédiaires)
└── marts/
    ├── compte_resultat/  mart_cr_*.sql
    ├── crd/              mart_crd_*.sql
    ├── sig/              mart_sig_*.sql
    └── dim/              dim_*.sql
```

### Contrat non-négociable
- **Chaque mart** : ≥ 3 tests (`not_null` PK, `relationships` FK, `expression_is_true` règle métier)
- **Chaque mart** : entrée dans `_marts.yml` avec description **en français** par colonne
- **Staging** : pas de logique métier, uniquement nettoyage + `cents_to_euros`
- **Interdit** : `select *`, jointure sans `on`, `mart → mart` (créer un `int_`)

## 5. Orchestration — n8n

### Déjà déployé sur `n8n.hma.business`
### Usage hmanagement
- Sync quotidien Pennylane → `raw.pennylane_*` (4 APIs : HMA, STIVMAT, STA, ETPA)
- Trigger `dbt run --select state:modified+` après sync
- Webhook Discord en fin de workflow (succès ET échec)

### Contrat n8n
- **Aucune transformation métier** dans n8n (transport + idempotence uniquement)
- **Idempotent** : clé `(source, source_id, extracted_at)` pour dédupliquer
- **Timeout explicite** par workflow (30min max défaut)

## 6. Infra — Coolify + Traefik + VPS Hostinger

### Topologie
```
VPS Hostinger (Ubuntu 24.04, IP 187.124.150.82, Europe/RGPD)
└── Coolify (Docker orchestrator)
    ├── Traefik (reverse proxy + Let's Encrypt auto)
    ├── Supabase self-hosted (Postgres, GoTrue, PostgREST, Kong, Studio)
    ├── n8n (existant — workflows Pennylane)
    ├── Vaultwarden (existant — secrets)
    ├── Grafana + Loki + Prometheus (existant — observabilité)
    ├── Uptime Kuma (existant — healthcheck)
    ├── Authentik (existant — SSO, cf. ADR-0002 pour usage hmanagement)
    └── Next.js hmanagement (l'app)
```

### Alerte capacité — à vérifier avant Sprint 1
Le VPS héberge déjà 10+ services. Mesurer `free -h` et `docker stats` avant d'ajouter Supabase (≈ 4 Go RAM pour Postgres + GoTrue + PostgREST + Kong + Studio). Nettoyer Odoo / Metabase / Superset suspendus si saturation.

### Routing Traefik
- HTTPS partout, HTTP → HTTPS auto
- Certificats Let's Encrypt auto-renewed
- Headers sécurité (HSTS, X-Frame-Options: DENY, nosniff, CSP stricte)
- Supabase Studio sur sous-domaine avec IP whitelist
- **Aucun port exposé** hors 80/443

## 7. Secrets — Vaultwarden

### Déjà déployé
Source de vérité : `https://vaultwarden.poworkiki.cloud` (org `stack_hma`).

### Règles
- Variables Coolify récupèrent les secrets (UI Env Variables)
- `.env.local` en dev, **jamais committé** (`.gitignore` déjà en place)
- `.env.example` committé avec les clés attendues, sans valeurs
- Rotation trimestrielle : service_role Supabase, tokens Pennylane, webhooks n8n
- Inventaire : `credentials-stack-hma.md` à la racine (noms + URIs, aucun mot de passe)

## 8. Observabilité

### Stack retenue (déjà en place)
- **Logs applicatifs** → Loki (via promtail sur les containers)
- **Métriques** → Prometheus (node_exporter, postgres_exporter, n8n metrics)
- **Dashboards** → Grafana (JSON versionné dans `infra/grafana/dashboards/`)
- **Healthchecks** → Uptime Kuma

### Position tranchée sur l'error tracking
- **GlitchTip reporté V1** (mentionné CDC §5.5) — en solo dev MVP, Loki + alertes Grafana sur 5xx suffit. Ajout GlitchTip uniquement si > 3 clients.
- **Sentry / Datadog SaaS interdits** (Article 2 souveraineté).

### Contrat observabilité
- Chaque endpoint Next.js logue `{user_id, tenant_id, route, duration_ms, status}` structuré JSON
- Chaque workflow n8n envoie une notif Discord (succès ET échec)
- Alerte Grafana : 5xx > 10/min, latence p95 > 1.5s, disk > 85%, sync Pennylane > 15min

## 9. Tests

### Pyramide (Article 6 constitution)
```
    E2E (Playwright)         5 tests (parcours critiques)
    dbt tests                ~30 tests (qualité data)
    Integration (Vitest+DB)  ~50 tests (API + RLS)
    Unit (Vitest)            150+ tests (calculs)
```

### Règle non-négociable MVP
- **100% coverage sur `src/lib/calculations/*`** (formules financières)
- **1 test d'intégration RLS par rôle** (super_admin, admin, controleur, consultant)
- **3 tests minimum par mart dbt**
- **5 tests E2E** (login, morning check, drill-down, admin invite, export CSV)
- **Zéro tolérance flaky** : corriger ou supprimer immédiatement

## 10. Qualité code

- **TypeScript `strict: true`** — `any` interdit sans commentaire justificatif
- **ESLint 9 flat config** : `@typescript-eslint`, `eslint-plugin-react`, `eslint-plugin-react-hooks`, `eslint-plugin-import` avec `no-restricted-imports` pour frontières modules
- **Prettier 3** (config partagée, pas de surcharge par dev)
- **Husky pre-commit** : `lint-staged` → eslint + prettier + typecheck + test unit sur fichiers staged
- **Commit convention** : Conventional Commits en français (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`)

## 11. Alternatives rejetées (table de défense)

| Outil | Raison du rejet |
|---|---|
| Supabase Cloud | Souveraineté (Article 2) |
| Vercel | Souveraineté + coût |
| Drizzle ORM pur | Supabase SDK suffit MVP, ADR V2 si besoin |
| Prisma | Trop lourd, mauvais support RLS |
| Jest | Vitest plus rapide, ESM natif |
| Cypress | Playwright couvre multi-navigateur mieux |
| Pages Router Next.js | App Router = standard 2026 |
| Django + HTMX | Stack TS retenue pour productivité Claude Code |
| GraphQL / tRPC | REST PostgREST + Server Actions suffisent |
| Airflow | Overkill pour volume HMA, n8n suffit |
| Metabase / Superset | Pas assez customisable pour UI cliente |
| Power BI | Windows-only, licence enterprise, non souverain |
| Sentry / Datadog SaaS | Souveraineté |
| Chart.js / Nivo / Victory | Tremor couvre le besoin |
| Mui / Chakra | shadcn + Radix plus maintenu, mieux typé |
| TanStack Router | Next.js App Router déjà retenu |

## 12. Politique de versionnage & upgrade

- **Pins exacts** dans `package.json` pour : `next`, `react`, `@supabase/ssr`, `dbt-core` (image Docker)
- **Ranges `^` autorisés** pour : libs UI shadcn, utils, types
- **Renovate ou Dependabot** : reporté Sprint 7 (hardening)
- **Upgrade Major** : ADR obligatoire, branche dédiée, tests E2E complets

## 13. Revues stack

- **Trimestrielle** (Article 11.3 constitution) : audit rapide des versions + outils
- **À chaque ADR** qui touche une couche : validation cohérence globale

---

*Document vivant. Toute modification = PR avec label `stack` + ADR si changement irréversible.*
