# Runbook — Déploiement initial Supabase self-hosted

- **Couverture** : User Stories 1 & 2, FR-001 à FR-013
- **Durée estimée** : 60-90 min pour un premier déploiement propre
- **Statut actuel** : **squelette** — sera enrichi après le 1er déploiement réel avec les vraies douleurs rencontrées (T035 puis T144)

> ⚠️ Cette procédure suppose que les pré-requis de la Phase 2 "Foundational" de
> [`tasks.md`](../../specs/001-supabase-selfhost/tasks.md) sont tous complétés :
> DNS T010, R2 T011-T013, Brevo T014-T017, 12 secrets Vaultwarden T018-T023, canal Telegram T024-T025.

## Phase 0 — Vérifications pré-déploiement

```bash
# Résolution DNS
dig supabase.hma.business +short
# → doit renvoyer 187.124.150.82

# Connexion VPS
ssh hma 'uptime && df -h | head -3'

# État Coolify
curl -I https://coolify.hma.business
# → doit renvoyer 200 ou 302
```

- [ ] Les 12 secrets `supabase-selfhost-*` existent dans Vaultwarden
- [ ] Bucket R2 `hma-supabase-backups` créé avec API key active
- [ ] Brevo SMTP accessible, domaine `hma.business` vérifié (SPF/DKIM/DMARC verts)
- [ ] Canal Telegram ops configuré, bot `hmagents_bot` membre

## Phase 1 — Création de l'app Supabase dans Coolify

1. Ouvrir `https://coolify.hma.business`.
2. **Resources → + New → Service** → template **"Supabase"**.
3. **Nom** : `supabase-hma`.

## Phase 2 — Configuration des domaines et TLS

1. Onglet **Domains** → Add domain : `supabase.hma.business`.
2. **Generate HTTPS** activé (Let's Encrypt via Traefik).
3. Attendre quelques secondes que Traefik enregistre le domaine.

## Phase 3 — Environment Variables

Coller toutes les variables listées dans [`infra/supabase/env.reference`](../../infra/supabase/env.reference) **publiques** + les **secrets** depuis Vaultwarden (voir [`contracts/platform-env-contract.md`](../../specs/001-supabase-selfhost/contracts/platform-env-contract.md)).

**Marquer chaque secret comme "Masked"** dans l'UI Coolify.

Vérifications rapides :
- `GOTRUE_SITE_URL=https://supabase.hma.business` (pas de trailing slash)
- `POSTGRES_PASSWORD` ≥ 32 caractères, pas de caractères problématiques (éviter `$`, `"`, `\` si possible)
- `JWT_SECRET` ≥ 40 caractères hex

## Phase 4 — Volumes persistants

Onglet **Volumes** :
- [ ] `/var/lib/postgresql/data` → volume `supabase-db-data` (persistant)
- [ ] `/var/lib/storage` → volume persistant pour Supabase Storage

## Phase 5 — Deploy

1. Cliquer **Deploy**.
2. Surveiller les logs Coolify en temps réel.
3. Attendre que tous les conteneurs passent `Healthy` (3-5 min typique).

Conteneurs attendus : `postgres`, `gotrue`, `postgrest`, `storage`, `realtime`, `studio`, `meta`, `kong` ou `traefik-route`.

## Phase 6 — Vérifications post-deploy

```bash
# 1. Depuis un poste extérieur
curl -I https://supabase.hma.business/
# → 200, cadenas HTTPS valide

curl -fsS https://supabase.hma.business/auth/v1/health
# → {"version":"...", "name":"GoTrue", ...}

# 2. Depuis le VPS
ssh hma 'docker ps --filter name=supabase --format "table {{.Names}}\t{{.Status}}"'
```

## Phase 7 — Premier compte super-admin MFA

1. Supabase Studio → `https://supabase.hma.business/` → login `admin` + `DASHBOARD_PASSWORD`.
2. **Authentication → Users → Invite user** → email cible super-admin.
3. Consulter la boîte mail (délai < 60 s), cliquer le Magic Link.
4. Configurer TOTP au premier login (QR code → app auth → code à 6 chiffres).
5. Confirmer dans Studio que le compte est créé avec MFA activé.

## Phase 8 — Activer les backups

Voir [`infra/supabase/backups/README.md`](../../infra/supabase/backups/README.md).

Résumé condensé :
```bash
ssh hma
sudo apt-get install -y restic
# installer /etc/supabase-backup/env (chmod 600)
# copier les scripts et la cron
sudo /usr/local/bin/pg-backup.sh --first-run
```

## Phase 9 — Activer le monitoring

Voir `infra/supabase/monitoring/uptime-kuma-probes.yaml` pour les 4 sondes à créer dans Uptime Kuma.

- [ ] Probe `supabase-studio` ajoutée
- [ ] Probe `supabase-auth` ajoutée
- [ ] Probe `supabase-rest` ajoutée
- [ ] Probe certificat TLS ajoutée
- [ ] `disk-alert.sh` installé + entrée cron

## Pièges à documenter (à enrichir au fil des déploiements)

> Section à compléter après chaque déploiement réel avec les vraies surprises rencontrées.

- _(à remplir lors du 1er deploy)_

## Rollback

En cas d'incident pendant le déploiement initial :
1. Coolify UI → app `supabase-hma` → **Stop**
2. Si nécessaire, **Delete** (⚠️ détruit le volume PG) → on accepte la perte au 1er deploy car pas de données encore
3. Reprendre à la Phase 3 (env vars) après investigation

## Sortie attendue

- `https://supabase.hma.business` HTTPS cadenas vert
- Au moins 1 compte super-admin avec MFA TOTP actif
- 1er backup R2 présent (taille > 0)
- 1er drill de restauration réussi
- 4 probes Uptime Kuma en état "Up"
- 0 secret en clair dans le repo (audit `grep` SC-007)
