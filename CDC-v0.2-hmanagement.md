# Cahier des Charges — hmanagement

> **Nom de code** : `hmanagement`
> **Version** : 0.2 (consolidé)
> **Date** : 21 avril 2026
> **Auteur** : Kiki (Gabi Raviki) — POWOR_BUSINESS / Gabinvest
> **Statut** : validé, en cours de build MVP

---

## Préambule

Ce document est la **source de vérité** de `hmanagement`. Il consolide :
- Le CDC initial v0.1 (brouillon architecte)
- Les décisions issues des sessions de cadrage (avril 2026)
- Les principes de la constitution Spec Kit
- Les patterns UX définis pour le projet
- Le référentiel comptable (`compta_analytique.md`)

Toute modification passe par un commit `docs(cdc):` avec justification.

---

## Table des matières

1. Vision & stratégie produit
2. Personas & cas d'usage
3. Périmètre MVP (HMA)
4. Roadmap V1 et V2
5. Exigences non-fonctionnelles
6. Stratégie de tests
7. Architecture cible
8. Modèle de données
9. Stratégie multi-tenant
10. Stack technique
11. Pattern UX universel
12. Stratégie de déploiement
13. Roadmap par sprints
14. Risques & mitigations
15. Estimations d'effort
16. Annexes

---

## 1. Vision & stratégie produit

### 1.1 Pitch produit

> **hmanagement transforme la comptabilité Pennylane en intelligence financière actionnable. En un clic, chaque KPI révèle la ligne comptable qui l'explique.**

### 1.2 Stratégie double : MVP HMA puis SaaS

Le projet suit une **stratégie d'architecture multi-tenant avec déploiement mono-tenant en MVP** :

- **MVP (M0-M2)** : livraison fonctionnelle pour HMA uniquement, un seul tenant actif
- **V1 (M3-M6)** : enrichissement fonctionnel chez HMA (bilan, ratios, trésorerie)
- **V2 (M6+)** : ouverture multi-tenant, onboarding d'autres PME ultra-marines

**Conséquence architecturale** : toutes les tables ont `tenant_id` dès le MVP, RLS activée dès le Sprint 1. Le code est **identique** en mono-tenant et multi-tenant. Pas de refactoring massif lors du pivot.

### 1.3 Problème résolu

Les PME multi-filiales françaises (ultra-marines en priorité) subissent :
- Pennylane produit des chiffres, **Excel croise à la main**
- Les dérives se détectent **trop tard**
- La consolidation groupe prend **2 jours/mois** manuellement
- Pas d'outil pour les **spécificités fiscales Outre-mer** (Octroi de Mer, LODEOM, ZFANG)
- Les outils BI généralistes (Power BI, Metabase) ne connaissent pas la **logique compta analytique** française

### 1.4 Proposition de valeur différenciante

1. **Drill-down 3 niveaux natif** : rubrique → sous-rubrique → compte/ligne d'écriture, sans JOIN ni SQL
2. **CRD et SIG first-class** : modules phares en MVP, directement utilisables
3. **Souveraineté totale** : self-hosted sur Coolify, données qui ne quittent pas le groupe
4. **Spécificités ultra-marines** intégrées : Octroi de Mer, LODEOM, ZFANG documentés dans la skill `french-accounting`
5. **Multi-tenant ready** : un client enterprise peut avoir son instance dédiée sans fork de code

### 1.5 North Star Metric

**Temps entre clôture mensuelle Pennylane et décision métier**
- Avant hmanagement : ~2 jours (extraction, Excel, analyse)
- Cible hmanagement : **< 30 secondes** (connexion, consultation, compréhension)

Cette métrique guide **toutes** les décisions produit. Si une feature n'améliore pas ce temps, elle est reportée.

### 1.6 Objectifs business à 18 mois

| Horizon | Objectif |
|---|---|
| M+2 | MVP fonctionnel pour HMA (CR + CRD + SIG) |
| M+6 | V1 avec bilan et ratios, 1 client pilote externe |
| M+12 | Multi-tenant activé, 3-5 clients payants |
| M+18 | 10+ clients PME ultra-marines, ARR 50-80 k€ |

### 1.7 Modèle économique cible (V2+)

- **SaaS mutualisé** : 90-250 €/mois/structure selon plan
- **Self-hosted premium** : licence annuelle 5-15 k€/an + support
- **Code identique** dans les deux modes — pas de fork, juste configuration

---

## 2. Personas & cas d'usage

### 2.1 Personas MVP (HMA — réels)

#### P1 — Kiki (Gabi Raviki), DAF HMA & porteur projet
- **Rôle système** : `super_admin`
- **Âge** : 34 ans
- **Compétences** : contrôle de gestion avancé, Python débutant, vibe coder progressant vers senior
- **Objectifs** : piloter HMA, construire et vendre hmanagement, apprendre le dev pro
- **Usage** : quotidien, développement + consultation

#### P2 — Gérant HMA
- **Rôle système** : `admin`
- **Compétences tech** : moyennes, à l'aise avec les outils pro
- **Objectifs** : vue consolidée groupe chaque matin, comités de direction, décisions rapides
- **Usage** : quotidien, consultation 5-10 minutes par jour
- **Parcours critique** : "Morning check du gérant" (< 30 secondes)

#### P3 — Gestionnaire administrative HMA
- **Rôle système** : `controleur`
- **Compétences** : compta confirmée, tech moyenne
- **Objectifs** : suivi quotidien, saisie budget, contrôles de cohérence
- **Usage** : ponctuel, centré sur une filiale

### 2.2 Personas V2 (SaaS — à acquérir)

Ces personas guident la **conception** dès le MVP pour que l'architecture les accueille en V2 :

- **Claire, DAF groupe PME** (5 structures, 40M€ CA) : cible commerciale principale
- **Marc, contrôleur de gestion** : heavy user, crée des vues partagées
- **Sophie, assistante compta** : saisie budget, vérifications ponctuelles
- **Julien, admin tenant** (DSI/dirigeant client) : gère les droits, connecte Pennylane
- **Kiki, super-admin SaaS cross-tenant** : onboarding, supervision, debug

### 2.3 Cas d'usage critiques (happy paths)

**UC1 — Morning check gérant** ⭐ (MVP)
Durée cible : < 30 secondes
1. Gérant ouvre hmanagement (session active)
2. Voit la home "Vue Groupe" avec 4 KPI (CA, Marge, Trésorerie estimée, Résultat)
3. Scan visuel : badge rouge si dérive > seuil
4. Clic sur KPI rouge → drill-down immédiat vers le module source

**UC2 — Analyse mensuelle d'une filiale** ⭐ (MVP)
Durée cible : < 5 minutes
1. Kiki sélectionne "Filiale Transport" + "Mars 2026"
2. Consulte CRD mensuel vs N-1 et vs budget
3. Drill-down sur poste en dérive (ex: charges variables)
4. Identifie les comptes 607x ou 613x qui dérivent
5. Comprend la cause en lisant la liste des écritures

