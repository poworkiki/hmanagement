# Roadmap Spec-Kit — hmanagement

> **Objectif** : dérouler le MVP (CR + CRD + SIG) feature par feature en suivant strictement le workflow Spec-Driven Development (SDD).
> **Source de vérité** : [`CLAUDE.md`](../CLAUDE.md) (scope MVP), [`.specify/memory/constitution.md`](../.specify/memory/constitution.md) (principes non négociables), [`docs/architecture.md`](architecture.md) (archi cible).
> **Usage** : copier-coller les prompts ci-dessous dans Claude Code, un par un, dans l'ordre.

---

## Le cycle standard (7 étapes)

Pour **toute feature > 2 jours de dev**, toujours dans cet ordre :

| # | Skill | Quand | Effet |
|---|---|---|---|
| 1 | `/speckit-specify` | Nouvelle feature | Crée `specs/NNN-slug/spec.md` (le QUOI) |
| 2 | `/speckit-clarify` | Spec rédigée | Pose 5 questions, encode réponses dans `spec.md` |
| 3 | `/speckit-plan` | Spec clarifiée | Génère `plan.md` + `research.md` + `data-model.md` + `contracts/` (le COMMENT) |
| 4 | `/speckit-tasks` | Plan OK | Décompose en tâches `T001…` dans `tasks.md` |
| 5 | `/speckit-analyze` | Tasks générées | Quality gate read-only — vérifie cohérence spec↔plan↔tasks |
| 6 | `/speckit-checklist` *(optionnel)* | Avant implement | Checklist custom sur un aspect critique (sécu, tests, perf) |
| 7 | `/speckit-implement` | Tout validé | Exécute les tâches séquentiellement avec confirmations |

**Skills annexes rares** :
- `/speckit-constitution` — modifier la constitution (version bump, nouvel article)
- `/speckit-taskstoissues` — convertir `tasks.md` en issues GitHub (utile si collaborateurs)

---

## Features MVP — ordre d'exécution recommandé

```
[001 Supabase self-hosted]  ← ✅ DONE (mergé 2026-04-23)
        ↓
[002 Schémas + RLS bootstrap]   ← prochaine
        ↓
[003 Next.js app scaffold]
        ↓
[004 Pipeline Pennylane → raw]
        ↓
[005 dbt mart Compte de Résultat]
        ↓
[006 dbt marts CRD + SIG]
        ↓
[007 UI admin (users, entités, tenants)]
        ↓
[008 Import/export budget CSV]
        ↓
[009 Home KPI (4 cartes)]
        ↓
[MVP LIVE]
```

Ordre déterminé par les dépendances : DB avant app, app avant data, data avant marts, marts avant UI finale.

---

## Feature 002 — Schémas + RLS bootstrap

**But** : créer les 4 schémas Postgres `raw/staging/marts/app`, activer RLS partout, enum 5 rôles `admin/pdg/daf/manager/userview`, 4 tables applicatives de base (tenants, entites, profiles, audit_log).

### 1. `/speckit-specify`

```
/speckit-specify Créer dans Postgres (instance Supabase self-hosted sur supabase.hma.business) les 4 schémas applicatifs : raw (données brutes JSONB), staging (dbt cleanup), marts (vues analytiques finales), app (tables applicatives). Créer l'enum app.user_role avec les 5 rôles MVP : admin (propriétaire plateforme, tout accès, cross-tenant en V2), pdg (dirigeant groupe, lecture exécutive consolidée + détail), daf (finance ops R/W budgets et imports), manager (gérant filiale scope entite_id), userview (collaborateur interne lecture seule scopée — stagiaire, assistant compta en formation, auditeur interne, exports CSV autorisés, aucune écriture, aucun accès externe en MVP). Les rôles sont stockés dans app.profiles.role (JAMAIS dans auth.users.user_metadata). Créer les tables applicatives de base : app.tenants (multi-tenant-ready), app.entites (filiales avec tenant_id et entite_id), app.profiles (utilisateurs liés à auth.users + rôle + tenant_id + entite_id optionnel pour manager/userview), app.audit_log (traçabilité immutable append-only via trigger qui bloque UPDATE/DELETE). Activer RLS sur toutes les tables app.* et marts.* avec tenant_id NOT NULL partout. Les policies RLS doivent enforcer : (1) isolation par tenant_id pour tous, (2) accès cross-entité pour admin/pdg/daf, (3) scope entite_id pour manager/userview, (4) écritures limitées à admin/daf (budgets) et manager sur sa propre entité. MFA TOTP obligatoire pour admin/pdg/daf. Fournir migrations Supabase CLI versionnées, tests d'intégration RLS par rôle (5 tests minimum, 1 par rôle via SET LOCAL role et SET LOCAL request.jwt.claim.sub), et documentation dans docs/runbooks/db-schema.md. Scope MVP mono-tenant : 1 seul tenant créé au seed (slug 'hma'), 4 entités HMA (holding, ETPA, STA, STIVMAT), mais architecture prête pour multi-tenant sans refactor.
```

