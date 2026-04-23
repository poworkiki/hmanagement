# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# hmanagement — Contexte projet Claude Code

## État du dépôt (avril 2026)

**Feature `001-supabase-selfhost` — Phases 1→5 LIVE.**

- ✅ Spec-Kit v0.7.2 installé (`.specify/`, `.claude/skills/speckit-*/`)
- ✅ Constitution v0.2.0 dans `.specify/memory/constitution.md`
- ✅ Scaffolding infra : `infra/supabase/` (scripts + config) + `docs/runbooks/` (5 runbooks) + `docs/adr/` (ADR-001)
- ✅ **Supabase self-hosted LIVE** sur `https://supabase.hma.business` (12 containers healthy, PG 15.8, GoTrue v2.186, PostgREST 14.6)
- ✅ **Authentik OIDC delegation active** — user `hmadmin` avec TOTP MFA, login flow validé
- ✅ **Backups R2 cron actif** — quotidien 03h30 UTC + drill mensuel + disk-alert 15 min (1er backup + 1er drill OK)
- ✅ **13 secrets Vaultwarden** chiffrés dans org `stack_hma` (préfixe `supabase-selfhost-*` + `authentik-hmadmin-password` + Coolify API)
- ✅ Cold-storage papier de `RESTIC_PASSWORD` effectué
- 📍 Branche active : `001-supabase-selfhost` (12+ commits, Phase 6/7/8 restants : API smoke-test, monitoring Uptime Kuma, polish + PR main)
- 📍 Prochaine feature : `002-schemas-rls-bootstrap` (schémas `raw/staging/marts/app` + RLS policies + rôles DB + `app.tenants/profiles/audit_log`)

**NON encore présent** dans le repo : `package.json` (Next.js), `dbt_project.yml`, `supabase/` (CLI), `e2e/`. Ces arrivent avec features 003+ (app), 004+ (pipelines), 005+ (dbt marts).

## Projet
**hmanagement** — Dashboard financier DAF/CFO pour le groupe HMA (holding familiale en Guyane française), avec stratégie de pivot vers SaaS multi-tenant pour PME ultra-marines.

Activités HMA : holding, transport, agriculture, agroalimentaire.
Porteur : Kiki (Gabi Raviki) — POWOR_BUSINESS / Gabinvest.

**Nom repo Git** : `hmanagement`
**Nom MVP** : `hmanagement` (même nom, pas de fork)
**Stratégie** : architecture multi-tenant-ready, déploiement mono-tenant en MVP.

## Stack technique (NON NÉGOCIABLE sans revue d'architecture)
- **Framework** : Next.js 15 App Router + TypeScript strict
- **UI** : shadcn/ui + Tremor + Tailwind CSS v4
- **Data** : TanStack Query + TanStack Table + React Hook Form + Zod
- **Backend** : Supabase self-hosted (PostgreSQL + Auth + API REST auto)
- **Transformations** : dbt Core
- **Orchestration** : n8n (workflows Pennylane)
- **Hébergement** : VPS Hostinger + Coolify + Traefik
- **Tests** : Vitest + Testing Library + happy-dom + Playwright
- **Qualité** : ESLint + Prettier + Husky + lint-staged
- **Méthodologie** : GitHub Spec Kit (SDD)

## Architecture data (ELT, 4 schémas PostgreSQL)
```
raw.*       → données Pennylane brutes (JSONB)
staging.*   → nettoyage dbt (1 modèle = 1 source)
marts.*     → vues analytiques finales (CR, CRD, SIG)
app.*       → tables applicatives (tenants, profiles, entites, audit_log, budgets)
```

## Scope MVP strict (compte de résultat uniquement)
**Modules inclus** : CR standard PCG, CRD, SIG, KPI home (4 cartes), UI admin, import budget CSV, export CSV.
**Exclus MVP** : bilan, ratios, trésorerie, forecast, IA, multi-devises, import FEC, multi-tenant actif.

## Contraintes (MUST / MUST NOT / NEVER)

### Code
- **MUST** utiliser TypeScript mode strict (pas de `any` sans commentaire justificatif)
- **MUST** nommer les fichiers et dossiers en anglais (code) mais colonnes DB en français
- **MUST** préférer Server Components par défaut, Client Components uniquement si interactivité
- **MUST NOT** utiliser `useState` ou `useEffect` avant d'avoir essayé une approche serveur
- **NEVER** exposer de secrets en clair (utiliser `.env.local` + Vaultwarden)

