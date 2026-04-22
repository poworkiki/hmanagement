# Constitution hmanagement

## Préambule

Ce document définit les **principes non négociables** du projet hmanagement.
Toute décision technique et tout développement doivent s'y conformer.
Pour dévier d'un principe, une revue d'architecture formelle est requise
(discussion explicite + mise à jour de ce document + commit dédié).

Dernière révision : Sprint 0 — avril 2026 — v0.2

---

## Article 1 — Mission du projet

hmanagement fournit un dashboard financier de niveau DAF/CFO, self-hosté, souverain et sécurisé, permettant :
- Consultation consolidée groupe et par filiale
- Analyse d'activité (SIG, CRD)
- Analyse de structure financière (bilan, FRNG, BFR — V1)
- Suivi des ratios financiers (V1)
- Contrôles de cohérence automatiques

**MVP** : livré à HMA (mono-tenant) avec compte de résultat uniquement.
**V2+** : ouverture multi-tenant SaaS pour PME ultra-marines.

## Article 2 — Souveraineté des données

**NON NÉGOCIABLE** : toutes les données financières sont hébergées sur infrastructure sous contrôle (VPS Hostinger via Coolify).

- Aucune donnée ne transite par un SaaS américain non conforme RGPD
- Les sauvegardes sont chiffrées et stockées en contrôle
- Les secrets sont gérés via Vaultwarden (self-hosted)

## Article 3 — Architecture

### 3.1 — Paradigme ELT (Extract, Load, Transform)
Les données brutes sont **conservées** dans `raw.*`. Les transformations s'effectuent à l'intérieur de PostgreSQL via dbt, non pas avant chargement.

### 3.2 — Architecture multi-tenant-ready, MVP mono-tenant
Toutes les tables ont `tenant_id` dès le MVP, RLS activée dès le Sprint 1. Le code est **identique** en mono-tenant et multi-tenant.

### 3.3 — Monolithe structuré (Majestic Monolith)
L'architecture privilégie la simplicité : un monolithe Next.js bien structuré, une couche data Supabase + dbt.

### 3.4 — Stack technique figée (sans revue)
- Frontend : Next.js 15 App Router + TypeScript strict
- UI : shadcn/ui + Tremor
- Backend : Supabase self-hosted
- Data : PostgreSQL + dbt
- Orchestration : n8n

### 3.5 — 4 schémas PostgreSQL strictement séparés
```
raw.*       : données brutes (lecture écriture : n8n uniquement)
staging.*   : nettoyage (lecture écriture : dbt uniquement)
marts.*     : vues analytiques (lecture : app, écriture : dbt)
app.*       : données applicatives (lecture écriture : app)
```

## Article 4 — Sécurité (CRITIQUE)

### 4.1 — Principe du moindre privilège
Chaque utilisateur reçoit le **minimum** de permissions nécessaires à sa fonction.
Nouvel utilisateur créé = inactif + rôle minimal par défaut.

### 4.2 — Row-Level Security obligatoire
**MUST** : toutes les tables `marts.*` et `app.*` ont des policies RLS actives.
Les vérifications de permissions côté frontend ne suffisent **jamais**.

### 4.3 — Authentification forte
- Magic Link email pour tous les utilisateurs
- MFA TOTP **obligatoire** pour `super_admin` et `admin`
- Session timeout : maximum 8 heures utilisateur, 1 heure admin
- Vérification contre les mots de passe compromis activée

### 4.4 — Audit trail
Toutes les actions sensibles (lecture de données consolidées, modification d'utilisateurs, export) sont enregistrées dans `app.audit_log`.
L'audit log est **immuable** (pas d'UPDATE, pas de DELETE — trigger blocker).

### 4.5 — Secrets
**NEVER** : secret en clair dans le code ou en dur.
**NEVER** : committer `.env.local`, `.env.production`, clés API.
**MUST** : tout secret vit dans Vaultwarden ou variables d'environnement Coolify.

