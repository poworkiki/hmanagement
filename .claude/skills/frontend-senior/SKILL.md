---
name: frontend-senior
description: Patterns frontend senior hmanagement — Next.js 15 App Router, Server/Client Components, shadcn/ui + Tremor, TanStack Query/Table, React Hook Form + Zod, drill-down 3 niveaux, data fetching. Trigger pour toute question sur UI, composants, routing, layouts, formulaires, tables, graphiques, auth côté client, ou caching front.
---

# Frontend senior — hmanagement

## Règle d'or : Server Components par défaut
Un composant est Client **uniquement si** il utilise : state, effects, event handlers, browser APIs, ou un hook client (`useQuery`, `useForm`). Sinon, il reste serveur.

**Ordre de décision** avant `'use client'` :
1. Puis-je `await` la donnée dans le composant serveur ? → **Oui** : reste serveur
2. Ai-je besoin d'interactivité ponctuelle ? → extraire le bout interactif en Client, garder le parent serveur
3. Formulaire ? → Server Action + `useFormState` (pas de `useState` manuel)
4. Données qui changent en live côté user ? → Client + TanStack Query

**Interdit** : `'use client'` en haut d'un layout ou d'une page sans justification en commentaire.

## Data fetching — matrice de décision

| Cas | Outil |
|---|---|
| Lecture mart (CR, CRD, SIG) en page | Server Component + Supabase server client, `await` direct |
| Filtre interactif qui requête la DB | Server Action renvoyant JSON + TanStack Query côté Client |
| Table avec tri/pagination côté client | TanStack Table (data chargée serveur) |
| Données temps réel (jamais en MVP) | Supabase Realtime — exclu MVP |
| Mutation (budget, user invite) | Server Action + `revalidatePath` |

`TanStack Query` n'est **pas** un remplacement de Server Components — c'est un outil client pour interactivité, pas pour le chargement initial.

## Supabase clients (3 instances distinctes)

```ts
// lib/supabase/server.ts  → Server Components (cookies session)
// lib/supabase/client.ts  → Client Components (browser, anon key)
// lib/supabase/service.ts → Server Actions critiques uniquement, JAMAIS importé côté client
```

Créer une fonction `requireUser()` qui lance `redirect('/login')` si pas de session — à appeler en haut de chaque Server Component protégé.

## Formulaires : RHF + Zod + Server Action

Schema partagé client/serveur, validation **deux fois** :

```ts
// schema.ts — source de vérité
export const budgetSchema = z.object({ entite_id: z.string().uuid(), montant: z.number().nonnegative() });

// actions.ts — Server Action
'use server';
export async function createBudget(input: unknown) {
  const data = budgetSchema.parse(input); // revalidation côté serveur OBLIGATOIRE
  // ... + audit_log + revalidatePath
}

// form.tsx — Client
const form = useForm({ resolver: zodResolver(budgetSchema) });
```

**Ne jamais** faire confiance à la validation client seule. RLS en DB = 3e couche de défense.

## Tables & charts : shadcn + Tremor

- **Tableaux financiers** (CR, CRD ligne à ligne) → shadcn `<Table>` + TanStack Table pour tri/filter/export
- **KPI cards home (4 cartes)** → Tremor `<Card>` + `<Metric>` + `<BadgeDelta>` pour variation N-1
- **Graphiques** (évolution mensuelle) → Tremor `<AreaChart>` / `<BarChart>`
- **Montants** : formater via `Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' })` dans un util `formatEuros`

Pas de Chart.js, Recharts direct, ou autre lib UI hors shadcn/Tremor (Article 3.4 constitution).

## Drill-down 3 niveaux (pattern phare MVP)

Rubrique → Compte → Écriture. Implémentation App Router :

```
app/(app)/cr/page.tsx              → niveau 1 rubriques
app/(app)/cr/[rubrique]/page.tsx   → niveau 2 comptes
app/(app)/cr/[rubrique]/[compte]/page.tsx → niveau 3 écritures (lien Pennylane)
```

Chaque niveau est un Server Component qui lit un mart spécifique (`mart_cr_rubriques`, `mart_cr_comptes`, `mart_cr_ecritures`). Params typés via `z.object(...)`.parse(params) en haut de page.

## Loading & Error boundaries
- `loading.tsx` dans chaque dossier de route protégée → skeleton Tremor
- `error.tsx` dans chaque dossier → fallback + bouton retry + log vers audit
- `not-found.tsx` au niveau app pour routes invalides

## Caching Next.js 15
- `fetch` est **opt-in cache** par défaut depuis Next 15 — marquer explicitement : `{ cache: 'force-cache' }` pour marts froids, `{ cache: 'no-store' }` par défaut sinon
- `revalidatePath('/cr')` après toute mutation qui impacte CR
- Pas de `revalidate: N` aveugle sur data financière (cohérence > performance)

## Auth UX
- Magic Link (Article 4.3) — pas de mot de passe MVP
- MFA TOTP obligatoire pour `super_admin`/`admin` → composant enrôlement dédié
- Session timeout côté middleware (8h user, 1h admin) — `middleware.ts` vérifie `iat` du JWT

## Anti-patterns (refus systématique)
- ❌ `useState` pour stocker une donnée serveur (utiliser Server Component ou TanStack Query)
- ❌ `useEffect` pour fetcher au mount (jamais en App Router)
- ❌ `'use client'` sur un composant qui `await` — incompatible, extraire la partie interactive
- ❌ Formuler une valeur monétaire sans `formatEuros` (risques de locale)
- ❌ Valider uniquement côté client avant mutation
- ❌ Importer `supabase/service.ts` dans un fichier qui finit bundlé navigateur
- ❌ Appeler une Server Action sans `revalidatePath`/`revalidateTag` après mutation
- ❌ Typer `params` / `searchParams` avec `any` (toujours Zod-parse)