**UC3 — Drill-down 3 niveaux** ⭐ (MVP)
Durée cible : < 3 clics
1. Vue niveau 1 : rubrique (ex: "Charges externes")
2. Niveau 2 : ventilation par compte (606x, 607x, 613x…)
3. Niveau 3 : liste des écritures comptables du compte

**UC4 — Consultation SIG mensuel** ⭐ (MVP)
Durée cible : < 2 minutes
1. Page SIG avec les 9 soldes en cascade
2. Chaque solde avec variation vs N-1 (BadgeDelta)
3. Comparaison multi-filiales possible

**UC5 — Export CSV pour rapport** (MVP Should)
1. Export 1 clic depuis n'importe quelle vue
2. Format Excel-ready avec en-têtes français

**UC6 — Import budget annuel** (V1)
1. Admin uploade un CSV structuré
2. Système valide, maps vers les postes
3. CRD affiche automatiquement les colonnes Budget/Écart

**UC7 — Consolidation groupe** (V1)
1. Sélection d'un "groupement" (ex: "Pôle Opérations" = Transport + Agri)
2. P&L consolidé affiché
3. Drill-down fonctionne sur l'agrégat

---

## 3. Périmètre MVP (HMA)

### 3.1 Focus strict : compte de résultat uniquement

Le MVP se concentre **exclusivement** sur les données de **classes PCG 6 et 7** (charges et produits). Les classes 1-5 (bilan) sont reportées en V1.

**Justification** :
- Complexité bilan = 4-5x supérieure (à-nouveaux, continuité exercices)
- Time to first value rapide (~2 mois vs ~4+)
- Validation métier avec utilisateurs réels avant d'investir plus

### 3.2 Must-have MVP (bloquant livraison)

Priorisation MoSCoW, taille T-shirt estimative.

| ID | User story | Taille |
|---|---|---|
| US-01 | Authentification Magic Link + MFA optionnel | M |
| US-02 | Seed des entités HMA (holding + Transport + Agri + Agroalimentaire) | S |
| US-03 | UI admin : gestion users (CRUD + rôles) | M |
| US-04 | UI admin : gestion entités HMA | S |
| US-05 | Pipeline ELT : n8n extrait Pennylane → `raw.*` PostgreSQL | L |
| US-06 | dbt : transformations `raw` → `staging` → `marts` | L |
| US-07 | Module Compte de Résultat standard (PCG) avec drill-down 3 niveaux | XL |
| US-08 | Module CRD (Compte de Résultat Différentiel) | XL |
| US-09 | Module SIG (9 soldes intermédiaires de gestion) | L |
| US-10 | Page home : 4 KPI Cards cliquables avec sparkline et delta N-1 | M |
| US-11 | Filtres temporels : mois, trimestre, année, rolling 12 | M |
| US-12 | Filtres par entité (filiale vs groupe) avec RLS | M |
| US-13 | Import budget via CSV + affichage colonnes Réel/Budget/Écart/% | M |
| US-14 | Export CSV de n'importe quel tableau | S |
| US-15 | Audit trail (append-only) des actions sensibles | M |
| US-16 | Tooltip de formule sur chaque KPI (issu du référentiel comptable) | S |

### 3.3 Should-have MVP (si temps)

| ID | User story | Taille |
|---|---|---|
| US-17 | Dashboard configurable (widgets personnalisables) | M |
| US-18 | Vues sauvegardées (filtres + colonnes) | S |
| US-19 | Commentaires sur ligne de tableau | M |
| US-20 | Colonnes réordonnables en drag & drop | M |

### 3.4 Hors scope MVP (reporté V1 ou V2)

- ❌ Bilan comptable
- ❌ Bilan fonctionnel (FRNG, BFR, Trésorerie nette)
- ❌ Les 26 ratios financiers
- ❌ Tableau de financement
- ❌ Forecast par scénario
- ❌ Consolidation groupement dynamique
- ❌ Multi-devises
- ❌ UI de saisie budget (CSV import seulement en MVP)
- ❌ Import FEC (API Pennylane uniquement en MVP)
- ❌ Élimination inter-co
- ❌ Connecteurs Sage/Cegid/EBP
- ❌ IA / RAG / copilote

### 3.5 Hors scope définitif (never)

- Saisie comptable / journal (hmanagement ne remplace PAS le logiciel comptable)
- Déclarations fiscales / liasses
- Paie
- Facturation client / achats

---

## 4. Roadmap V1 et V2

### 4.1 V1 (M+3 à M+6) — Enrichissement fonctionnel

- Module Bilan comptable
- Module Bilan fonctionnel (FRNG, BFR, TN)
- 26 ratios financiers
- Tableau de financement
- Forecast simple (scénarios par règles %)
- UI de saisie budget complète
- Consolidation groupement dynamique
- Commentaires + vues partagées

### 4.2 V2 (M+6+) — Ouverture SaaS

- Activation multi-tenant réel
- Onboarding d'autres clients PME
- Connecteurs API Sage, Cegid, EBP
- Import FEC pour flexibilité
- Élimination inter-co
- Permissions granulaires par axe analytique
- Feature flags par tenant

### 4.3 V2+ (M+12+) — IA et scaling

L'architecture doit être **IA-ready dès le MVP** (outbox pattern, schéma stable, tenant_id partout) sans coder l'IA.

Fonctionnalités IA cibles :
1. **Copilote analyse** : "Pourquoi la marge a baissé en mars ?" → agent interroge la base, propose une explication sourcée
2. **Résumé mensuel auto** : commentaire exécutif généré sur le CR du mois
3. **Détection anomalies** : écritures atypiques flaguées
4. **RAG documentaire** : upload contrats/PV, requête en langage naturel
5. **Mémoire agent** (mem0) : préférences utilisateur persistantes

**Stack IA V2** :
- Worker Python FastAPI séparé
- Qdrant self-hosted (vector store)
- LlamaIndex / LangGraph
- Driver LLM abstrait (OpenAI / Anthropic / Ollama)

---

## 5. Exigences non-fonctionnelles

### 5.1 Performance

| KPI | Cible MVP | Cible V1 |
|---|---|---|
| Time-to-first-byte home | < 800 ms (p95) | < 500 ms |
| Drill-down niveau 1 → 2 | < 1.5 s | < 800 ms |
| Drill-down niveau 2 → 3 | < 1 s paginé (100 lignes) | identique |
| Export CSV P&L | < 5 s | < 2 s |
| Sync Pennylane quotidienne | < 10 min | < 3 min |

**Leviers** :
- Tables d'agrégats dbt pré-calculés dans `marts.*`
- Index BRIN sur colonnes temporelles
- Index btree composites `(tenant_id, entite_id, compte_id, date)`
- Pagination côté serveur (niveau 3)
- Cache TanStack Query côté client
- Materialized views Postgres si besoin

