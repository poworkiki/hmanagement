---
name: project-structure
description: Structure et conventions du projet hmanagement — organisation monorepo Next.js, features, tests, dbt, docs, ADR, .claude/, nommage fichiers. Trigger pour toute question « où je mets X ? », nommage, découpage fichiers/dossiers, organisation des tests, ou structure globale du repo.
---

# Project structure — hmanagement

## Arborescence cible (fin Sprint 1)

```
hmanagement/
├── CLAUDE.md                       contexte Claude Code (racine)
├── README.md
├── package.json                    Next.js + deps
├── tsconfig.json                   "strict": true obligatoire
├── vitest.config.ts
├── playwright.config.ts
├── next.config.ts
├── .env.local                      NON committé (gitignored)
├── .env.example                    template committé (clés sans valeurs)
│
├── .claude/
│   ├── settings.json               permissions, hooks
│   └── skills/
│       ├── hma-context/SKILL.md
│       ├── testing-strategy/SKILL.md
│       ├── backend-senior/SKILL.md
│       ├── frontend-senior/SKILL.md
│       ├── architecture-senior/SKILL.md
│       ├── project-structure/SKILL.md
│       └── ops-senior/SKILL.md
│
├── .specify/
│   └── memory/constitution.md      principes non négociables
│
├── docs/
│   ├── CDC-v0.2-hmanagement.md
│   ├── synthese-executive.md
│   ├── compta_analytique.md        formules PCG source de vérité
│   ├── tech-debt.md                dette tracée
│   └── adr/
│       ├── 0001-monolithe-nextjs.md
│       └── 0002-supabase-self-hosted.md
│
├── supabase/
│   ├── migrations/YYYYMMDDHHMM_*.sql
│   ├── seed.sql                    tenant 'hma' + rôles + dim initiales
│   └── config.toml
│
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml                (template uniquement, .local pour perso)
│   ├── macros/cents_to_euros.sql
│   └── models/
│       ├── staging/
│       │   ├── _sources.yml
│       │   ├── _stg.yml            tests
│       │   └── stg_pennylane__*.sql
│       ├── intermediate/
│       │   └── int_*.sql
│       └── marts/
│           ├── _marts.yml          tests + doc en français
│           ├── compte_resultat/mart_cr_*.sql
│           ├── crd/mart_crd_*.sql
│           ├── sig/mart_sig_*.sql
│           └── dim/dim_*.sql
│
├── src/
│   ├── app/                        App Router
│   │   ├── (auth)/login/page.tsx
│   │   ├── (app)/
│   │   │   ├── layout.tsx          layout authentifié
│   │   │   ├── page.tsx            KPI home
│   │   │   ├── cr/[...route]
│   │   │   ├── crd/[...route]
│   │   │   ├── sig/[...route]
│   │   │   ├── budget/
│   │   │   └── admin/
│   │   ├── api/                    Route Handlers (webhook n8n, export)
│   │   └── middleware.ts           auth + session timeout
│   │
│   ├── features/                   code métier découpé par domaine
│   │   ├── compte-resultat/
│   │   │   ├── components/
│   │   │   ├── server/queries.ts   lectures mart (Server only)
│   │   │   ├── server/actions.ts   Server Actions
│   │   │   ├── schemas.ts          Zod
│   │   │   ├── types.ts
│   │   │   └── __tests__/
│   │   ├── crd/
│   │   ├── sig/
│   │   ├── admin/
│   │   ├── budget/
│   │   └── kpi-home/
│   │
│   ├── components/                 UI générique (wrappers shadcn/tremor)
│   │   ├── ui/                     shadcn generated
│   │   └── charts/                 wrappers Tremor projet
│   │
│   └── lib/
│       ├── supabase/{server,client,service}.ts
│       ├── auth/{requireUser,requireRole}.ts
│       ├── formatters/{euros,dates,periodes}.ts
│       ├── calculations/           fonctions financières pures (100% testées)
│       │   ├── sig.ts
│       │   ├── crd.ts
│       │   └── __tests__/
│       └── zod/                    schemas partagés
│
├── e2e/
│   ├── login.spec.ts
│   ├── morning-check.spec.ts
│   ├── drill-down.spec.ts
│   ├── admin-invite.spec.ts
│   └── export-csv.spec.ts
│
└── .github/workflows/
    ├── ci.yml                      lint + typecheck + test + dbt
    └── e2e.yml                     Playwright on PR
```

## Conventions de nommage (consolidées)