### 2. `/speckit-clarify`
```
/speckit-clarify
```

### 3. `/speckit-plan`
```
/speckit-plan
```

### 4. `/speckit-tasks`
```
/speckit-tasks
```

### 5. `/speckit-analyze`
```
/speckit-analyze
```

### 6. `/speckit-checklist` (sécu RLS — critique pour cette feature)
```
/speckit-checklist Checklist sécurité RLS pour cette feature :
- RLS activée sur 100% des tables app.* et marts.*
- Chaque table app.* a tenant_id NOT NULL
- Chaque policy référence current_setting('app.current_tenant') et auth.jwt()->>'role'
- Aucun rôle applicatif stocké dans user_metadata Supabase (tout dans app.profiles.role)
- Test d'intégration par rôle (admin, pdg, daf, manager, userview — 1 test minimum par rôle)
- Grants minimaux : anon ne peut RIEN écrire, authenticated passe par app.profiles
- Audit log écrit via trigger, jamais depuis le code app (tamper-proof)
```

### 7. `/speckit-implement`
```
/speckit-implement
```

---

## Feature 003 — Next.js app scaffold

**But** : initialiser le projet Next.js 15 App Router avec shadcn/ui + Tremor + TanStack + tests Vitest/Playwright. Layout drill-down 3 niveaux. Auth Supabase côté client.

### `/speckit-specify`

```
/speckit-specify Initialiser l'application Next.js 15 App Router avec TypeScript mode strict, Tailwind CSS v4, shadcn/ui et Tremor pour les composants, TanStack Query v5 pour le data fetching, TanStack Table v8 pour les tables, React Hook Form + Zod pour les formulaires. Intégrer Supabase SSR (@supabase/ssr) pour l'auth côté client avec OIDC Authentik déjà configuré. Structure App Router : route group (admin) pour pages admin, (app) pour dashboard métier, layout drill-down 3 niveaux (groupe HMA → entité filiale → détail transaction). Server Components par défaut, Client Components uniquement où interactivité requise. Configurer Vitest + Testing Library + happy-dom pour unit/integration, Playwright pour E2E (5 parcours critiques min). ESLint + Prettier + Husky + lint-staged avec pre-commit hook (lint + typecheck + tests unit). Générer les types TypeScript depuis Supabase (supabase gen types typescript). Scope : pas encore de logique métier, juste le scaffold + layouts + login/logout fonctionnel + 1 page dashboard vide + 1 page admin vide.
```

Puis `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` → `/speckit-analyze` → `/speckit-implement`.

**Checklist bonus** avant implement :
```
/speckit-checklist Checklist Next.js best practices :
- Server Components par défaut, Client Components justifiés par interactivité
- Pas de useState/useEffect sans tentative serveur préalable
- Auth vérifiée côté serveur via middleware + côté DB via RLS (defense in depth)
- Types TypeScript stricts, zéro any non justifié
- Couverture tests 100% sur les fonctions financières (quand elles arriveront)
- 5 tests E2E minimum : login, logout, navigation drill-down, page admin, page dashboard
```

---

## Feature 004 — Pipeline Pennylane → raw

**But** : ingestion quotidienne automatisée des données Pennylane (factures, écritures, comptes) vers `raw.*` via n8n.

### `/speckit-specify`