### 5.2 Sécurité

- **Isolation tenant stricte** : RLS Postgres + `SET LOCAL app.tenant_id`
- **Principe du moindre privilège** : rôle DB applicatif sans `BYPASSRLS`
- **Auth** : Supabase Auth, Magic Link + MFA TOTP pour admins
- **Autorisation** : RBAC 4 rôles (`super_admin`, `admin`, `controleur`, `consultant`)
- **Audit trail** : table append-only `app.audit_log`
- **Secrets** : Vaultwarden + variables d'environnement Coolify, jamais en clair
- **Transport** : HTTPS exclusif, HSTS, CSP stricte
- **Session timeout** : 8h max pour utilisateurs, 1h pour admins

### 5.3 Conformité

- **RGPD** : hébergement Europe (Hostinger EU), DPA fourni, droit à l'effacement (anonymisation)
- **Archivage comptable** : 10 ans (art. L123-22 Code commerce), export FEC possible à tout moment
- **Horodatage audit** : `clock_timestamp()` DB

### 5.4 Disponibilité

- **SLA MVP** : 99.0% (mono-VPS)
- **SLA V2** : 99.5% (VPS secondaire warm standby)
- **RTO** : 4h | **RPO** : 1h (backups incrémentaux)

### 5.5 Observabilité

- **Logs structurés JSON** → Loki
- **Métriques Prometheus** (latence HTTP, temps DB, imports)
- **Dashboards Grafana** (existants sur ton VPS)
- **Error tracking** : GlitchTip self-hosted
- **Traces OpenTelemetry** : V1 optionnel

### 5.6 Accessibilité

- Conformité **RGAA 4.1 niveau AA** (obligation légale en France)
- Contrastes AA minimum
- Navigation clavier complète
- Support lecteurs d'écran (NVDA, JAWS, VoiceOver)
- Sémantique HTML correcte (déjà gérée par shadcn/ui + Radix UI)

---

## 6. Stratégie de tests

**Principe directeur** : les tests sont **écrits pendant** le développement, jamais après. Ils sont **bloquants** pour la livraison MVP.

### 6.1 Pyramide des tests hmanagement

```
                   ┌───┐
                   │E2E│          5 tests (parcours critiques)
                   └───┘
                ┌────────┐
                │  dbt   │        ~30 tests (qualité data)
                │ tests  │
                └────────┘
           ┌──────────────────┐
           │  Integration     │   ~50 tests (API + RLS)
           │  tests           │
           └──────────────────┘
     ┌─────────────────────────────┐
     │    Unit tests (Vitest)      │   150+ tests (calculs)
     └─────────────────────────────┘
```

**Proportion cible** : 70% unit, 20% integration, 7% dbt, 3% E2E.

### 6.2 Niveau 1 — Tests unitaires (Vitest)

**Scope** : fonctions pures, calculs financiers, helpers, formatages.

**Couverture exigée** : **100% sur les fonctions de calculs financiers** (non négociable MVP).

**Stack** :
- Vitest (framework)
- `@testing-library/react` pour les composants UI
- `happy-dom` pour DOM simulé léger

**Exemple canonique** :
```typescript
// src/lib/calculs/crd.test.ts
import { describe, it, expect } from 'vitest'
import { calculerMCV, calculerSeuilRentabilite } from './crd'

describe('calculerMCV', () => {
  it('calcule la marge sur coûts variables', () => {
    expect(calculerMCV(100000, 60000)).toBe(40000)
  })

  it('gère le cas CA nul', () => {
    expect(calculerMCV(0, 0)).toBe(0)
  })

  it('accepte MCV négative (charges > CA)', () => {
    expect(calculerMCV(50000, 70000)).toBe(-20000)
  })
})

describe('calculerSeuilRentabilite', () => {
  it('calcule le seuil de rentabilité', () => {
    // CA = 100 000, MCV = 40 000 → taux 40%
    // Charges fixes = 20 000 → SR = 50 000
    expect(calculerSeuilRentabilite(20000, 0.4)).toBe(50000)
  })

  it('lève une erreur si taux MCV = 0', () => {
    expect(() => calculerSeuilRentabilite(20000, 0)).toThrow()
  })
})
```

### 6.3 Niveau 2 — Tests d'intégration

**Scope** : interactions avec Supabase/PostgreSQL, API routes Next.js, policies RLS.

**Exigence** : chaque policy RLS critique est **testée automatiquement**.

**Exemple** :
```typescript
// src/services/crd-service.test.ts
describe('CrdService.getCrdMensuel', () => {
  beforeEach(async () => {
    await seedTestTenant('hma-test')
    await seedTestEntites()
  })

  it('respecte RLS : controleur ne voit pas autres filiales', async () => {
    await signInAs('controleur_transport')
    const result = await crdService.getCrdMensuel({
      entiteId: 'filiale_agri',
      mois: '2026-01'
    })
    expect(result).toBeNull()
  })

  it('admin voit le consolidé groupe', async () => {
    await signInAs('admin_hma')
    const result = await crdService.getCrdMensuel({
      entiteId: 'groupe_hma',
      mois: '2026-01'
    })
    expect(result).toBeDefined()
    expect(result.chiffre_affaires).toBeGreaterThan(0)
  })
})
```

### 6.4 Niveau 3 — Tests dbt (qualité données)

**Scope** : chaque mart doit avoir au minimum 3 tests.

**Types** :
- `not_null` sur clés primaires et étrangères
- `relationships` vers dimensions
- `unique` sur combinaisons de clés
- `accepted_range` pour cohérence métier
- `expression_is_true` pour règles business custom

**Exemple** :
```yaml
# dbt/models/marts/_marts.yml
version: 2
models:
  - name: mart_compte_resultat
    description: "Compte de résultat mensuel par entité HMA"
    columns:
      - name: periode
        tests: [not_null]
      - name: entite_id
        tests:
          - not_null
          - relationships:
              to: ref('dim_entites')
              field: id
      - name: chiffre_affaires_ht
        tests:
          - not_null
          - dbt_utils.accepted_range:
              min_value: 0
      - name: resultat_net
        tests:
          - dbt_utils.expression_is_true:
              expression: "= resultat_exploitation + resultat_financier + resultat_exceptionnel - impots"
```

### 6.5 Niveau 4 — Tests E2E (Playwright)

**Scope** : 5 parcours utilisateurs critiques simulés dans un vrai navigateur.

**Liste MVP** :
1. Login Magic Link end-to-end
2. Morning check gérant (< 30 secondes)
3. Drill-down 3 niveaux CRD
4. Admin invite un nouvel utilisateur
5. Export CSV d'un tableau