### Tests (NON NÉGOCIABLE — bloquants MVP)
- **MUST** atteindre 100% de couverture sur les fonctions de calculs financiers
- **MUST** écrire les tests PENDANT le dev, pas après (TDD encouragé)
- **MUST** avoir au moins 1 test d'intégration RLS par rôle
- **MUST** avoir au moins 3 tests dbt par mart (not_null, relationships, règle métier)
- **MUST** avoir 5 tests E2E pour les parcours critiques
- **NEVER** tolérer un test flaky (corriger ou supprimer immédiatement)
- **NEVER** tester l'implémentation, toujours le comportement

### Sécurité (CRITIQUE — données financières HMA)
- **MUST** activer RLS sur toutes les tables `marts.*` et `app.*`
- **MUST** vérifier les permissions côté DB (RLS), pas seulement frontend
- **MUST** exiger MFA TOTP pour les rôles `super_admin` et `admin`
- **NEVER** stocker les rôles dans `user_metadata` Supabase (modifiable par user)
- **NEVER** committer un fichier `.env.local` ou `.env.production`

### Base de données
- **MUST** utiliser les schémas dédiés (`raw`, `staging`, `marts`, `app`)
- **MUST** avoir `tenant_id NOT NULL` sur toute table `app.*` et `marts.*`
- **MUST** documenter chaque mart dans un fichier `_marts.yml` dbt
- **MUST** tester chaque mart (not_null, relationships, règles métier)
- **NEVER** faire de `SELECT *` dans un mart (explicite les colonnes)
- **NEVER** faire de jointure sans `ON` explicite
- **NEVER** accéder directement aux schémas `raw` ou `staging` depuis Next.js

### Conventions de nommage dbt
- Staging : `stg_<source>__<entité>.sql` → `stg_pennylane__invoices.sql`
- Intermediate : `int_<entité>_<transformation>.sql`
- Marts : `mart_<domaine>_<entité>.sql` → `mart_compte_resultat.sql`
- Dimensions : `dim_<entité>.sql` → `dim_entites.sql`
- Facts : `fct_<entité>.sql`

### Conventions TypeScript
- Tests : `*.test.ts` (unit) ou `*.spec.ts` (integration)
- Tests E2E : dans `e2e/*.spec.ts`
- Composants : `PascalCase.tsx`
- Hooks : `useCamelCase.ts`
- Utilitaires : `camelCase.ts`

### Git & commits
- **MUST** utiliser Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`)
- **MUST** nommer les branches : `feature/<description>`, `fix/<bug>`, `refactor/<zone>`
- **MUST** passer pre-commit hook (lint + typecheck + tests unit) avant commit
- **NEVER** committer directement sur `main` sans revue

## Rôles utilisateurs (RBAC 4 niveaux)
1. `super_admin` — Kiki (gestion users + tout accès)
2. `admin` — direction HMA, DAF (lecture consolidée + admin users)
3. `controleur` — contrôleur de gestion (R/W sur SA filiale)
4. `consultant` — lecture seule limitée (expert-comptable externe)

## Workflow de développement (Spec-Driven Development)
Pour toute nouvelle feature non triviale (> 2 jours de dev) :
1. `/speckit.specify` — décrire le QUOI
2. `/speckit.clarify` — résoudre les ambiguïtés
3. `/speckit.plan` — concevoir le COMMENT
4. `/speckit.tasks` — décomposer en tâches
5. `/speckit.analyze` — quality gate cohérence
6. `/speckit.implement` — exécution

Voir `.specify/memory/constitution.md` pour les principes non négociables.

## Infrastructure HMA (référence stable — non versionnée mais requise)

| Ressource | Adresse | Usage | Managé par |
|---|---|---|---|
| VPS Hostinger principal | `187.124.150.82` (SSH alias `hma`) | Coolify, Supabase, n8n, Authentik | Hostinger |
| VPS secondaire | `168.231.69.226` | Legacy, migration progressive | Hostinger |
| Coolify | `coolify.hma.business` | Orchestrateur Docker (admin `hmadmin`) | Coolify self-hosted |
| Traefik (reverse-proxy) | container `coolify-proxy` sur VPS | HTTPS + Let's Encrypt pour toutes les apps | livré par Coolify |
| Vaultwarden | `vaultwarden.poworkiki.cloud` | Source de vérité secrets, org `stack_hma` | self-hosted perso |
| Authentik (IdP SSO) | `auth.hma.business` — **standalone docker-compose** à `/opt/authentik/`, **hors Coolify** | Délégation OIDC pour Supabase + n8n. User live : `hmadmin` (pas `akadmin` qui est un outpost service account) | docker-compose standalone |
| n8n | `n8n.hma.business` | Orchestration workflows (Pennylane à venir) | Coolify |
| Uptime Kuma | `status.hma.business` | Monitoring disponibilité + alerte cert TLS | Coolify |
| Cloudflare | DNS zone `hma.business` + R2 bucket `hma-supabase-backups` | DNS, TLS validation, object storage chiffré restic | SaaS CF |
| Supabase (feature 001) | `supabase.hma.business` | DB + Auth + REST + Studio (12 containers) | Coolify template |

**Détail complet des secrets** : `credentials-stack-hma.md` (non commité, local à la racine) — **jamais dans git**.

## Patterns Vaultwarden — gestion des secrets

Source de vérité : `https://vaultwarden.poworkiki.cloud` org **`stack_hma`**. Tous les secrets projet sont préfixés par namespace (ex. `supabase-selfhost-*`, `authentik-hmadmin-*`).