## Article 5 — Qualité de code

### 5.1 — TypeScript strict sans exception
`"strict": true` dans `tsconfig.json`. Le type `any` est **interdit** sauf cas exceptionnel documenté par un commentaire.

### 5.2 — Tests obligatoires (NON NÉGOCIABLE)
Voir Article 6 pour le détail complet de la stratégie de tests.

**Règles minimales** :
- 100% couverture sur les fonctions de calculs financiers
- Tests d'intégration RLS pour chaque rôle
- Au moins 3 tests dbt par mart
- 5 tests E2E minimum pour parcours critiques

### 5.3 — Revue avant merge
Aucun commit direct sur `main`. Toute modification passe par :
- Branche `feature/*`, `fix/*`, ou `refactor/*`
- Pre-commit hook (lint + typecheck + tests unitaires)
- Relecture humaine (auto-review en mode review) avant merge

### 5.4 — Documentation
- Chaque mart dbt **MUST** avoir une description métier en français
- Chaque colonne **MUST** être documentée
- Chaque décision architecturale majeure **MUST** créer un ADR dans `docs/adr/`

---

## Article 6 — Stratégie de tests (RENFORCÉ)

### 6.1 — Principe directeur
Les tests sont écrits **PENDANT** le développement, jamais après. Ils sont **bloquants** pour la livraison MVP.

### 6.2 — Pyramide de tests hmanagement
- **70% tests unitaires** (Vitest) — fonctions pures, calculs
- **20% tests d'intégration** (Vitest + DB test) — API + RLS
- **7% tests dbt** — qualité de données
- **3% tests E2E** (Playwright) — parcours critiques uniquement

### 6.3 — Tests bloquants MVP (par catégorie)

**Catégorie A — Calculs financiers** : **100% couverture**
- Toutes les formules SIG (9 soldes)
- Toutes les formules CRD (MCV, seuil, levier, point mort, marge sécurité)
- Conversion centimes → euros Pennylane
- Variations vs N-1, cumuls YTD

**Catégorie B — Sécurité (intégration)**
- RLS isole par filiale (testé pour chaque rôle)
- RLS isole par rôle (consultant ne modifie pas)
- Session expirée → redirection login
- `user_metadata` jamais utilisé pour permissions

**Catégorie C — Data quality (dbt)**
- Chaque mart a `not_null` sur PK
- `relationships` vers dimensions
- Règles métier : CA ≥ 0, cohérence débits/crédits
- Fraîcheur données (< 24h après sync)

**Catégorie D — E2E (Playwright)**
- Login Magic Link end-to-end
- Morning check gérant (< 30 secondes)
- Drill-down 3 niveaux CRD
- Admin invite un nouvel utilisateur
- Export CSV d'un tableau

### 6.4 — TDD encouragé
Pour les fonctions de calcul financier critiques : écrire les tests **AVANT** l'implémentation (Red → Green → Refactor).

