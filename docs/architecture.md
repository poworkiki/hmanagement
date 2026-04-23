# Architecture — hmanagement

> **Statut** : architecture cible MVP, non négociable sans ADR.
> **Complément de** : `constitution.md` (principes), `docs/stack.md` (outils), `docs/setup.md` (ops).

---

## 1. Principes directeurs

| Principe | Conséquence |
|---|---|
| **Souveraineté** (Art. 2) | Tout self-hébergé, aucun SaaS US non RGPD |
| **ELT pas ETL** (Art. 3.1) | Données brutes conservées dans `raw`, transformations dans Postgres via dbt |
| **Multi-tenant ready** (Art. 3.2) | `tenant_id NOT NULL` partout dès MVP, RLS active |
| **Majestic Monolith** (Art. 3.3) | Un seul app Next.js, pas de microservices avant 5 clients |
| **Défense en profondeur** (Art. 4.2) | RLS DB + check role serveur + check UI |
| **North Star Metric** (Art. 12) | Clôture Pennylane → décision < 30s — toute décision design passe ce test |

## 2. Vue d'ensemble — composants & frontières

```
┌─────────────────────────────────────────────────────────────────┐
│                       UTILISATEURS                              │
│              (Kiki super_admin, gérant, gestionnaire)           │
└────────────────────────────┬────────────────────────────────────┘
                             │ HTTPS
                             ▼
                    ┌─────────────────┐
                    │     Traefik     │  TLS + Let's Encrypt
                    │  (via Coolify)  │  + Rate limit + Headers sec
                    └────┬───────┬────┘
                         │       │
          ┌──────────────┘       └───────────────┐
          ▼                                       ▼
  ┌───────────────┐                     ┌──────────────────┐
  │  Next.js 15   │                     │       n8n        │
  │  App Router   │                     │  (existant VPS)  │
  │  Server Comps │                     └────────┬─────────┘
  │  + shadcn     │                              │
  │  + Tremor     │                              │ cron 02:00
  └───┬───────┬───┘                              │
      │       │                                  ▼
      │       │                      ┌─────────────────────┐
      │       │                      │  Pennylane API      │
      │       │                      │  (HMA + STIVMAT +   │
      │       │                      │   STA + ETPA)       │
      │       │                      └─────────┬───────────┘
      │       │                                │ JSON
      │       │                                ▼
      │       │       ┌─────────────────────────────────────┐
      │       │       │  SUPABASE SELF-HOSTED (Coolify)     │
      │       │       │  ┌─────────────────────────────────┐│
      │       │       │  │  PostgreSQL 16                  ││
      │       └──SDK──┼─▶│  ├── raw.*     (ingestion n8n)  │◀── service_role
      │               │  │  ├── staging.* (dbt)            ││
      │               │  │  ├── marts.*   (lecture app)    ││
      │               │  │  └── app.*     (tables app)     ││
      │               │  └─────────────────────────────────┘│
      │               │  ┌─────────────────────────────────┐│
      │   ssr/anon   ─┼─▶│  GoTrue (Magic Link + MFA TOTP) ││
      │               │  │  PostgREST (auto REST sur RLS)  ││
      │               │  │  Kong (gateway)                 ││
      │               │  │  Studio (admin Kiki — IP WL)    ││
      │               │  └─────────────────────────────────┘│
      │               └────────────┬────────────────────────┘
      │                            │
      │                            │ triggered by n8n
      │                            ▼
      │               ┌────────────────────────────┐
      │               │  dbt Core (container)      │
      │               │  raw → staging → marts     │
      │               │  + tests qualité data      │
      │               └────────────────────────────┘
      │
      ▼
  ┌────────────────────────┐
  │  Grafana + Loki +      │  observabilité
  │  Prometheus +          │  (déjà en place)
  │  Uptime Kuma           │
  └────────────────────────┘
```

### Frontières de responsabilité

| Composant | Lit | Écrit | Jamais |
|---|---|---|---|
| **n8n** | Pennylane API | `raw.*` (service_role) | `staging`, `marts`, `app` |
| **dbt** | `raw.*`, `staging.*` | `staging.*`, `marts.*` | `app.*`, `raw.*` direct modif |
| **Next.js (user)** | `marts.*`, `app.*` (via RLS) | `app.*` (via RLS) | `raw.*`, `staging.*`, service_role |
| **Next.js (server action critique)** | idem | idem | service_role sauf cas documenté |

