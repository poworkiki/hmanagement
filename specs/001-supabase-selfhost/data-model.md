# Phase 1 — Data Model : Socle data self-hosted et souverain

**Feature** : `001-supabase-selfhost`
**Date** : 2026-04-22

Cette feature ne crée **aucun schéma applicatif** (`raw`, `staging`, `marts`, `app`). Ces schémas appartiennent à la feature suivante *`002-schemas-rls-bootstrap`*.

Le "data model" ici décrit **les entités de plateforme** — celles qui vivent dans la configuration de l'instance Supabase ou dans les systèmes périphériques (Vaultwarden, R2, Uptime Kuma). Les entités sont présentées telles qu'elles existent **après un déploiement propre**.

---

## 1. `PlatformUser` — Utilisateur de la plateforme

**Emplacement physique** : table `auth.users` de GoTrue (gérée par Supabase, non à créer).

**Attributs métier exposés** :

| Attribut | Type logique | Contrainte | Notes |
|---|---|---|---|
| `id` | UUID | PK, généré par GoTrue | Immuable |
| `email` | string | unique, non null | Seul canal de connexion (Magic Link) |
| `role` logique | enum | non null | `super_admin`, `admin`, `controleur`, `consultant` — stocké dans un **custom JWT claim** ou dans `app.profiles` à la feature suivante. **JAMAIS** dans `user_metadata` (Art. constitution 4 + CLAUDE.md `MUST NOT`). |
| `mfa_enrolled` | bool | non null | `true` dès la première complétion TOTP |
| `last_login_at` | timestamp | nullable | Maintenu par GoTrue |
| `created_at` | timestamp | non null | Auto |
| `is_active` | bool | non null, default `false` | Nouvel utilisateur **inactif par défaut** (Art. 4.1) |

**Invariants métier** :
- Un utilisateur avec `role ∈ {super_admin, admin}` **ne peut pas** avoir `mfa_enrolled = false` (enforcement côté app middleware + session GoTrue).
- Un utilisateur dont `is_active = false` ne doit pas pouvoir compléter une authentification.

**Transitions d'état** :

```
pending_invite ──(magic link cliqué)──▶ pending_mfa_setup
pending_mfa_setup ──(TOTP activé)────▶ active
active ──(révocation admin)──────────▶ disabled
disabled ──(réactivation admin)──────▶ active
```

Les deux premiers états sont implicites GoTrue ; le passage à `active` est matérialisé par `is_active = true` (feature suivante).

---

## 2. `ServiceAPIKey` — Clé API service

**Emplacement physique** : secrets Supabase (env var `SERVICE_ROLE_KEY`, `ANON_KEY`), pas de table dédiée en MVP.

**Attributs métier logiques** :

| Attribut | Type | Contrainte | Notes |
|---|---|---|---|
| `label` | string | unique | Ex : `n8n-pennylane-sync`, `dbt-cli` |
| `scope` | enum | non null | `anon` (RLS actif), `service_role` (bypass RLS — admin uniquement) |
| `status` | enum | non null | `active` / `revoked` |
| `rotated_at` | timestamp | non null | Dernière rotation |
| `issued_to` | string | nullable | Nom humain du consommateur |

**Invariants** :
- À la mise en service : exactement **2 clés actives** (`anon`, `service_role`). Aucune clé "personnalisée" créée ad hoc sans passer par une rotation documentée.
- Révocation = rotation globale (voir `research.md` R-008). Granularité fine reportée.

---

## 3. `PlatformBackup` — Sauvegarde de la plateforme

**Emplacement physique** : bucket Cloudflare R2 `hma-supabase-backups`, indexé par `restic`.

**Attributs métier** :

| Attribut | Type | Contrainte | Notes |
|---|---|---|---|
| `snapshot_id` | string | PK (géré par restic) | Hash immuable |
| `taken_at` | timestamp | non null | Début du `pg_dump` |
| `host` | string | non null | `supabase.hma.business` |
| `size_bytes` | int | non null | Après déduplication restic |
| `integrity_checksum` | string | non null | SHA-256 du dump avant chiffrement |
| `category` | enum | non null | `daily`, `monthly` (déterminé par la politique `forget`) |
| `tested_at` | timestamp | nullable | Horodatage du dernier drill de restauration exploité |

**Invariants** :
- `size_bytes > 0` (un dump vide = incident).
- Au moins **1 snapshot `daily` dans les 25 dernières heures** (alerte si absent).
- Au moins **1 snapshot `monthly` dans les 35 derniers jours**.
- `integrity_checksum` vérifié après restauration drill mensuelle.

**Transitions** :

```
created ──(restic store)──▶ stored
stored ──(drill mensuelle OK)──▶ verified
stored ──(rétention dépassée)──▶ forgotten (purgé par restic forget)
```

---

## 4. `PlatformSecret` — Secret de configuration

**Emplacement physique** : Vaultwarden org `stack_hma`. **Aucun stockage secondaire** dans le repo ou sur le VPS hors mémoire Docker.

**Attributs métier** :