### 6.5 — Anti-patterns tests (interdits)
- ❌ Tester l'implémentation (ex: `expect(useState).toHaveBeenCalled()`)
- ❌ Tolérer un flaky test (correction immédiate ou suppression)
- ❌ 100% couverture fictive (tests qui n'assertent rien de pertinent)
- ❌ Mocks partout (préférer tests avec vraie DB de test)
- ❌ Tests qui dépendent de l'ordre d'exécution
- ❌ Assertions molles (`toBeTruthy()` au lieu de valeur exacte)

### 6.6 — Workflow tests dans CI
Pipeline GitHub Actions bloquant :
1. Lint + typecheck
2. Tests unitaires
3. Tests d'intégration
4. Tests dbt (sur changement de modèles)
5. Tests E2E (sur PR uniquement)

**Aucun merge sur `main` si un test échoue.**

---

## Article 7 — Principes de conception

### 7.1 — KISS (Keep It Simple, Stupid)
Privilégier la solution simple qui marche à la solution élégante qui complique.
Complexité ajoutée = dette technique.

### 7.2 — YAGNI (You Ain't Gonna Need It)
N'ajouter ni couche ni dépendance "au cas où". Chaque ajout doit résoudre un problème actuel et concret, pas hypothétique.

### 7.3 — DRY (Don't Repeat Yourself) — avec modération
Factoriser la logique partagée, mais pas à l'extrême. Une duplication ponctuelle vaut mieux qu'une abstraction mal pensée.

### 7.4 — Séparation des responsabilités
Chaque couche, module, fonction fait **une seule chose** et la fait bien.
Signal d'alerte : si tu ne peux pas résumer un module en une phrase, il fait trop de choses.

### 7.5 — Décisions réversibles vs irréversibles
- Décisions réversibles : prendre vite, itérer
- Décisions irréversibles (schéma DB, stack majeure) : prendre lentement, documenter dans ADR

## Article 8 — Workflow Spec-Driven Development

### 8.1 — Gateway SDD pour features non triviales
Toute nouvelle feature de plus de 2 jours de dev **MUST** passer par :
1. `/speckit.specify` (QUOI)
2. `/speckit.clarify` (ambiguïtés)
3. `/speckit.plan` (COMMENT)
4. `/speckit.tasks` (décomposition)
5. `/speckit.analyze` (quality gate)
6. `/speckit.implement` (exécution)

### 8.2 — Features triviales
Corrections de bugs, renommages, ajustements UI mineurs peuvent être traités directement sans cycle SDD complet.

## Article 9 — Multi-tenancy

### 9.1 — Architecture-ready dès MVP
Toutes les tables portent `tenant_id`. RLS active. Un seul tenant `hma` en MVP.

### 9.2 — Isolation stricte
**Test automatique obligatoire** : "user tenant A ne voit jamais tenant B".
Rôle DB applicatif sans `BYPASSRLS`.

### 9.3 — Pivot vers multi-tenant réel (V2)
Aucun refactoring majeur nécessaire : activation via configuration.

## Article 10 — Observabilité & opérations

### 10.1 — Tout pipeline a une notification
Chaque workflow n8n **MUST** envoyer une notification de fin (Discord / Slack) en cas de succès ET d'échec.

### 10.2 — Monitoring
Métriques pipeline (durée, lignes traitées, tests passés) visualisées via Grafana.

### 10.3 — Sauvegardes
PostgreSQL sauvegardé quotidiennement. Test de restauration **mensuel obligatoire**.

## Article 11 — Évolution du projet

### 11.1 — Strangler Fig Pattern
L'architecture évolue progressivement par remplacement incrémental, jamais par big bang rewrite.

### 11.2 — Dette technique
Toute dette technique connue est tracée dans `docs/tech-debt.md` avec justification et horizon de résolution.

### 11.3 — Revues d'architecture
Au moins une revue trimestrielle des décisions prises. Les ADR périmés sont marqués "Superseded" mais jamais supprimés.

### 11.4 — Scope MVP gelé
Pendant le MVP, **aucune feature hors liste MoSCoW** n'est ajoutée sans revue formelle.
Toute exception = commit ADR explicite + ajustement roadmap.

## Article 12 — North Star Metric

Le succès de hmanagement se mesure à **une métrique** :

**Temps entre clôture mensuelle Pennylane et décision métier prise par le DAF.**

- État actuel : 2 jours
- Cible MVP : **< 30 secondes**

Toute décision produit qui ne sert pas cette métrique est reportée.

---

## Signature

Ce document est la **source de vérité** des principes du projet.
Il est versionné dans Git et révisé régulièrement.
Toute modification nécessite un commit dédié de type `docs(constitution):`.

Propriétaire : Kiki — POWOR_BUSINESS
Projet : hmanagement
Version : 0.2 — Sprint 0 (avril 2026)
