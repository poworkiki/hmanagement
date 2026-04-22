---
name: backend-senior
description: Patterns backend senior hmanagement — Supabase self-hosted, RLS multi-tenant, PostgreSQL, dbt Core, intégration n8n/Pennylane. Trigger pour toute question touchant DB, RLS, policies, schémas (raw/staging/marts/app), migrations, Edge Functions, RPC, audit log, rôles DB, ou pipeline ELT.
---

# Backend senior — hmanagement

## Règle d'or : RLS multi-tenant systématique
Toute table `marts.*` et `app.*` porte `tenant_id uuid NOT NULL references app.tenants(id)`. Policy template :

```sql
create policy "tenant_isolation" on app.<table>
  for all to authenticated
  using  (tenant_id = (select tenant_id from app.profiles where id = auth.uid()))
  with check (tenant_id = (select tenant_id from app.profiles where id = auth.uid()));
```

**JAMAIS** `BYPASSRLS` sur le rôle applicatif. Le `service_role` ne sort **jamais** du backend (n8n, Edge Functions, jobs dbt).

## Schémas — matrice d'accès

| Schéma | Écrit | Lit | Notes |
|---|---|---|---|
| `raw.*` | n8n (service_role) | dbt | JSONB brut, append-only, jamais exposé à Next.js |
| `staging.*` | dbt | dbt | Nettoyage uniquement, aucune logique métier |
| `marts.*` | dbt | Next.js (lecture) | RLS active, views ou tables incrémentales |
| `app.*` | Next.js | Next.js | Auth, profiles, entités, budgets, audit_log |

`GRANT`/`REVOKE` explicites par rôle DB. Le rôle `authenticated` n'a **aucun** droit direct sur `raw`/`staging`.

## RBAC dans la DB (pas user_metadata)
Rôles stockés dans `app.profiles.role` avec check constraint — **jamais** `auth.users.user_metadata` (modifiable par user). Helper :

```sql
create or replace function app.current_role() returns text
  language sql stable security definer set search_path = app
as $$ select role from app.profiles where id = auth.uid(); $$;
```

Utilisation : `using (app.current_role() in ('super_admin','admin'))`.

## Audit log immuable
Trigger bloqueur UPDATE + DELETE sur `app.audit_log` :

```sql
create or replace function app.reject_mutation() returns trigger
  language plpgsql as $$ begin raise exception 'audit_log immuable'; end; $$;
create trigger audit_no_update before update on app.audit_log
  for each row execute function app.reject_mutation();
create trigger audit_no_delete before delete on app.audit_log
  for each row execute function app.reject_mutation();
```

Logger via trigger AFTER INSERT/UPDATE sur tables sensibles. Partitionner par mois si volume > 1M lignes.

## dbt — patterns non négociables

**Sources** (`_sources.yml`) : freshness obligatoire sur Pennylane (`warn_after: {count: 24, period: hour}`).

**Modèles** :
- `stg_<source>__<entité>.sql` : 1:1 avec la source, convertit centimes→euros, caste dates, **aucune jointure**
- `int_*` : jointures intermédiaires, logique métier réutilisable
- `mart_*` / `dim_*` / `fct_*` : surface exposée à l'app

**Tests minimum par mart** (3 catégories, Article 6.3 constitution) :
```yaml
- not_null: [tenant_id, periode, entite_id]
- relationships: entite_id → dim_entites.id
- dbt_utils.expression_is_true: chiffre_affaires_ht >= 0
```

**Materialization** :
- staging/intermediate → `view`
- marts lourds (CR, CRD, SIG) → `incremental`, `unique_key=['tenant_id','entite_id','periode']`, `on_schema_change='fail'`

**Interdits** : `select *` en mart, jointure sans `on`, logique métier en staging, référencer un mart depuis un mart (créer un `int_`).

## Conversion Pennylane (centimes → euros)
Toujours en staging via macro, jamais dupliquée :

```sql
{% macro cents_to_euros(col) %}
  ({{ col }}::numeric / 100.0)::numeric(18,2)
{% endmacro %}
```

## Migrations Supabase
- 1 migration = 1 changement atomique, nommage `YYYYMMDDHHMM_<verb>_<objet>.sql`
- **Toujours réversible** : `up` ET `down` testés en local
- Les **policies RLS vivent dans les migrations**, pas dans dbt
- Valider `supabase db diff` avant push

## Edge Functions vs RPC vs REST auto

| Besoin | Choix |
|---|---|
| Lecture mart simple | REST auto (PostgREST) + RLS |
| Agrégation complexe, drill-down | RPC `security invoker` (hérite RLS appelant) |
| Webhook externe, envoi email, job service_role | Edge Function |
| Lecture mart | **JAMAIS** Edge Function — passer par REST + RLS |

## Intégration n8n / Pennylane
- Workflows poussent dans `raw.*` via `service_role` (env Coolify, jamais hardcodé)
- Chaque workflow termine par un **webhook Discord** (succès ET échec, Article 10.1)
- Idempotence via clé `(source, source_id, synced_at)` pour déduper
- Trigger dbt : `dbt run --select state:modified+` après sync raw
- Montants Pennylane en centimes (×100) — conversion en staging uniquement

## Anti-patterns (refus systématique)
- ❌ Filtrer par tenant uniquement côté Next.js
- ❌ `select * from marts.*` dans du code front
- ❌ Stocker le rôle dans `user_metadata`
- ❌ Calcul financier en SQL dans un composant (doit être mart OU fonction TS 100% testée)
- ❌ `security definer` sans `set search_path = ...` (injection de schéma)
- ❌ Modifier `raw.*` depuis autre chose que n8n
- ❌ Exposer `service_role` au client (jamais en `NEXT_PUBLIC_*`)
