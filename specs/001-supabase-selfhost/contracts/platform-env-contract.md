# Contract — Variables d'environnement & secrets de plateforme

**Feature** : `001-supabase-selfhost`
**Date** : 2026-04-22
**Nature du contrat** : chaque déploiement de l'application Supabase dans Coolify **MUST** renseigner exactement les variables listées ci-dessous, avec la source mentionnée. Toute variable manquante empêche le démarrage ou l'opération conforme.

Source = **Vaultwarden** (`vaultwarden.poworkiki.cloud`, org `stack_hma`), sauf mention `public`.

> **Règle de lecture** : ✅ = secret (masqué dans Coolify, jamais en log) · 📄 = public (valeur constante documentée).

---

## 1. PostgreSQL

| Variable env | Source Vaultwarden | Type | Notes |
|---|---|---|---|
| `POSTGRES_PASSWORD` | `supabase-selfhost-postgres-password` | ✅ | ≥ 32 chars, alphanum + symboles |
| `POSTGRES_DB` | *(valeur fixe)* | 📄 | `postgres` |
| `POSTGRES_PORT` | *(valeur fixe)* | 📄 | `5432` (exposition interne Docker uniquement) |

## 2. JWT & API Keys

| Variable env | Source Vaultwarden | Type | Notes |
|---|---|---|---|
| `JWT_SECRET` | `supabase-selfhost-jwt-secret` | ✅ | ≥ 40 chars aléatoires |
| `ANON_KEY` | `supabase-selfhost-anon-key` | ✅ | JWT signé avec `JWT_SECRET`, `role=anon` |
| `SERVICE_ROLE_KEY` | `supabase-selfhost-service-role-key` | ✅ | JWT signé, `role=service_role`, usage admin uniquement |
| `JWT_EXPIRY` | *(valeur fixe)* | 📄 | `3600` (1 h) |

## 3. GoTrue (authentification)

| Variable env | Source | Type | Notes |
|---|---|---|---|
| `GOTRUE_SITE_URL` | *(valeur fixe)* | 📄 | `https://supabase.hma.business` |
| `GOTRUE_API_EXTERNAL_URL` | *(valeur fixe)* | 📄 | `https://supabase.hma.business/auth/v1` |
| `GOTRUE_JWT_EXP` | *(valeur fixe)* | 📄 | `3600` |
| `GOTRUE_MFA_ENABLED` | *(valeur fixe)* | 📄 | `true` |
| `GOTRUE_SECURITY_PASSWORDS_HIBP_ENABLED` | *(valeur fixe)* | 📄 | `true` |
| `GOTRUE_DISABLE_SIGNUP` | *(valeur fixe)* | 📄 | `true` (pas d'auto-inscription) |
| `GOTRUE_MAILER_AUTOCONFIRM` | *(valeur fixe)* | 📄 | `false` |
| `GOTRUE_RATE_LIMIT_EMAIL_SENT` | *(valeur fixe)* | 📄 | `10` / heure / IP — rate-limit **émission** Magic Link (FR-013) |
| `GOTRUE_OTP_EXP` | *(valeur fixe)* | 📄 | `900` (15 min) — Magic Link expire après 15 min d'inactivité (FR-009) |
| `GOTRUE_RATE_LIMIT_VERIFY` | *(valeur fixe)* | 📄 | `30` / heure / IP — rate-limit **vérifications** Magic Link / OTP (anti brute-force, FR-013) |
| `GOTRUE_RATE_LIMIT_TOKEN_REFRESH` | *(valeur fixe)* | 📄 | `150` / heure / IP — rate-limit rafraîchissement JWT (FR-013) |

> **Note importante** : les noms exacts des variables GoTrue ci-dessus peuvent varier selon la version livrée par le template Supabase Coolify (ex. `GOTRUE_MAILER_OTP_EXP` vs `GOTRUE_OTP_EXP`). **Vérifier au déploiement** contre la documentation de la version utilisée (T050) et ajuster les noms dans `infra/supabase/gotrue-config-overrides.yml`. L'**intention** (TTL 15 min + rate-limit verify/refresh) reste la source de vérité.

## 4. SMTP (livraison des magic links)

| Variable env | Source Vaultwarden | Type | Notes |
|---|---|---|---|
| `GOTRUE_SMTP_HOST` | `supabase-selfhost-smtp-host` | ✅ | ex : `smtp-relay.brevo.com` |
| `GOTRUE_SMTP_PORT` | *(valeur fixe)* | 📄 | `587` |
| `GOTRUE_SMTP_USER` | `supabase-selfhost-smtp-user` | ✅ | |
| `GOTRUE_SMTP_PASS` | `supabase-selfhost-smtp-pass` | ✅ | |
| `GOTRUE_SMTP_ADMIN_EMAIL` | *(valeur fixe)* | 📄 | `no-reply@hma.business` |
| `GOTRUE_SMTP_SENDER_NAME` | *(valeur fixe)* | 📄 | `hmanagement` |

## 5. Supabase Studio

| Variable env | Source Vaultwarden | Type | Notes |
|---|---|---|---|
| `DASHBOARD_USERNAME` | *(valeur fixe)* | 📄 | `admin` |
| `DASHBOARD_PASSWORD` | `supabase-selfhost-dashboard-password` | ✅ | ≥ 24 chars |

## 6. Sauvegardes (utilisées par les scripts cron, pas directement par Supabase)

| Variable env | Source Vaultwarden | Type | Notes |
|---|---|---|---|
| `R2_ACCOUNT_ID` | `supabase-selfhost-r2-account-id` | ✅ | Account Cloudflare |
| `R2_ACCESS_KEY_ID` | `supabase-selfhost-r2-access-key-id` | ✅ | Scope : `hma-supabase-backups` uniquement |
| `R2_SECRET_ACCESS_KEY` | `supabase-selfhost-r2-secret-access-key` | ✅ | |
| `R2_BUCKET` | *(valeur fixe)* | 📄 | `hma-supabase-backups` |
| `RESTIC_REPOSITORY` | *(valeur dérivée)* | 📄 | `s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/hma-supabase-backups` |
| `RESTIC_PASSWORD` | `supabase-selfhost-restic-password` | ✅ | Clé de chiffrement des backups |

## 7. Notifications

| Variable env | Source Vaultwarden | Type | Notes |
|---|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `Telegram Bot — HMAGENTS` (secret existant) | ✅ | Déjà présent, réutilisé |
| `TELEGRAM_CHAT_ID_OPS` | *(à créer)* | 📄 | Chat ID destiné aux alertes supabase |

---

## Règles générales

- Aucune variable marquée ✅ ne doit apparaître dans : repo Git, logs Coolify, logs conteneurs, backups restic **déchiffrés**. Vérification SC-007 au moment de la clôture.
- Toute modification d'une variable ✅ passe par le runbook `docs/runbooks/supabase-secret-rotation.md` et incrémente `last_rotated_at` dans Vaultwarden.
- Les variables 📄 peuvent être versionnées (dans `infra/supabase/env.reference`) avec des valeurs finales ou des placeholders explicites — jamais mélangées avec des valeurs ✅.

## Acceptance

Le contrat est considéré satisfait si :
1. Les **12 secrets** Vaultwarden préfixés `supabase-selfhost-*` existent et contiennent une valeur non vide,
2. L'application Supabase déployée sur Coolify liste **0 variable vide** dans sa section env,
3. Un `grep -RIn "SERVICE_ROLE_KEY\|JWT_SECRET\|POSTGRES_PASSWORD" infra/ docs/` ne renvoie **que** des références à des noms de variables, jamais de valeurs.