```
/speckit-specify Mettre en place le pipeline ELT Pennylane → raw via n8n (instance n8n.hma.business déjà active). Workflow quotidien qui pull depuis Pennylane API v2 les entités principales : invoices, journal entries, accounts plan, entités (filiales HMA, ETPA, STA, STIVMAT). Les données sont écrites brutes en JSONB dans raw.pennylane_invoices, raw.pennylane_journal_entries, raw.pennylane_accounts, raw.pennylane_entities avec colonnes : id_externe (PK), tenant_id, entite_id, payload JSONB, ingested_at timestamptz, source (constante "pennylane"). Idempotent sur id_externe (ON CONFLICT DO UPDATE). Observable : log dans app.audit_log (action, count, duration) + alerte Telegram en cas d'échec > 3 retries. Scope : 4 tokens API Pennylane dans Vaultwarden (HMA, ETPA, STA, STIVMAT déjà stockés), rate-limit Pennylane respecté (60 req/min max). Workflow n8n versionné en JSON dans infra/n8n/workflows/pennylane-daily-sync.json pour rejouer. Runbook de supervision dans docs/runbooks/pennylane-pipeline.md.
```

---

## Feature 005 — dbt mart Compte de Résultat

**But** : premier mart dbt `marts.mart_compte_resultat` consommable par le frontend. Structure PCG.

### `/speckit-specify`

```
/speckit-specify Initialiser dbt Core dans le repo et livrer le premier mart analytique : marts.mart_compte_resultat. Respecter la structure dbt standard : staging/stg_pennylane__*.sql (1 modèle par source raw), intermediate/int_*.sql si transformations partagées, marts/mart_compte_resultat.sql. Appliquer le référentiel PCG français du document compta_analytique.md pour construire un CR conforme : ventes, production stockée, subventions, consommations externes, valeur ajoutée, charges de personnel, EBE, dotations amortissements, résultat d'exploitation, charges/produits financiers, résultat courant, charges/produits exceptionnels, IS, résultat net. Périodicité mensuelle ET annuelle, vision par entité ET consolidé groupe. Chaque ligne comporte : tenant_id, entite_id, periode (YYYY-MM), compte_niveau_1, compte_niveau_2, libelle, montant. RLS active sur le mart (tenant_id + rôle DB). Tests dbt minimum par mart : 3 (not_null sur tenant_id/entite_id/periode, relationships sur entite_id vers app.entites, règle métier vérifiant résultat_net = somme des sous-totaux). Doc dans _marts.yml (description + colonnes). Couverture tests unitaires 100% sur toute fonction SQL custom (via dbt test).
```

---

## Feature 006 — dbt marts CRD + SIG

**But** : 2 marts additionnels complétant le CR — Compte de Résultat Différentiel (V/F) et Soldes Intermédiaires de Gestion.

### `/speckit-specify`

```
/speckit-specify Livrer 2 marts dbt additionnels construits sur mart_compte_resultat : marts.mart_crd (Compte de Résultat Différentiel avec classification variable/fixe des charges pour calcul seuil de rentabilité et marge sur coûts variables) et marts.mart_sig (Soldes Intermédiaires de Gestion PCG : marge commerciale, production de l'exercice, valeur ajoutée, EBE, résultat d'exploitation, résultat courant avant impôts, résultat exceptionnel, résultat net). Utiliser le référentiel compta_analytique.md sections 1 (SIG) et 5 (CRD). Classification V/F des charges définie en table de mapping dans app.ref_charges_classification (seedée au déploiement, éditable via UI admin plus tard). Chaque mart comporte : tenant_id, entite_id, periode, sections hiérarchiques, montant, taux de marge le cas échéant. Tests dbt minimum 3 par mart. Ces marts sont les briques du drill-down 3 niveaux côté UI : niveau 1 = groupe consolidé, niveau 2 = entité, niveau 3 = détail ligne (lien vers raw.pennylane_* pour voir les transactions).
```

---

## Feature 007 — UI admin (users, entités, tenants)

**But** : page admin pour gérer les comptes utilisateurs, les entités filiales, les tenants. Accessible uniquement au rôle `admin`.

### `/speckit-specify`