### Automatisation (lecture + écriture chiffrée)

Le dépôt sibling **`/c/HMAGESTION_STACK/scripts/`** expose :

- `vw-crypto.py` — Python client qui gère le chiffrement côté client (password-based login → clé utilisateur → clé d'org via RSA → AES-256-CBC + HMAC), cible l'org `stack_hma` par défaut (UUID `f7bd1540-c6ed-45fb-8e8e-3ca9a9d9db23` hardcodé)
- `vw-secret.sh` — wrapper bash (lecture seule) : `get <name>`, `list [filter]`, `export <name> <VAR>`
- `vw-add.sh` — wrapper bash pour écriture non-chiffrée (⚠️ à éviter — items invisibles dans l'UI Bitwarden/Vaultwarden car pas chiffrés)

**Toujours privilégier `vw-crypto.py`** pour les écritures dans l'org partagée.

### Pattern d'orchestrateur single-session (anti rate-limit)

Vaultwarden a un rate-limit sur `/identity/connect/token` (~5 logins/30s). Un script qui fait plusieurs opérations doit **ouvrir UNE seule session** :

```python
import importlib.util
spec = importlib.util.spec_from_file_location("vw_crypto", "/c/HMAGESTION_STACK/scripts/vw-crypto.py")
vw = importlib.util.module_from_spec(spec); spec.loader.exec_module(vw)

env = vw.load_env()
session = vw.get_session(env)              # UN SEUL login
ciphers = session.fetch_ciphers(vw.ORG_ID) # UN SEUL fetch
# puis boucler sur ciphers, upserts multiples avec session.access_token
```

### Pattern zero-leak pour handoff de secrets

Quand le user doit fournir une valeur sensible (ex. un token fraichement généré dans Coolify UI) :

```
1. Créer un fichier .env hors repo : C:\Users\gabin\secret-tmp.env
2. User le remplit dans Notepad local, sauvegarde
3. Script lit le fichier (Read tool → contenu en context mais au moins user ne l'a pas collé dans le chat)
4. Script store dans Vaultwarden via vw-crypto.py
5. Script DELETE le fichier local
```

**JAMAIS** :
- Demander au user de coller un secret dans le chat (transcript persisté côté Anthropic)
- Echo le secret dans une sortie bash (tool output est loggé)
- Committer un fichier avec des valeurs secrètes (même test/dev)

### Live services ops — commandes réelles

```bash
# Supabase (déployé, live)
ssh hma 'docker ps --format "{{.Names}}" | grep supabase'      # état containers
ssh hma 'sudo /usr/local/bin/pg-backup.sh'                     # backup manuel
ssh hma 'sudo /usr/local/bin/pg-restore-drill.sh'              # drill restauration
ssh hma 'sudo tail -50 /var/log/supabase-backup.log'           # logs backup

# Vaultwarden programmatique
python3 /c/HMAGESTION_STACK/scripts/vw-crypto.py set "name" "user" "pw" "uri"
bash /c/HMAGESTION_STACK/scripts/vw-secret.sh get "secret name"
bash /c/HMAGESTION_STACK/scripts/vw-secret.sh list [filter]

# Spec-Kit (feature workflow)
/speckit-specify    # nouvelle feature
/speckit-clarify    # résoudre ambiguïtés
/speckit-plan       # plan technique (⚠️ DESTRUCTIF sur feature existante, voir doc)
/speckit-tasks      # décomposer (⚠️ DESTRUCTIF sur feature existante)
/speckit-analyze    # quality gate read-only
/speckit-implement  # exécution
/speckit-checklist  # checklist requirements quality ("unit tests for English")
```

### Aspirationnel (futures features)

```bash
npm run dev / lint / typecheck / test:*        # Next.js — feature 003+
dbt run / test / docs                          # dbt — feature 006+
supabase db diff / migration new / push        # Supabase CLI — feature 002+
```

## Pièges Coolify documentés

4 traps réels capturés dans `docs/runbooks/supabase-deploy.md` (utile pour toute future app déployée via Coolify, pas seulement Supabase) :

1. **Coolify regénère JWT/API keys** si env vars laissées vides au deploy → re-sync Vaultwarden obligatoire après
2. **Changer `POSTGRES_DB` sans wiper le volume** = containers restart-loop (permissions denied) → wipe volume + redeploy
3. **Suffix container change à chaque recreate** (`supabase-db-<random>`) → `/etc/supabase-backup/env` à mettre à jour
4. **Stop+start via API peut laisser des containers en état `Created`** → rescue manuel `docker start <name>` × N

## Style de communication attendu
- Langue : **français** pour commentaires, docs, messages commits métier
- Code : **anglais** pour noms de fichiers, fonctions, variables
- Explications Claude : français, niveau senior dev, jargon défini à la première utilisation
- Toujours mentionner les anti-patterns à éviter
- Toujours proposer les tests en même temps que le code

## Skills disponibles
Cible : `.claude/skills/` (non encore installé — le contenu de la skill `hma-context` est dans `SKILL.md` à la racine en attendant). Claude appliquera automatiquement selon le contexte :
- `hma-context` — contexte métier HMA, PCG, spécificités Guyane (Octroi de Mer, LODEOM, ZFANG), terminologie stricte, classification V/F des charges pour CRD
- `testing-strategy` — pyramide et patterns de tests hmanagement (à installer)
- Skills futures (créées au fil des besoins) : `supabase-expert`, `dbt-modeler`, `nextjs-app-router`, `shadcn-tremor`, `french-accounting`

**Déclencheurs `hma-context`** : toute mention de CRD, SIG, FRNG, BFR, PCG, bilan fonctionnel, compte de résultat différentiel, ratios financiers, Pennylane, Octroi de Mer, LODEOM, ZFANG, filiales HMA.

## Documents de référence
Actuellement tous à la racine (à déplacer vers `docs/` et `.specify/memory/` au Sprint 1) :
- Architecture complète : `CDC-v0.2-hmanagement.md` (cahier des charges consolidé, ~30 pages) → cible `docs/`
- Synthèse exécutive : `synthese-executive.md` → cible `docs/`
- Constitution Spec Kit : `constitution.md` (12 articles, principes non négociables) → cible `.specify/memory/`
- Skill métier HMA : `SKILL.md` (contexte PCG, Octroi de Mer, LODEOM, ZFANG, terminologie) → cible `.claude/skills/hma-context/SKILL.md`
- Credentials stack : `credentials-stack-hma.md` (inventaire Vaultwarden) — ne jamais committer les secrets eux-mêmes
- Référentiel comptable : `compta_analytique.md` (formules PCG — **source externe à importer**, pas encore dans le repo)

## Contacts projet
- Propriétaire produit : Kiki (super_admin)
- Cible utilisateurs MVP : 3 personnes HMA (Kiki, gérant, gestionnaire)
- Ambition commerciale : PME ultra-marines (Guyane, Antilles, Réunion)