## 3. Flux de données — sync quotidien

```
02:00  n8n cron
  │
  ├─▶ GET Pennylane /invoices /transactions /ledger_entries
  │   (4 structures : HMA, STIVMAT, STA, ETPA)
  │
  ├─▶ UPSERT raw.pennylane_* (JSONB, idempotent clé source_id)
  │
  ├─▶ exec dbt run --select state:modified+
  │     ├─ staging : nettoyage, cents→euros, caste dates
  │     ├─ intermediate : classif V/F charges, agrégats inter
  │     └─ marts : mart_cr, mart_crd, mart_sig, mart_kpi_home
  │
  ├─▶ exec dbt test --select state:modified+
  │
  └─▶ Webhook Discord : ✅ "Sync OK, 1247 rows processed, 12s"
                       | ❌ "Sync FAIL on mart_crd : test relationships"
```

### Garanties
- **Idempotence** : re-run safe, clé `(source, source_id, extracted_at)`
- **Fraîcheur mesurée** : `dbt source freshness` doit < 24h
- **Atomicité** : si un test dbt fail, les marts de cette branche sont dans l'état **précédent** (pas de partial update visible au user)

## 4. Flux de données — consultation (drill-down 3 niveaux)

```
User clique "Charges externes" (rubrique niveau 1)
  │
  ▼
Server Component page /etats-financiers/compte-resultat/charges-externes
  │
  ├─ requireUser() → redirect /login si pas de session
  │
  ├─ Supabase SSR client :
  │    SELECT rubrique, montant, variation_n1
  │    FROM marts.mart_cr_rubriques
  │    WHERE periode = $1
  │    (RLS filtre automatiquement tenant + entité selon rôle)
  │
  ├─ Server Component retourne HTML streamé
  │
  ▼
User clique compte "607100" (niveau 2)
  │
  ▼
Server Component /etats-financiers/compte-resultat/charges-externes/607
  │
  └─ SELECT compte, libelle, montant, écritures_count
     FROM marts.mart_cr_comptes
     WHERE rubrique = 'charges-externes' AND periode = $1
  │
  ▼
User clique écriture (niveau 3)
  │
  ▼
Pagination TanStack Virtual : 100 écritures
  │
  └─ SELECT ecriture_id, libelle, montant, date_piece, numero_facture
     FROM marts.mart_cr_ecritures
     WHERE compte = '607100' AND periode = $1
     ORDER BY date_piece DESC
     LIMIT 100 OFFSET $offset
```

### Performance cible
- Niveau 1 : < 800ms TTFB p95 (mart pré-calculé par dbt)
- Niveau 2 : < 1.5s
- Niveau 3 : < 1s paginé 100 lignes

### Leviers
- Marts matérialisés en tables `incremental` par `(tenant_id, entite_id, periode)`
- Index btree composites sur chaque mart
- Index BRIN sur colonnes temporelles
- Pagination serveur obligatoire niveau 3

## 5. Modèle de sécurité

### 5.1 Couches de défense
```
┌─────────────────────────────────────────────────┐
│  1. Traefik : TLS, rate limit, headers sec, CSP │
├─────────────────────────────────────────────────┤
│  2. Middleware Next.js : session timeout,       │
│     vérif JWT, MFA requis pour admin/super      │
├─────────────────────────────────────────────────┤
│  3. Server Components : requireUser() +         │
│     requireRole(role[]) en haut de chaque page  │
├─────────────────────────────────────────────────┤
│  4. Supabase : RLS policies (isolation tenant + │
│     rôle + entité) — DERNIÈRE LIGNE DE DÉFENSE  │
└─────────────────────────────────────────────────┘
```

**Règle** : un bug à n'importe quel niveau est rattrapé par le niveau suivant.

### 5.2 RBAC — 4 rôles stockés dans `app.profiles.role`

| Rôle | Voit | Modifie |
|---|---|---|
| `super_admin` | Tout (cross-tenant en V2) | Users, entités, budgets, export |
| `admin` | Consolidé groupe + toutes filiales | Users de son tenant, budgets |
| `controleur` | Sa filiale (via `entite_id`) | Budget de sa filiale, commentaires |
| `consultant` | Sa filiale, lecture seule | Rien (export CSV uniquement) |

**Les rôles ne sont JAMAIS dans `auth.users.user_metadata`** (modifiable par user). Lus via helper `app.current_role()`.