| Élément | Convention | Exemple |
|---|---|---|
| Fichier composant | `PascalCase.tsx` | `RubriqueRow.tsx` |
| Hook | `useCamelCase.ts` | `usePeriode.ts` |
| Utilitaire / fn pure | `camelCase.ts` | `formatEuros.ts` |
| Test unit | `*.test.ts(x)` | `sig.test.ts` |
| Test intégration | `*.spec.ts` | `rls.spec.ts` |
| Test E2E | `e2e/*.spec.ts` | `e2e/login.spec.ts` |
| Route App Router | `kebab-case/` | `compte-resultat/` |
| Table / colonne DB | `snake_case` **français** | `chiffre_affaires_ht` |
| Schéma DB | lowercase court | `app`, `marts` |
| Mart dbt | `mart_<domaine>_<entité>.sql` | `mart_cr_rubriques.sql` |
| Staging dbt | `stg_<source>__<entité>.sql` | `stg_pennylane__invoices.sql` |
| Intermediate dbt | `int_<entité>_<transformation>.sql` | `int_ecritures_classifiees.sql` |
| Dimension dbt | `dim_<entité>.sql` | `dim_entites.sql` |
| Migration | `YYYYMMDDHHMM_<verb>_<objet>.sql` | `202604211430_create_audit_log.sql` |
| ADR | `NNNN-titre-kebab.md` | `0003-rbac-profiles-role.md` |
| Branche Git | `feature/*` `fix/*` `refactor/*` `docs/*` `chore/*` | `feature/crd-drill-down` |
| Commit | Conventional Commits FR | `feat(crd): ajoute calcul seuil rentabilité` |

## Où placer quoi — règles de décision

**Nouveau composant UI** :
- Réutilisé ≥ 2 features → `src/components/` (ou `components/charts/` si Tremor)
- Spécifique à une feature → `src/features/<feature>/components/`
- Règle de 3 : ne promouvoir vers `components/` qu'à la **3e occurrence**

**Nouveau calcul financier** :
- Logique conditionnelle, dépend d'entrées utilisateur → `src/lib/calculations/` + 100% coverage
- Pur agrégat SQL sur marts → mart ou macro dbt
- **Jamais les deux** (une seule source de vérité)

**Nouveau schema Zod** :
- Utilisé côté serveur + client (formulaires) → `src/features/<f>/schemas.ts`
- Utilisé partout (ex: `tenantIdSchema`) → `src/lib/zod/`

**Nouveau query Supabase** :
- Lecture mart → `src/features/<f>/server/queries.ts` (Server only, `import 'server-only'` en tête)
- Mutation → `src/features/<f>/server/actions.ts` avec `'use server'`

**Nouveau test** :
- Fonction pure → à côté du fichier : `formatEuros.ts` + `formatEuros.test.ts`
- Intégration DB/RLS → `src/features/<f>/__tests__/*.spec.ts` avec Supabase test container
- E2E user journey → `e2e/*.spec.ts`

**Nouveau document** :
- Décision irréversible → `docs/adr/NNNN-*.md`
- Dette connue → ligne dans `docs/tech-debt.md` (pas de fichier par dette)
- Spec feature SDD → `specs/<feature>/` (géré par Spec Kit)

## Règles d'import (architecturales)

1. `features/<A>` **ne peut jamais** importer de `features/<B>` — tout partage passe par `lib/`
2. `lib/` **ne peut jamais** importer de `features/*`
3. `components/` **ne peut jamais** importer de `features/*` ni de `lib/supabase/service`
4. Un fichier `server/*` ne doit **jamais** être importé par un Client Component (guard avec `import 'server-only'`)
5. Les types TS générés par Supabase vivent dans `src/lib/database.types.ts` — regénérer via `supabase gen types typescript`

Valider ces règles avec ESLint `no-restricted-imports` dans `.eslintrc`.

## Barils (`index.ts`) — limités
Autorisés pour : `src/components/ui/` (shadcn), `src/lib/formatters/`. Interdits ailleurs (alourdit le tree-shaking et masque les dépendances circulaires).

## .gitignore essentiels
```
.env.local
.env.*.local
node_modules/
.next/
dbt/target/
dbt/dbt_packages/
dbt/logs/
dbt/profiles.local.yml
playwright-report/
test-results/
coverage/
*.tsbuildinfo
```

## Anti-patterns structure
- ❌ Dossier `utils/` fourre-tout (préférer `lib/formatters/`, `lib/calculations/`, etc.)
- ❌ Composant « Dumb » dans `features/` réutilisé ailleurs sans promotion
- ❌ Migration SQL sans timestamp (ordre d'exécution cassé)
- ❌ Fichier `.env` committé (même sans secrets — utiliser `.env.example`)
- ❌ Code mort laissé « au cas où » (supprimer, Git garde l'historique)
- ❌ Un mart dbt sans entrée dans `_marts.yml`
- ❌ Nommer un mart `mart_revenue.sql` (anglais) au lieu de `mart_chiffre_affaires.sql` — colonnes/marts en français