**Exemple** :
```typescript
// e2e/crd-drill-down.spec.ts
import { test, expect } from '@playwright/test'

test('controleur peut drill-down sur son CRD', async ({ page }) => {
  await signInAsControleurTransport(page)

  await page.goto('/activite/crd')
  await expect(page.getByTestId('crd-ca-value')).toBeVisible()

  // Niveau 2 : ventilation charges variables
  await page.getByTestId('expand-charges-variables').click()
  await expect(page.getByTestId('compte-607')).toBeVisible()

  // Niveau 3 : détail des écritures
  await page.getByTestId('compte-607').click()
  await expect(page.getByTestId('ecriture-list')).toBeVisible()
})
```

### 6.6 Tests obligatoires MVP (bloquants)

**Catégorie A — Calculs financiers (unit)** : 100% couverture
- Toutes les formules SIG (9 soldes)
- Toutes les formules CRD (MCV, seuil, levier, point mort, marge sécurité)
- Conversion centimes → euros Pennylane
- Variations vs N-1, cumuls YTD

**Catégorie B — Sécurité (integration)**
- RLS par filiale (isolation testée pour chaque rôle)
- RLS par rôle (consultant ne modifie pas)
- Anti-pattern : `user_metadata` jamais utilisé pour permissions
- Session expirée → redirection login

**Catégorie C — Data quality (dbt)**
- Chaque mart a not_null sur clés primaires
- Relationships vers dimensions
- Règles métier : CA ≥ 0, cohérence débits/crédits
- Fraîcheur des données (< 24h après sync)

**Catégorie D — E2E (Playwright)**
- 5 parcours critiques listés § 6.5

### 6.7 Workflow dans Claude Code

**Hook pre-commit** (dans `.claude/hooks/pre-commit`) :
```bash
#!/bin/bash
npm run lint && npm run typecheck || exit 1
npm run test:unit || exit 1
if git diff --cached --name-only | grep -q "dbt/models/"; then
  cd dbt && dbt compile || exit 1
fi
```

**Commandes Claude Code personnalisées** :
- `/test-crd` : lance tous les tests CRD (unit + integration + dbt + E2E)
- `/tdd-new <nom>` : démarre une session TDD (Red → Green → Refactor)
- `/review-coverage` : rapport de couverture du module sélectionné

**Skill dédiée** : `.claude/skills/testing-strategy/SKILL.md` (auto-déclenchée sur fichiers `*.test.ts`, `*.spec.ts`)

### 6.8 Anti-patterns de tests à éviter