### 5.3 RLS — pattern canonique

```sql
-- Policy simple : isolation par tenant
CREATE POLICY tenant_isolation ON marts.mart_compte_resultat
  FOR SELECT TO authenticated
  USING (tenant_id = (SELECT tenant_id FROM app.profiles WHERE id = auth.uid()));

-- Policy rôle + entité
CREATE POLICY role_and_entity ON marts.mart_compte_resultat
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM app.profiles p
      WHERE p.id = auth.uid()
        AND p.tenant_id = mart_compte_resultat.tenant_id
        AND (
          p.role IN ('super_admin', 'admin')            -- tout voir
          OR p.entite_id = mart_compte_resultat.entite_id  -- sa filiale
        )
    )
  );
```

### 5.4 Auth flow

```
1. User demande Magic Link sur /login
2. GoTrue envoie email (SMTP configuré : Brevo ou OVH)
3. User clique link → callback /auth/callback
4. Si rôle super_admin/admin : challenge MFA TOTP
5. Session JWT 8h (user) / 1h (admin) — enforced middleware
6. app.profiles.actif doit être true (nouveau user = false par défaut)
```

### 5.5 Audit trail
- Table `app.audit_log` append-only (trigger bloque UPDATE et DELETE)
- Logué : login, logout, export CSV, grant rôle, update budget, toute modif d'entité
- Colonnes : `tenant_id, user_id, action, target_type, target_id, payload, ip, user_agent, occurred_at`
- Rétention : 10 ans (obligation légale comptable, Art. L123-22 Code commerce)
- Partition mensuelle quand volume > 1M rows

## 6. Architecture frontend

### 6.1 Routage App Router

```
app/
├── (auth)/
│   ├── login/page.tsx              formulaire Magic Link
│   └── callback/route.ts           Auth callback
├── (app)/                          layout protégé (middleware)
│   ├── layout.tsx                  header, nav, user menu
│   ├── page.tsx                    home : 4 KPI cards
│   ├── etats-financiers/
│   │   ├── compte-resultat/
│   │   │   ├── page.tsx                    niveau 1 (rubriques)
│   │   │   ├── [rubrique]/page.tsx         niveau 2 (comptes)
│   │   │   └── [rubrique]/[compte]/page.tsx niveau 3 (écritures)
│   ├── activite/
│   │   ├── crd/page.tsx            CRD + drill-down
│   │   └── sig/page.tsx            9 soldes
│   ├── budget/
│   │   ├── page.tsx                table budgets
│   │   └── import/page.tsx         import CSV
│   ├── admin/
│   │   ├── users/page.tsx
│   │   └── entites/page.tsx
│   └── parametres/page.tsx         profil user
├── api/
│   ├── health/route.ts             healthcheck Coolify
│   ├── webhooks/
│   │   └── n8n/route.ts            webhook dbt trigger confirmation
│   └── export/csv/route.ts         export streaming
├── middleware.ts                    auth + session timeout
└── error.tsx / not-found.tsx / loading.tsx
```

### 6.2 Server vs Client Components

**Par défaut : Server.** `'use client'` uniquement si :
- State local interactif (filtres)
- Handlers DOM (`onClick`, `onChange`)
- TanStack Query (invalidation filtres dynamiques)
- TanStack Virtual (niveau 3)

**Mauvais réflexes à refuser** :
- `useState` pour stocker une donnée serveur → Server Component
- `useEffect` pour fetch au mount → Server Component + `await`
- `'use client'` sur un layout entier → extraire la partie interactive

### 6.3 Data fetching matrix

| Cas | Outil |
|---|---|
| Lecture mart dans page | Server Component + `createServerClient` + `await` |
| Mutation | Server Action + `revalidatePath` |
| Filtre interactif qui refetch | Server Action retournant JSON + TanStack Query |
| Tri/pagination client | TanStack Table |
| Virtualisation niveau 3 | TanStack Virtual |
| Temps réel | ❌ Hors MVP |

### 6.4 Formulaires

