---
name: architecture-senior
description: Décisions architecturales senior hmanagement — ELT 4 schémas, Majestic Monolith, multi-tenant-ready, Strangler Fig, KISS/YAGNI/DRY, décisions réversibles vs ADR, North Star Metric. Trigger pour toute question de design d'ensemble, choix de stack, frontière entre couches, scope MVP vs V1/V2, ou évolution architecturale.
---

# Architecture senior — hmanagement

## Frame de décision en 4 questions
Avant toute proposition d'architecture, se poser :

1. **Sert la North Star Metric** (clôture Pennylane → décision < 30s) ? Si non : reporter.
2. **Dans le scope MVP** (CR + CRD + SIG + KPI home + admin + import/export CSV) ? Si non : flag explicite « hors MVP, Article 11.4 ».
3. **Réversible** (refactor facile plus tard) ou **irréversible** (schéma DB, stack majeure) ? Si irréversible : ADR obligatoire dans `docs/adr/`.
4. **Conforme constitution** (Articles 1–12) ? Lister l'article référencé dans la réponse.

## Paradigme ELT (pas ETL) — frontière stricte
```
Pennylane ──(n8n)──▶ raw.*  ──(dbt)──▶ staging.*  ──(dbt)──▶ marts.*  ──(Next.js)──▶ UI
                     JSONB            nettoyage              analytics     RLS
```

**Interdits absolus** :
- Transformation métier dans n8n (seulement transport + idempotence)
- Jointure dans staging (seulement nettoyage 1:1)
- Lecture de `raw`/`staging` depuis Next.js (contournement RLS)
- Calcul financier côté front **ET** côté DB sans source unique de vérité

**Règle** : une formule financière vit à **un seul endroit** — soit en mart dbt (si purement SQL), soit en fonction TS testée 100% (si logique conditionnelle complexe). Jamais les deux.

## Multi-tenant-ready en MVP mono-tenant

**Invariant** : `tenant_id uuid NOT NULL` sur **toutes** les tables `app.*` et `marts.*`, RLS active dès Sprint 1, un seul tenant `hma` inséré au seed.

**Bénéfice** : le pivot V2 ne demande **aucun refactor SQL**, uniquement l'ouverture de la création de tenants via l'UI admin.

**Piège** : ne pas croire qu'on peut « ajouter `tenant_id` plus tard ». C'est techniquement possible mais oblige à rétro-patcher toutes les policies, tous les mart dbt, tout le code de fetch. **Dès le Sprint 1, non négociable.**

## Majestic Monolith — quand NE PAS splitter

Un monolithe Next.js bien structuré suffit pour le MVP **et** pour 50+ tenants. Triggers pour discuter un split :
- Workloads CPU très différents (ex: forecast ML) → Edge Function ou worker dédié
- Besoin d'un SLA différent (ex: webhook Pennylane temps réel vs rapports batch)
- Équipe > 5 devs sur la même zone

**Avant le split** : mesurer (pas intuition), proposer un ADR, garder la porte de sortie Strangler Fig.

## Strangler Fig pour évolutions majeures
Toute réécriture suit ce pattern :
1. Introduire la nouvelle implémentation derrière un flag/feature toggle
2. Router un sous-ensemble de trafic (par tenant, par route, par user)
3. Mesurer parité (tests de comparaison outputs)
4. Basculer progressivement, retirer l'ancien code par morceaux
5. **Jamais** big-bang rewrite (Article 11.1)

## KISS / YAGNI / DRY appliqués

| Principe | Application hmanagement |
|---|---|
| KISS | Pas de micro-services, pas de message queue, pas de cache Redis en MVP |
| YAGNI | Pas de forecast, pas d'IA, pas de multi-devises tant que HMA n'en a pas besoin |
| DRY (modéré) | Factoriser formules financières, **pas** le schéma des formulaires ni les types Zod (ok de dupliquer si la divergence future est probable) |

Signal d'alerte : si ajouter une feature demande de modifier > 5 fichiers dans > 3 couches, l'abstraction est probablement cassée — revoir avant de coder.

## Décisions réversibles vs irréversibles

**Réversibles** (prendre vite, itérer) :
- Choix d'un composant UI shadcn/Tremor
- Nommage d'une route
- Structure interne d'un feature folder

**Irréversibles** (ADR obligatoire) :
- Schéma DB (colonnes, contraintes, types)
- Choix d'un tiers payant (APIs externes, SaaS)
- Découpage multi-tenant
- Format des exports CSV (contrat avec utilisateurs)

ADR format : `docs/adr/NNNN-titre.md` avec sections **Contexte, Décision, Conséquences, Alternatives rejetées**. Un ADR périmé passe en `Superseded: ADR-XXXX`, jamais supprimé.

## Frontières de modules (feature-based)

```
src/features/
├── compte-resultat/   (CR standard PCG)
├── crd/               (compte de résultat différentiel)
├── sig/               (soldes intermédiaires de gestion)
├── admin/             (users, entités, tenants)
├── budget/            (import CSV + édition)
└── kpi-home/          (4 cartes)
src/lib/        → clients partagés (supabase, formatters, auth helpers)
src/components/ → UI génériques shadcn/tremor wrappers
```

**Règle d'import** : une feature peut importer `lib/` et `components/`, **jamais** une autre feature. Si deux features partagent de la logique, promouvoir vers `lib/` — mais seulement à la 3e occurrence (règle de 3).

## North Star Metric alignment
Toute décision produit/archi passe le test : *« Cela réduit-il le temps clôture Pennylane → décision ? »*. Si neutre ou négatif : pas MVP.

Exemples :
- ✅ Drill-down 3 niveaux : **oui** (évite d'ouvrir Pennylane)
- ✅ Import budget CSV : **oui** (pas d'outil externe)
- ❌ Éditeur WYSIWYG de rapports : **non** (hors North Star)
- ❌ Thème sombre MVP : **non** (neutre)

## Anti-patterns architecturaux (refus)
- ❌ Partager une table entre tenants sans `tenant_id` « parce qu'elle est statique » (dim_entites par ex.)
- ❌ Logique métier dans un trigger DB invisible (préférer fonction dbt ou TS testée)
- ❌ Cache en amont de la DB avant d'avoir mesuré une latence réelle
- ❌ GraphQL / tRPC / nouveau protocole sans justification mesurée (REST PostgREST + Server Actions suffit)
- ❌ Abstraire une couche « au cas où on change de backend » (YAGNI)
- ❌ Ajouter un service externe (Sentry, Segment, etc.) sans vérifier RGPD + souveraineté (Article 2)
- ❌ Décision irréversible sans ADR