- ❌ Tester l'implémentation (ex: `expect(useState).toHaveBeenCalled()`)
- ❌ Flaky tests tolérés (corriger ou supprimer immédiatement)
- ❌ 100% couverture fictive (tests qui n'assertent rien de pertinent)
- ❌ Mocks partout (préférer tests avec vraie DB de test)
- ❌ Tests qui dépendent de l'ordre d'exécution
- ❌ Assertions molles : `expect(result).toBeTruthy()` au lieu de vérifier la valeur exacte

---

## 7. Architecture cible

### 7.1 Vue logique

```
┌──────────────────────────────────────────────────────────┐
│                      UTILISATEURS                        │
│             (Kiki, gérant HMA, gestionnaire)             │
└────────────────────────┬─────────────────────────────────┘
                         │ HTTPS
                         ▼
┌──────────────────────────────────────────────────────────┐
│           Coolify / Traefik (reverse proxy)              │
│           TLS + Let's Encrypt + routing domain           │
└───────────┬─────────────────────────────┬────────────────┘
            │                             │
            ▼                             ▼
   ┌─────────────────┐         ┌─────────────────────┐
   │ Next.js 15      │         │  n8n                │
   │ App Router      │         │  (orchestration     │
   │ SSR + RSC       │         │   Pennylane sync)   │
   │ shadcn + Tremor │         └─────────┬───────────┘
   └────────┬────────┘                   │
            │                             │
            │   ┌─────────────────────────┘
            │   │
            ▼   ▼
   ┌───────────────────────────────────────────────┐
   │ SUPABASE SELF-HOSTED (Coolify)                │
   │ ┌───────────────────────────────────────────┐ │
   │ │ PostgreSQL 16                             │ │
   │ │  ├── raw.*      (ingestion Pennylane)     │ │
   │ │  ├── staging.*  (dbt intermédiaire)       │ │
   │ │  ├── marts.*    (analytics exposées)      │ │
   │ │  └── app.*      (tables applicatives)     │ │
   │ └───────────────────────────────────────────┘ │
   │ ┌───────────────────────────────────────────┐ │
   │ │ Supabase Auth (Magic Link + MFA TOTP)     │ │
   │ │ PostgREST (API REST auto-générée)         │ │
   │ │ RLS policies (isolation par tenant+rôle)  │ │
   │ │ Storage (exports CSV, futurs uploads)     │ │
   │ │ Studio (admin technique Kiki)             │ │
   │ └───────────────────────────────────────────┘ │
   └──────────────┬────────────────────────────────┘
                  │ (déclenché par n8n après sync)
                  ▼
   ┌───────────────────────────────────────────────┐
   │ dbt Core (container Coolify)                  │
   │ Transformations raw → staging → marts         │
   │ Tests qualité de données                      │
   │ Documentation auto-générée                    │
   └───────────────────────────────────────────────┘

Monitoring :
   Grafana + Loki + Prometheus + GlitchTip (déjà en place sur ton VPS)
```

### 7.2 Briques & responsabilités

| Brique | Techno | Responsabilité |
|---|---|---|
| Reverse proxy | Traefik (via Coolify) | TLS, routing par host |
| Front | Next.js 15 App Router | SSR, Server Components, hydratation |
| UI | shadcn/ui + Tailwind v4 | Layout, formulaires, navigation, tables |
| Data-viz | Tremor | KPI cards, graphiques financiers |
| Tables | TanStack Table + TanStack Virtual | Drill-down, virtualisation |
| API | Next.js route handlers + Server Actions | Business logic, auth |
| Backend | Supabase self-hosted | PostgreSQL + Auth + PostgREST + RLS |
| Client DB | `@supabase/ssr` | Types TypeScript, SSR-compatible |
| Orchestration | n8n (déjà existant) | Sync Pennylane, déclenchement dbt |
| Transformations | dbt Core | ELT SQL versionné + tests qualité |
| Observabilité | Grafana + Loki + Prometheus + GlitchTip | Existant sur ton VPS |
| Secrets | Vaultwarden + env Coolify | Gestion centralisée |

### 7.3 Flux critiques

**Flux 1 — Synchronisation quotidienne Pennylane**
```
02:00 cron n8n
  ↓
n8n récupère /invoices, /transactions, /ledger_entries via API Pennylane
  ↓
UPSERT dans raw.pennylane_* (JSONB, idempotent)
  ↓
n8n déclenche `docker exec dbt-container dbt run`
  ↓
dbt : raw → staging → marts
  ↓
dbt test : validation qualité
  ↓
Si OK : notification Discord "✅ Sync OK"
Si KO : notification + alerte Slack
```

**Flux 2 — Consultation drill-down**
```
User clique sur rubrique "Charges externes"
  ↓
Next.js Server Component appelle Supabase
  ↓
RLS filtre selon auth.jwt() : rôle + entite_id
  ↓
Requête SQL sur mart_compte_resultat (niveau 1)
  ↓
User clique sur un compte
  ↓
Requête niveau 2 : ventilation par compte
  ↓
User clique sur compte 607100
  ↓
Requête niveau 3 : liste écritures paginée (100 lignes)
```

### 7.4 Principes d'architecture

- **Monolithe modulaire** en MVP (pas de microservices avant 5 clients)
- **API stateless** : scaling horizontal trivial plus tard
- **Outbox pattern** : toute écriture avec effet de bord async passe par une table d'événements (préparation IA V2)
- **Read models séparés** : `marts.*` distincts du transactionnel Pennylane (`raw.*`)
- **Feature flags** par tenant (table `app.tenant_features`) pour V2
- **Agnostic à Supabase** : l'accès DB passe par une couche d'abstraction (`src/lib/db/*`) pour fallback possible

---

## 8. Modèle de données

### 8.1 Schémas PostgreSQL

```sql
CREATE SCHEMA raw;        -- Données Pennylane brutes (JSONB)
CREATE SCHEMA staging;    -- Nettoyage dbt (1 modèle = 1 source)
CREATE SCHEMA marts;      -- Vues analytiques finales
CREATE SCHEMA app;        -- Tables applicatives (users, entites, audit)
```

**Règles strictes** :
- **MUST** : toute table applicative a `tenant_id uuid NOT NULL`
- **MUST** : RLS activée sur tout `app.*` et `marts.*`
- **NEVER** : accès direct à `raw.*` ou `staging.*` depuis Next.js
- Les tables `app.*` et `marts.*` sont lisibles via l'API
- Les tables `raw.*` et `staging.*` sont utilisées par dbt et n8n uniquement

### 8.2 Tables applicatives (schéma `app`)

```sql
-- ─── Multi-tenant root ───────────────────────────────────
CREATE TABLE app.tenants (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug       text UNIQUE NOT NULL,        -- 'hma' en MVP
  name       text NOT NULL,
  plan       text DEFAULT 'mvp',          -- 'mvp' | 'starter' | 'pro' | 'enterprise'
  created_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);

-- ─── Profils utilisateurs (liés à auth.users Supabase) ───
CREATE TYPE user_role AS ENUM (
  'super_admin', 'admin', 'controleur', 'consultant'
);

CREATE TABLE app.profiles (
  id           uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  tenant_id    uuid NOT NULL REFERENCES app.tenants(id),
  email        text NOT NULL,
  prenom       text,
  nom          text,
  role         user_role NOT NULL,
  entite_id    uuid REFERENCES app.entites(id),  -- filiale de rattachement
  actif        boolean DEFAULT false,             -- inactif par défaut
  mfa_enabled  boolean DEFAULT false,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

-- ─── Entités (filiales HMA) ──────────────────────────────
CREATE TYPE entite_type AS ENUM (
  'holding', 'filiale_transport', 'filiale_agri', 'filiale_agroalimentaire'
);

CREATE TABLE app.entites (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES app.tenants(id),
  code            text NOT NULL,              -- 'HMA', 'HMA-TRANSPORT', etc.
  nom             text NOT NULL,
  type            entite_type NOT NULL,
  parent_id       uuid REFERENCES app.entites(id),  -- hiérarchie groupe
  siren           text,
  code_pennylane  text,                        -- mapping Pennylane
  devise          text DEFAULT 'EUR',
  actif           boolean DEFAULT true,
  created_at      timestamptz DEFAULT now()
);

-- ─── Audit trail (append-only) ───────────────────────────
CREATE TABLE app.audit_log (
  id          bigserial PRIMARY KEY,
  tenant_id   uuid NOT NULL,
  user_id     uuid REFERENCES auth.users(id),
  action      text NOT NULL,               -- 'export.csv', 'user.grant', 'entite.update'
  target_type text,
  target_id   text,
  payload     jsonb,
  ip          inet,
  user_agent  text,
  occurred_at timestamptz DEFAULT clock_timestamp()
);
-- Aucun UPDATE ni DELETE autorisé (trigger blocker)

-- ─── Feature flags par tenant ────────────────────────────
CREATE TABLE app.tenant_features (
  tenant_id         uuid PRIMARY KEY REFERENCES app.tenants(id),
  ai_enabled        boolean DEFAULT false,
  forecast_enabled  boolean DEFAULT false,
  max_users         int DEFAULT 20,
  max_entites       int DEFAULT 5
);

-- ─── Budget (import CSV en MVP) ──────────────────────────
CREATE TABLE app.budgets (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL,
  entite_id       uuid NOT NULL REFERENCES app.entites(id),
  exercice        int NOT NULL,               -- 2026
  compte_numero   text NOT NULL,              -- '607100'
  montant_budget  numeric(18, 2) NOT NULL,
  pourcentage_cible numeric(5, 2),             -- optionnel
  import_source   text,                        -- 'csv-2026-01-15.csv'
  created_at      timestamptz DEFAULT now()
);
CREATE UNIQUE INDEX ON app.budgets (tenant_id, entite_id, exercice, compte_numero);
```

### 8.3 Tables analytiques (schéma `marts`)

Générées par dbt, documentées dans `dbt/models/marts/_marts.yml`.

Modèles MVP :
- `mart_compte_resultat` : CR mensuel standard PCG par entité
- `mart_compte_resultat_differentiel` : CRD avec ventilation V/F
- `mart_sig` : 9 soldes intermédiaires de gestion
- `mart_kpi_home` : les 4 KPI de la home (CA, Marge, Résultat, Trésorerie estimée)
- `dim_entites` : dimension des entités (synchronisée avec `app.entites`)
- `dim_comptes` : PCG structuré avec hiérarchie

### 8.4 Tables brutes (schéma `raw`)

Alimentées par n8n.

```sql
CREATE TABLE raw.pennylane_invoices (
  id                 serial PRIMARY KEY,
  tenant_id          uuid NOT NULL,
  entite_id          uuid NOT NULL,
  pennylane_id       text NOT NULL,
  data               jsonb NOT NULL,
  extracted_at       timestamptz DEFAULT now(),
  UNIQUE (tenant_id, entite_id, pennylane_id)
);
CREATE INDEX ON raw.pennylane_invoices USING GIN (data);
CREATE INDEX ON raw.pennylane_invoices (tenant_id, extracted_at);

-- Idem pour pennylane_transactions, pennylane_ledger_entries, etc.
```

### 8.5 Classification V/F des charges (pour CRD)

Classification par défaut (conforme PCG, voir `compta_analytique.md` §5.2) stockée dans :

```sql
CREATE TABLE app.pcg_nature_charge (
  compte_pattern text PRIMARY KEY,        -- '607%', '6132', etc.
  nature_defaut  text NOT NULL,            -- 'variable' | 'fixe' | 'mixte'
  ratio_variable numeric(3, 2),            -- pour 'mixte' (ex: 0.60)
  description    text,
  created_at     timestamptz DEFAULT now()
);

-- Override par profil sectoriel (V1 pour autres clients)
CREATE TABLE app.profil_nature_charge (
  profil         text,                     -- 'transport', 'agri', 'btp'
  compte_pattern text,
  nature         text,
  ratio_variable numeric(3, 2),
  PRIMARY KEY (profil, compte_pattern)
);

-- Override par entité (granularité la plus fine)
CREATE TABLE app.entite_override_charge (
  entite_id      uuid REFERENCES app.entites(id),
  compte_pattern text,
  nature         text,
  ratio_variable numeric(3, 2),
  PRIMARY KEY (entite_id, compte_pattern)
);
```

Fonction SQL de résolution :
```sql
-- resolve_nature(compte_num, entite_id) : applique la hiérarchie override
CREATE FUNCTION app.resolve_nature(compte_num text, p_entite_id uuid)
RETURNS TABLE (nature_finale text, ratio numeric) AS $$
  -- 1. Cherche d'abord dans entite_override
  -- 2. Puis profil sectoriel de l'entité
  -- 3. Puis pcg_nature_charge par défaut
  -- ...
$$ LANGUAGE plpgsql;
```

### 8.6 Règles d'intégrité critiques

- Toutes les tables `app.*` et `marts.*` ont `tenant_id NOT NULL`
- RLS activée avec policy `USING (tenant_id = current_setting('app.tenant_id', true)::uuid)`
- Soft delete via `deleted_at` sur entités
- **JAMAIS** de suppression destructive sur `app.audit_log` ou données comptables
- Trigger anti-UPDATE/DELETE sur `app.audit_log`
- Contrainte `CHECK (actif IS TRUE OR deleted_at IS NOT NULL)` pour cohérence

---

## 9. Stratégie multi-tenant

### 9.1 Décision : architecture-ready, MVP mono-tenant

**En MVP** : un seul tenant `hma` actif. Pas d'onboarding, pas de signup public.

**En V2** : activation multi-tenant réel. Le code est **identique**, seule la configuration change.

### 9.2 Implémentation RLS (Row-Level Security Postgres)

```sql
-- Activation RLS
ALTER TABLE app.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE app.entites ENABLE ROW LEVEL SECURITY;
ALTER TABLE marts.mart_compte_resultat ENABLE ROW LEVEL SECURITY;
-- ... toutes les tables

-- Policy : isolation par tenant
CREATE POLICY tenant_isolation ON app.profiles
  FOR ALL
  USING (tenant_id = (auth.jwt() ->> 'tenant_id')::uuid);

-- Policy : isolation par rôle + entité
CREATE POLICY controleur_sa_filiale ON marts.mart_compte_resultat
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM app.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id = mart_compte_resultat.tenant_id
        AND (
          p.role IN ('super_admin', 'admin')  -- tout voir
          OR (p.role = 'controleur' AND p.entite_id = mart_compte_resultat.entite_id)
          OR (p.role = 'consultant' AND p.entite_id = mart_compte_resultat.entite_id)
        )
    )
  );
```

### 9.3 Pivot vers multi-tenant réel (V2)

Aucun refactoring majeur nécessaire :
1. Créer de nouveaux tenants dans `app.tenants`
2. Activer un formulaire d'onboarding (page `/signup`)
3. Activer la logique de routing par sous-domaine (`clientX.hmanagement.app`)
4. Activer les features flags par tenant
5. Mettre en place la facturation (Stripe)

### 9.4 Sécurité RLS — principes

- **Ceinture + bretelles** : même si une query oublie `WHERE tenant_id`, RLS bloque au niveau DB
- **Test automatique obligatoire** : "user tenant A ne voit jamais tenant B"
- **Rôle applicatif** sans `BYPASSRLS`
- **Rôle migration** séparé avec privilèges élevés
- **PgBouncer transaction pooling** compatible avec `SET LOCAL`

---

## 10. Stack technique

### 10.1 Stack finale (validée)

| Couche | Outil | Version cible |
|---|---|---|
| **Framework web** | Next.js | 15.x App Router |
| **Langage** | TypeScript | 5.x strict |
| **Styling** | Tailwind CSS | v4 |
| **UI components** | shadcn/ui | dernière |
| **Dashboards UI** | Tremor | `@tremor/react` v3.18+ |
| **Charts** | Recharts (via Tremor + shadcn Chart) | - |
| **Tables** | TanStack Table + TanStack Virtual | v8+ |
| **Data fetching** | TanStack Query | v5 |
| **Forms** | React Hook Form + Zod | - |
| **Backend** | Supabase self-hosted | dernière stable |
| **Client Supabase** | `@supabase/ssr` | dernière |
| **DB** | PostgreSQL | 16 (via Supabase) |
| **Orchestration** | n8n | existant |
| **Transformations** | dbt Core | 1.7+ |
| **Tests unit** | Vitest | dernière |
| **Tests React** | @testing-library/react | dernière |
| **Tests DOM** | happy-dom | dernière |
| **Tests E2E** | Playwright | dernière |
| **Linter** | ESLint | 9 flat config |
| **Formatter** | Prettier | dernière |
| **Git hooks** | Husky + lint-staged | dernière |
| **Secrets** | Vaultwarden + Coolify env | existant |
| **Déploiement** | Coolify + Docker | existant |
| **Monitoring** | Grafana + Loki + Prometheus + GlitchTip | existant |
| **Méthodologie** | GitHub Spec Kit | v0.7+ |
| **IDE** | VSCode + Claude Code | dernière |

### 10.2 Alternatives reconnues mais non retenues

| Outil | Raison du rejet |
|---|---|
| Supabase Cloud (managed) | Souveraineté requise, self-hosted obligatoire |
| Drizzle ORM pur | Supabase SDK suffit en MVP, Drizzle en option V2 si besoin |
| Django + HTMX | Stack TypeScript retenue pour productivité Claude Code |
| Pages Router Next.js | En maintenance, App Router est le standard 2026 |
| Jest | Vitest plus rapide et moderne |
| Airflow | Overkill pour le volume Pennylane HMA, n8n suffit |
| Metabase | Pas assez customisable pour UI client finale |
| Power BI Report Server | Windows-only, licence enterprise |

---

## 11. Pattern UX universel

### 11.1 Principe directeur

> *"La meilleure UX est celle qui ne se remarque pas." — Don Norman*

Un utilisateur ne doit jamais hésiter plus de 3 secondes sur une action. Si c'est le cas, l'UX est ratée.

### 11.2 Règles d'or dashboards financiers

1. **Hierarchy of information** : info la plus importante en haut à gauche
2. **Progressive disclosure** : commencer synthétique, permettre le détail
3. **Contextual comparison** : tout chiffre comparé (vs N-1, vs budget)
4. **Color with meaning** : vert/rouge sémantiques, doublés par symbole (↑↓✓✗)
5. **Fast time to first value** : comprendre en < 5 secondes
6. **Action, pas contemplation** : chaque KPI permet une action (drill-down)
7. **Trust through transparency** : source et formule toujours accessibles

### 11.3 Pattern KPI Card universel (non négociable)

```
┌─ [Titre métier] ────────────────────┐
│  [Valeur formatée]                  │
│  [BadgeDelta vs N-1]                │
│  [SparkChart 12 mois]               │
│  ℹ️ [Formule au hover/tooltip]       │
│  [→ Bouton drill-down source]       │
└─────────────────────────────────────┘
```

**6 éléments obligatoires** :
1. Titre métier compréhensible (pas de jargon technique)
2. Valeur principale formatée (€, %, selon nature)
3. Delta vs période comparée (BadgeDelta Tremor)
4. Mini-graphique de tendance (SparkChart Tremor)
5. Formule accessible au hover (Tooltip shadcn)
6. Action claire : clic = drill-down vers module source

### 11.4 Pattern tableau drill-down

**3 niveaux** :
- Niveau 1 : rubrique agrégée (ex: "Charges externes")
- Niveau 2 : ventilation par compte (ex: 607x, 613x...)
- Niveau 3 : liste des écritures comptables

**Interactions** :
- Expandable rows (expansion inline)
- Colonnes réordonnables en drag & drop
- Tri multi-colonnes
- Lignes à montant nul masquées par défaut (toggle pour afficher)

### 11.5 Pattern filtres temporels

**Granularités** : semaine, mois, trimestre, année, rolling 12 mois

**Composants** :
- `TabGroup` Tremor pour basculer granularité
- `DateRangePicker` Tremor pour plage custom
- Chips de raccourcis : "Ce mois", "N-1", "YTD", "Rolling 12"

### 11.6 Mapping calendrier (rapports récurrents)

Structure proposée pour V1 :
- Table `app.rapports_recurrents` (fréquence, échéance, destinataires)
- Widget dashboard "Prochain rapport dû"
- Génération PDF automatique à échéance

---

## 12. Stratégie de déploiement

### 12.1 Environnements

| Env | Infra | Usage |
|---|---|---|
| Dev local | Docker Compose | Développement, hot reload |
| Staging | VPS Hostinger (existant) / Coolify | Tests d'intégration |
| Prod | VPS Hostinger (existant) / Coolify | Production HMA |

### 12.2 Domaine & routing

- **Prod** : `hmanagement.hma.business` (ou à définir)
- **Staging** : `staging.hmanagement.hma.business`
- **Supabase Studio** : `supabase.hma.business` (protégé par IP whitelist)

### 12.3 CI/CD

**Pipeline GitHub Actions** (à la fin du Sprint 1) :
1. Lint (`npm run lint`)
2. Typecheck (`npm run typecheck`)
3. Tests unitaires (`npm run test:unit`)
4. Tests d'intégration (`npm run test:integration`)
5. Build Docker
6. Push GHCR avec tag SHA + `latest`
7. Webhook Coolify → déploiement auto staging sur merge `main`
8. Déploiement prod sur tag `v*`

**Tests E2E** : lancés uniquement sur PR (Playwright headless).

### 12.4 Backups

- **Postgres** : `pg_dump` quotidien 03:00 → stockage externe, rétention 14 j
- **Postgres full** : `pg_basebackup` hebdomadaire → bucket S3 externe (Backblaze), rétention 90 j
- **Test de restauration** : mensuel obligatoire, script automatisé
- **Config Coolify** : export manuel hebdomadaire

### 12.5 Monitoring

- Healthchecks `/api/health` (DB + Supabase ping)
- Uptime externe via UptimeRobot
- Alertes Grafana :
  - Latence p95 > 1.5s pendant 5 min
  - Taux erreur 5xx > 1% pendant 5 min
  - Sync Pennylane > 15 min
  - Disque > 80%
- Canal : Discord webhook (solo, pas besoin de PagerDuty)

### 12.6 Sécurité opérationnelle

- Fail2ban sur SSH
- SSH par clé uniquement, port non-standard
- Firewall VPS : 22 / 80 / 443 uniquement
- Coolify admin via WireGuard uniquement
- Rotation secrets DB tous les 6 mois (procédure documentée)

---

## 13. Roadmap par sprints

### Sprint 0 ✅ (FAIT)
- CLAUDE.md + constitution.md + skill hma-context
- CDC v0.2 consolidé (ce document)
- Skill testing-strategy

### Sprint 1 — Infrastructure Supabase (1 semaine)
- Installation Supabase self-hosted sur Coolify
- Configuration domaine + SSL Traefik
- Schéma `app` : tables `tenants`, `profiles`, `entites`, `audit_log`, `tenant_features`, `budgets`
- Configuration Auth : Magic Link + MFA TOTP
- Seed : tenant `hma` + entités + compte super_admin Kiki
- **Tests** : RLS par rôle, isolation tenant
- **Livrable** : login Supabase Studio fonctionnel avec MFA

### Sprint 2 — Next.js + shadcn + auth (1 semaine)
- Bootstrap Next.js 15 App Router + TypeScript strict
- Installation shadcn/ui + Tremor + TanStack
- Configuration ESLint + Prettier + Husky + lint-staged
- Configuration Vitest + Playwright
- Page `/login` avec Magic Link
- Middleware auth + layout protégé
- UI admin `/admin/users`, `/admin/entites`
- **Tests** : E2E login Magic Link, unit tests helpers auth
- **Livrable** : login fonctionnel dans l'app, UI admin HMA

### Sprint 3 — Pipeline ELT Pennylane → marts (1-2 semaines)
- Workflow n8n de sync Pennylane quotidienne
- Schémas `raw` et `staging`
- Premiers modèles dbt : `stg_pennylane__*`, `dim_entites`, `dim_comptes`
- Tests dbt qualité données
- Documentation dbt docs
- **Tests** : dbt tests obligatoires, tests intégration n8n
- **Livrable** : données HMA réelles visibles dans `marts` via Supabase Studio

### Sprint 4 — Module Compte de Résultat (1-2 semaines)
- Mart `mart_compte_resultat`
- Page `/etats-financiers/compte-resultat`
- Tableau avec drill-down 3 niveaux
- Colonnes Montant/Réel/Budget/Écart/%
- Filtres temporels + entité
- Export CSV
- **Tests** : 100% couverture calculs, E2E drill-down
- **Livrable** : CR standard PCG complet

### Sprint 5 — Module CRD (1 semaine)
- Mart `mart_compte_resultat_differentiel` avec classification V/F
- Import CSV budget avec UI admin
- Page `/activite/crd`
- KPI complémentaires (MCV, seuil de rentabilité, levier)
- **Tests** : 100% couverture formules CRD, E2E complet
- **Livrable** : CRD opérationnel pour HMA

### Sprint 6 — Module SIG + KPI home (1 semaine)
- Mart `mart_sig` (9 soldes)
- Page `/activite/sig`
- Home avec 4 KPI Cards cliquables
- Tooltips formules depuis `compta_analytique.md`
- **Tests** : E2E morning check gérant (< 30s)
- **Livrable** : MVP complet testable par le gérant HMA

### Sprint 7 — Hardening + prod (1 semaine)
- Audit trail complet
- Tests de charge
- Tests de sécurité (RLS, injection, XSS)
- Déploiement production Coolify
- Documentation utilisateur HMA
- Formation gérant + gestionnaire
- **Livrable** : MVP en production, HMA l'utilise

**Total MVP** : **7-9 semaines** selon rythme et imprévus.

---

## 14. Risques & mitigations

| # | Risque | Proba | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Fuite cross-tenant (query mal filée) | Faible | Critique | RLS obligatoire + tests isolation automatisés |
| R2 | Perf drill-down sur volume | Moyen | Fort | Marts pré-calculés dbt, index BRIN/btree composites |
| R3 | API Pennylane instable ou rate-limited | Moyen | Fort | Retry exponential backoff + DLQ + pagination |
| R4 | VPS down (SPOF) | Faible | Fort | Backups quotidiens externes + docs runbook |
| R5 | Bug de calcul compta | Moyen | Critique | Tests unit 100% sur formules + validation croisée Pennylane |
| R6 | Scope creep (feature V1 qui fuit en MVP) | Élevé | Fort | Scope strict gelé, toute exception = commit ADR |
| R7 | Classification V/F erronée (CRD) | Moyen | Moyen | Overrides par entité + validation manuelle avec DAF |
| R8 | Dépassement ressources Supabase self-hosted | Moyen | Moyen | Monitoring RAM/CPU, upgrade VPS si besoin |
| R9 | Surcharge solo dev | Élevé | Fort | Scope MVP gelé, pas de side projects, discipline Claude Code |
| R10 | Mauvaise adoption utilisateur | Moyen | Critique | Tests utilisateurs dès Sprint 4, itérations rapides |
| R11 | Dette technique à cause vitesse | Moyen | Moyen | Code review Claude Code + pre-commit hook strict |
| R12 | Tests flaky | Élevé | Moyen | Correction immédiate ou suppression, zéro tolérance |

---

## 15. Estimations d'effort

Hypothèse : **Kiki solo, AI-assisted (Claude Code)**, ~3-4h code effectif/jour.

| Sprint | Effort (jours-h) |
|---|---|
| Sprint 1 — Supabase | 5 |
| Sprint 2 — Next.js + auth | 6 |
| Sprint 3 — ELT pipeline | 8 |
| Sprint 4 — Module CR | 10 |
| Sprint 5 — Module CRD | 7 |
| Sprint 6 — SIG + KPI home | 6 |
| Sprint 7 — Hardening + prod | 5 |
| Buffer imprévus | 8 |
| **Total MVP** | **~55 jours-h** |

À 3-4h/jour → **2 à 3 mois calendaires** pour MVP livré en production.

Coefficient prudence 1.3× sur les premiers sprints → **3 mois réalistes**.

---

## 16. Annexes

### 16.1 Glossaire

- **SIG** : Soldes Intermédiaires de Gestion (9 soldes + CAF)
- **CRD** : Compte de Résultat Différentiel (analyse seuil de rentabilité)
- **CR** : Compte de Résultat (standard PCG)
- **CAF** : Capacité d'Autofinancement
- **FRNG** : Fonds de Roulement Net Global
- **BFR** : Besoin en Fonds de Roulement
- **PCG** : Plan Comptable Général français
- **FEC** : Fichier des Écritures Comptables (format légal DGFiP)
- **RLS** : Row-Level Security (PostgreSQL)
- **ELT** : Extract, Load, Transform (paradigme data moderne)
- **dbt** : data build tool (transformations SQL versionnées)
- **TDD** : Test-Driven Development
- **TTFB** : Time To First Byte
- **MFA / TOTP** : Multi-Factor Authentication / Time-based One-Time Password

### 16.2 Référentiel comptable

Voir `compta_analytique.md` — source de vérité des formules financières.

Sections critiques pour MVP :
- §1. SIG (9 soldes avec formules SQL)
- §2. Compte de résultat structure détaillée
- §5. Résultat différentiel (CRD)
- Annexe A. Correspondance comptes PCG et états financiers
- Annexe B. Contrôles de cohérence

### 16.3 Liens utiles

- API Pennylane : https://pennylane.readme.io/reference
- Supabase self-hosting : https://supabase.com/docs/guides/self-hosting
- dbt Core : https://docs.getdbt.com/
- Spec Kit : https://github.com/github/spec-kit
- shadcn/ui : https://ui.shadcn.com/
- Tremor : https://tremor.so
- Next.js App Router : https://nextjs.org/docs/app

### 16.4 Antipatterns hmanagement (liste vivante)

- ❌ Stocker les rôles dans `user_metadata` Supabase (modifiable par user)
- ❌ Faire des permissions uniquement côté frontend
- ❌ SELECT * dans un mart
- ❌ Jointure sans ON explicite
- ❌ Hard-coder des dates (utiliser `{{ var() }}` dbt)
- ❌ Oublier `tenant_id` dans un filtre (même si RLS protège, c'est une odeur de code)
- ❌ Committer sans tests
- ❌ Désactiver ESLint/TypeScript en mode strict
- ❌ Ajouter une feature hors MVP "parce que c'est rapide à faire"
- ❌ Utiliser `any` en TypeScript sans commentaire justificatif

### 16.5 Definition of Done (par module)

Un module est **livré** quand :
- ✅ Code mergé sur `main`
- ✅ Tests unit couvrant 100% des calculs
- ✅ Au moins 1 test d'intégration avec RLS
- ✅ Tests dbt sur marts concernés
- ✅ Au moins 1 test E2E sur parcours critique
- ✅ Documentation YAML dbt à jour
- ✅ Tooltips de formules visibles sur KPI
- ✅ Utilisateur de test (Kiki) l'a validé manuellement
- ✅ Aucune erreur ESLint / TypeScript
- ✅ Pre-commit hook passe sans skip

---

*Fin du CDC v0.2 — document vivant, à itérer avec HMA après Sprint 4.*