1 schema Zod = source de vérité, partagé client + serveur :
```typescript
// src/features/budget/schemas.ts
export const budgetImportSchema = z.object({
  entite_id: z.string().uuid(),
  exercice: z.number().int().min(2020).max(2040),
  montant_budget: z.number().nonnegative(),
});

// src/features/budget/server/actions.ts
'use server';
export async function importBudget(input: unknown) {
  const data = budgetImportSchema.parse(input);  // RE-validation serveur
  const supabase = createServerClient();
  const { error } = await supabase.from('budgets').insert(data);
  if (error) throw error;
  revalidatePath('/budget');
  await logAudit({ action: 'budget.import', payload: data });
}

// src/features/budget/components/ImportForm.tsx
const form = useForm<z.infer<typeof budgetImportSchema>>({
  resolver: zodResolver(budgetImportSchema),
});
```

## 7. Architecture backend

### 7.1 Schémas PostgreSQL — matrice d'accès

| Schéma | Rôle `n8n` | Rôle `dbt_runner` | Rôle `authenticated` | Rôle `service_role` |
|---|---|---|---|---|
| `raw.*` | R/W | R | — | R/W |
| `staging.*` | — | R/W | — | R |
| `marts.*` | — | R/W | R (RLS) | R/W |
| `app.*` | — | — | R/W (RLS) | R/W |
| `auth.*` (Supabase) | — | — | R (RLS) | R/W |

**Invariant** : aucun rôle DB applicatif n'a `BYPASSRLS`.

### 7.2 Communication Next.js ↔ Supabase

```
┌───────────────────────┐
│  Next.js Server       │
│  Component / Action   │
└────────┬──────────────┘
         │ uses
         ▼
┌───────────────────────────────────────────┐
│  src/lib/supabase/                        │
│  ├─ server.ts  createServerClient(cookies)│  → RLS appliquée selon session
│  ├─ client.ts  createBrowserClient()      │  → Client Components uniquement
│  └─ service.ts createServiceClient()      │  → Server seulement, JAMAIS bundlé
└────────┬──────────────────────────────────┘
         │
         ▼
┌───────────────────────┐
│  Kong gateway         │  routage + rate limit
└────────┬──────────────┘
         │
         ├──▶ GoTrue  (auth, JWT)
         ├──▶ PostgREST (auto REST sur Postgres)
         └──▶ Postgres direct (via Supabase client Postgres en Edge Functions)
```

### 7.3 Règles de choix : REST auto vs RPC vs Edge Function

| Besoin | Choix |
|---|---|
| Lecture mart simple (`select col from mart where ...`) | **REST auto** (PostgREST) + RLS |
| Agrégation multi-table, drill-down | **RPC** (`create function ... security invoker`) |
| Webhook externe, email, tâche `service_role` | **Edge Function** |
| Lecture mart | **Jamais** Edge Function (bypass le cache PostgREST) |

### 7.4 Abstraction DB — position tranchée
**Aucune couche d'abstraction** entre `src/features/*` et `@supabase/ssr`. Le SDK Supabase est lui-même la couche. Si on change de backend V2, c'est une réécriture ciblée feature par feature — et on le saura car un ADR sera requis.

(Le CDC §7.4 suggère `src/lib/db/*` comme abstraction — rejeté par ADR-0003, à rédiger.)

## 8. Architecture du monolithe

### 8.1 Découpage feature-based

```
src/
├── app/              Next.js App Router (routage, layouts, pages)
├── features/         code métier découpé par domaine
│   ├── compte-resultat/
│   ├── crd/
│   ├── sig/
│   ├── budget/
│   ├── admin/
│   └── kpi-home/
├── components/       UI générique (wrappers shadcn/Tremor)
│   ├── ui/           shadcn generated
│   └── charts/       wrappers Tremor
├── lib/
│   ├── supabase/     3 clients (server, client, service)
│   ├── auth/         requireUser, requireRole
│   ├── formatters/   euros, dates, periodes (Intl.NumberFormat FR)
│   ├── calculations/ fonctions financières pures (100% coverage)
│   │   ├── sig.ts
│   │   └── crd.ts
│   └── zod/          schemas partagés
└── e2e/              Playwright
```

### 8.2 Règles d'import (ESLint `no-restricted-imports`)

```
features/A ─X─▶ features/B       (interdit : passer par lib/)
features/*  ──▶ lib/              (autorisé)
features/*  ──▶ components/       (autorisé)
lib/        ─X─▶ features/*       (interdit)
components/ ─X─▶ features/*       (interdit)
components/ ─X─▶ lib/supabase/service (interdit : fuite service_role)
client-side ─X─▶ server-only code (marker `import 'server-only'`)
```

