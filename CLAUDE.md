# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# hmanagement — Contexte projet Claude Code

## État du dépôt (Sprint 0)
À ce jour, le repo ne contient **que des documents de cadrage à la racine** : `CLAUDE.md`, `README.md`, `constitution.md`, `SKILL.md` (contenu de la skill `hma-context`), `CDC-v0.2-hmanagement.md`, `synthese-executive.md`, `credentials-stack-hma.md`. **Aucun code applicatif, aucun `package.json`, aucun `dbt_project.yml`, aucun répertoire `supabase/` n'existe encore.** Les commandes ci-dessous (npm, dbt, supabase) et la structure `.claude/skills/`, `.specify/memory/`, `docs/` sont l'**état cible** prévu pour la fin de Sprint 0 / début Sprint 1 — pas à exécuter tant que le scaffolding n'est pas en place.

Le prochain travail concret attendu est l'installation de Supabase self-hosted sur Coolify, via le workflow Spec Kit (voir `README.md` section « Sprint 1 à suivre »).

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

## Commandes projet courantes
> ⚠️ **Aspirationnel pour l'instant** — ces commandes ne fonctionneront qu'après le scaffolding Sprint 1 (Next.js init, `supabase init`, `dbt init`). Ne pas les lancer sur le repo en l'état.

```bash
# Développement local
npm run dev                                    # Next.js en local
npm run lint                                   # ESLint
npm run typecheck                              # TypeScript
npm run test:unit                              # Vitest unitaires
npm run test:integration                       # Vitest intégration
npm run test:e2e                               # Playwright E2E

# dbt (dans le container)
dbt run --select state:modified+               # run modèles modifiés
dbt test --select state:modified+              # tests modèles modifiés
dbt docs generate && dbt docs serve            # documentation

# Supabase self-hosted
supabase db diff                               # diff migrations
supabase migration new <nom>                   # nouvelle migration
supabase db push                               # appliquer migrations

# Spec Kit
/speckit.constitution                          # voir/éditer constitution
/speckit.specify                               # nouvelle spec feature
```

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