| Attribut | Type | Contrainte | Notes |
|---|---|---|---|
| `id` logique | string | PK | Préfixe `supabase-selfhost-*` |
| `category` | enum | non null | `jwt`, `db_password`, `smtp`, `r2_access`, `r2_secret`, `restic_password`, `admin_api` |
| `last_rotated_at` | timestamp | non null | |
| `rotation_policy` | enum | non null | `quarterly` (jwt, service_role), `annual` (autres), `on_incident` (toujours applicable) |
| `fingerprint` | string | non null, unique | Hash non-réversible de la valeur (pour détecter rotation sans stocker la valeur) |

**Inventaire canonique (contrat env — voir `contracts/platform-env-contract.md`)** :

| `id` Vaultwarden | Injecté dans | Rotation |
|---|---|---|
| `supabase-selfhost-jwt-secret` | `JWT_SECRET` GoTrue + PostgREST | trimestrielle |
| `supabase-selfhost-service-role-key` | `SERVICE_ROLE_KEY` | trimestrielle (dérivée JWT) |
| `supabase-selfhost-anon-key` | `ANON_KEY` | trimestrielle (dérivée JWT) |
| `supabase-selfhost-postgres-password` | `POSTGRES_PASSWORD` | annuelle ou incident |
| `supabase-selfhost-dashboard-password` | Studio admin password | annuelle |
| `supabase-selfhost-smtp-host` | `GOTRUE_SMTP_HOST` | fixe (changement provider) |
| `supabase-selfhost-smtp-user` | `GOTRUE_SMTP_USER` | fixe |
| `supabase-selfhost-smtp-pass` | `GOTRUE_SMTP_PASS` | annuelle ou incident |
| `supabase-selfhost-r2-access-key-id` | Script backup | annuelle |
| `supabase-selfhost-r2-secret-access-key` | Script backup | annuelle |
| `supabase-selfhost-restic-password` | Script backup | annuelle ou incident |
| `supabase-selfhost-telegram-webhook-url` | Monitoring / notifs | annuelle |

**Invariants** :
- `fingerprint` **doit changer** à chaque incrément de `last_rotated_at` (vérification manuelle au runbook rotation).
- Aucun secret ne doit apparaître dans les logs (vérification par `grep` dans les logs Coolify au moment de la clôture de la feature — SC-007).

---

## 5. `AuthEvent` — Événement d'authentification

**Emplacement physique** : logs GoTrue (stdout → agrégation Coolify), rétention 7 jours. Persistence long terme reportée à la feature `observability-stack` ultérieure.

**Attributs métier** :

| Attribut | Type | Notes |
|---|---|---|
| `occurred_at` | timestamp | Précision seconde |
| `user_id` | UUID / null | `null` si échec avant identification |
| `event_type` | enum | `magic_link_requested`, `magic_link_consumed`, `mfa_setup`, `mfa_challenge_ok`, `mfa_challenge_fail`, `login_success`, `login_fail`, `logout`, `session_expired`, `rate_limit_triggered` |
| `client_ip` | string | Champ `X-Real-IP` derrière CF |
| `details` | JSON | Rate-limiter cause, user-agent, etc. |

**Utilisation MVP** :
- Consultable par le super-admin via Coolify UI pour audit ponctuel (FR-023).
- Base future pour une table `app.audit_log` persistée (feature suivante), avec transformation dbt possible ultérieurement.

---

## Relations

```
PlatformUser  ──(1..N)──▶  AuthEvent
PlatformUser  ──(0..N)──▶  (session JWT en cours — non modélisée, géré par GoTrue)
PlatformSecret ──(1..1)──▶ Injecté dans 1 variable env Coolify
PlatformBackup ──(1..1)──▶ Protège état global PostgreSQL
ServiceAPIKey  ──(1..1)──▶ Référence un PlatformSecret (jwt)
```

---

## Schémas / objets DB introduits par cette feature

| Objet | Créé ici ? | Feature qui le crée |
|---|---|---|
| Cluster PostgreSQL 15 + DB `postgres` | ✅ | `001-supabase-selfhost` (template Coolify) |
| Extensions PG (`pgcrypto`, `uuid-ossp`, `pgjwt`, `pg_stat_statements`) | ✅ | `001-supabase-selfhost` (image Supabase les inclut) |
| Rôles DB par défaut (`postgres`, `anon`, `authenticated`, `service_role`) | ✅ | Fournis par image Supabase |
| Schéma `auth.*` (GoTrue) | ✅ | Fournis par image Supabase |
| Schémas `raw.*`, `staging.*`, `marts.*`, `app.*` | ❌ | `002-schemas-rls-bootstrap` |
| Rôles DB applicatifs (`hm_reader`, `hm_writer`, etc.) sans `BYPASSRLS` | ❌ | `002-schemas-rls-bootstrap` |
| Tables `app.tenants`, `app.profiles`, `app.audit_log` | ❌ | `002-schemas-rls-bootstrap` |
| Policies RLS | ❌ | `002-schemas-rls-bootstrap` |

Cette séparation nette est **volontaire** (cohérente avec Art. 7.4 séparation des responsabilités) et facilite le tests indépendant de chaque feature.

---

**Phase 1 data-model terminée.** Voir ensuite `contracts/` pour les surfaces exposées.