### 8.3 Promotion de code partagé — règle de 3
Une logique utilisée 1 fois reste locale. 2 fois : duplication tolérée. **3e occurrence** : promotion vers `lib/` ou `components/`.

## 9. Préparation multi-tenant (MVP mono-tenant)

### Invariants dès Sprint 1
- `tenant_id uuid NOT NULL` sur **toutes** les tables `app.*` et `marts.*`
- RLS active et policies avec filtre `tenant_id`
- Un seul tenant seed : `hma` (slug `hma`, plan `mvp`)
- Code **identique** à V2, seule la configuration change (cf. ADR-0004 à créer)

### Que faire ET ne pas faire MVP
**Faire** :
- Forcer `tenant_id` via colonne `GENERATED` ou default via trigger sur `app.*`
- Tester automatiquement : « user tenant A ne voit jamais tenant B » (1 test integration minimum)

**Ne pas faire** :
- Table `tenant_features` : OK à créer (pas de coût), mais tout flag lu `true` en MVP
- Onboarding formulaire `/signup` : V2
- Routing par sous-domaine : V2
- Facturation Stripe : V2

## 10. Décisions architecturales — pointeurs ADR

| ADR | Sujet | Statut | Résolution |
|---|---|---|---|
| ADR-0001 | Supabase self-hosted vs Cloud | À écrire | Self-hosted (Article 2) + désactiver 2 entrées Cloud Vaultwarden |
| ADR-0002 | Supabase Auth natif vs Authentik OIDC | À écrire | À trancher avec Kiki — reco default : Supabase natif MVP, Authentik V2 |
| ADR-0003 | Abstraction DB `src/lib/db/*` | À écrire | **Rejeté** — SDK Supabase est la couche |
| ADR-0004 | Outbox pattern en MVP | À écrire | **Reporté V2** — pas de coût MVP, pas d'IA MVP |
| ADR-0005 | Mapping entités Pennylane → `app.entites` | À écrire | 4 structures : HMA (holding), STIVMAT, STA (2 × transport), ETPA (agri) — confirmer usage métier avec Kiki |

## 11. Scalabilité — ce qui tient, ce qui casse

| Volume | Tient | Action préventive |
|---|---|---|
| 1 tenant (MVP) | Tout | — |
| 5 tenants, 10 user actifs/min | Tout | Monitoring Prometheus |
| 50 tenants, 100 user/min | Postgres solo + Next.js | Mesurer avant (cf. R8 CDC), upgrade VPS ou séparer Postgres |
| 500 tenants | ❌ | Sharding Postgres par tenant OU migration DB séparée par tenant — décision ADR V2+ |

**Bottleneck attendu** : writes sur `app.audit_log`. Partition mensuelle activable à 1M rows.

## 12. Évolution MVP → V1 → V2

### MVP → V1 (+3 mois)
- Ajouter schémas bilan (classes 1-5 PCG) : **pas** de refactor architecture, juste nouveaux marts
- Ajouter 26 ratios : nouveaux marts, Zod schemas
- Forecast simple : nouveau feature folder `features/forecast/`

### V1 → V2 (+6 mois)
- **Activation multi-tenant** : supprimer le garde-fou « 1 seul tenant actif »
- **Onboarding** `/signup` + Stripe + routing sous-domaine
- **IA V2** : worker Python FastAPI séparé + Qdrant (déjà déployé), réutilise les marts
- **Authentik SSO** (si ADR-0002 le retient V2)

### Strangler Fig — pas de big bang rewrite
Toute évolution majeure :
1. Nouvelle implémentation derrière flag
2. Routage partiel (par tenant ou route)
3. Parité testée
4. Bascule progressive
5. Retrait ancien code

## 13. Ce qu'on NE fera jamais

- ❌ Microservices avant 5 clients actifs
- ❌ Message queue (Kafka, RabbitMQ) MVP — Postgres NOTIFY suffit
- ❌ Cache Redis avant d'avoir mesuré une latence réelle
- ❌ GraphQL / tRPC — REST + Server Actions suffit
- ❌ Abstraction « au cas où on change de provider »
- ❌ Réécrire les calculs financiers à la fois en SQL ET en TS (une source de vérité)
- ❌ Exposer `service_role` au client
- ❌ Désactiver RLS « pour debugger »

---

*Architecture vivante. Modification = ADR dans `docs/adr/` + PR review + mise à jour de ce fichier.*