```
/speckit-specify Développer la zone /admin de l'application Next.js, accessible uniquement au rôle `admin` (vérifié middleware + RLS côté DB). 3 pages : /admin/users (CRUD profiles : invite user via Authentik, éditer rôle dans l'enum app.user_role, désactiver, lier à entité pour manager/userview), /admin/entites (CRUD app.entites avec code SIREN, nom, type d'activité, lien Pennylane, tenant_id), /admin/tenants (CRUD app.tenants en prévision du multi-tenant futur, masqué en MVP si un seul tenant). Utiliser TanStack Table v8 pour les listes avec tri/filtrage/pagination, React Hook Form + Zod pour les formulaires, shadcn/ui pour les composants de base. Invitations users via Authentik OIDC (API admin Authentik) — pas de Magic Link local car l'auth est déléguée. Audit log automatique de toute action admin (trigger DB sur app.profiles, app.entites, app.tenants). Tests E2E Playwright couvrant les 3 parcours CRUD + tests de refus d'accès pour chacun des 4 autres rôles (pdg, daf, manager, userview).
```

---

## Feature 008 — Import/export budget CSV

**But** : permettre au contrôleur de gestion d'importer un budget annuel prévisionnel par entité/compte en CSV, et d'exporter le CR/CRD/SIG en CSV pour Excel.

### `/speckit-specify`

```
/speckit-specify Fonctionnalité d'import/export CSV pour les contrôleurs de gestion. Import : page /app/budget/import qui accepte un CSV au format entite_id,compte_niveau_2,periode_YYYY-MM,montant_prevu. Validation Zod côté client + re-validation serveur (RLS enforce tenant_id). Écrit dans app.budgets (PK composite entite_id+compte+periode, tenant_id NOT NULL). Preview des 10 premières lignes avant confirm, rollback transactionnel si erreur. Export : bouton sur chaque page CR/CRD/SIG qui génère un CSV avec les colonnes affichées + filtres appliqués (période, entité). Nommage fichier : hma_cr_2026-01_consolide.csv. Audit log sur import (qui, quand, combien de lignes, rollback ou success). Tests unit sur le parser CSV (coverage 100% sur la fonction de parsing), tests E2E Playwright sur le parcours import + export.
```

---

## Feature 009 — Home KPI (4 cartes)

**But** : page d'accueil dashboard avec 4 cartes KPI agrégées groupe. Dernière feature MVP.

### `/speckit-specify`

```
/speckit-specify Page d'accueil /app (home dashboard) avec 4 cartes KPI agrégées niveau groupe HMA pour la période courante (mois en cours, comparé au mois précédent et à N-1 même mois). Les 4 cartes : (1) Chiffre d'affaires consolidé avec évolution M-1 et N-1, (2) EBE consolidé avec taux d'EBE et évolution, (3) Résultat net consolidé avec évolution, (4) Trésorerie disponible agrégée si disponible dans les données Pennylane sinon carte "Charges de personnel" à la place. Chaque carte : valeur principale, delta M-1 coloré (vert/rouge), delta N-1, petit sparkline sur 6 derniers mois via Tremor. Clic sur carte = drill-down niveau 2 (par entité). Données consommées via TanStack Query depuis les vues marts.mart_sig (pour CA, EBE, RN) et marts.mart_compte_resultat. RLS côté DB garantit que chaque user ne voit que ses entités. Tests E2E : affichage correct avec données de seed, refresh après update marts, accessibilité (ARIA labels sur sparklines).
```

---

## Cheat-sheet — ordre strict à suivre par feature

```
1. /speckit-specify  <prompt détaillé>
2. /speckit-clarify                        # ← réponds aux 5 questions
3. /speckit-plan
4. /speckit-tasks
5. /speckit-analyze                        # ← read-only quality gate
6. /speckit-checklist <focus critique>     # ← optionnel mais recommandé
7. /speckit-implement                      # ← exécution réelle
```

À chaque feature terminée :
- Merge PR vers `main`
- Update `CLAUDE.md` § "État du dépôt"
- Mettre à jour ce roadmap si scope évolue

---

## Anti-patterns à éviter

❌ Lancer `/speckit-plan` sans avoir fait `/speckit-clarify` → plan basé sur du vague.
❌ Re-lancer `/speckit-plan` ou `/speckit-tasks` sur une feature existante → destructif, écrase.
❌ Skip `/speckit-analyze` → on découvre les incohérences tard pendant implement.
❌ Lancer plusieurs features en parallèle → Spec-Kit suppose une feature active à la fois.
❌ Écrire le code à la main sans passer par `/speckit-implement` → perte de traçabilité Spec-Kit.

---

*Dernière mise à jour : 2026-04-23 — après merge PR #1 (feature 001 Supabase LIVE).*
