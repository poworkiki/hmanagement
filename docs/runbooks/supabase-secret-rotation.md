# Runbook — Rotation des secrets Supabase

Procédure de rotation des 12 secrets `supabase-selfhost-*` de Vaultwarden.

- **Couverture** : FR-012, SC-008, Art. constitution 4.5
- **Périodicité** :
  - **Trimestrielle** : `jwt-secret`, `anon-key`, `service-role-key` (les 3 sont liés, tournent ensemble)
  - **Annuelle** : `postgres-password`, `dashboard-password`, `smtp-*`, `r2-*`, `restic-password`
  - **Immédiate** : tout secret suspecté compromis

## Tableau de planification

| Secret | Cadence | Dernière rotation | Prochaine échéance |
|---|---|---|---|
| `supabase-selfhost-jwt-secret` | trimestrielle | _(à remplir au 1er déploiement)_ | |
| `supabase-selfhost-anon-key` | trimestrielle (liée JWT) | | |
| `supabase-selfhost-service-role-key` | trimestrielle (liée JWT) | | |
| `supabase-selfhost-postgres-password` | annuelle | | |
| `supabase-selfhost-dashboard-password` | annuelle | | |
| ~~`supabase-selfhost-smtp-*`~~ | ~~annuelle~~ | N/A — **supprimés /speckit-clarify 2026-04-22** (auth déléguée Authentik) | |
| `supabase-selfhost-oidc-client-id` | sur recréation app Authentik | | |
| `supabase-selfhost-oidc-client-secret` | annuelle ou immédiat sur incident | | Rotate via Authentik UI → regenerate secret |
| `supabase-selfhost-r2-account-id` | fixe (lié au compte CF) | | |
| `supabase-selfhost-r2-access-key-id` | annuelle | | |
| `supabase-selfhost-r2-secret-access-key` | annuelle | | |
| `supabase-selfhost-restic-password` | **jamais rotation simple** — voir section dédiée | | |

## Procédure : rotation trimestrielle JWT + clés dérivées

⚠️ **Impact utilisateur** : invalidation de toutes les sessions utilisateurs actives → tout le monde doit se reconnecter. Impact acceptable (MVP = peu d'utilisateurs, reconnexion < 2 min).

⚠️ **Impact intégrations** : toute clé `SERVICE_ROLE_KEY` / `ANON_KEY` cachée dans n8n, scripts, app doit être mise à jour **en parallèle** — sinon les intégrations cassent.

### Étapes

1. **Générer les nouvelles valeurs** :
   ```bash
   # Nouveau JWT_SECRET
   NEW_JWT_SECRET=$(openssl rand -hex 32)
   echo "$NEW_JWT_SECRET"

   # Signer les nouvelles ANON_KEY et SERVICE_ROLE_KEY
   # → utiliser l'outil Supabase CLI ou un script custom qui crée les JWT
   # → claims : { "role": "anon" | "service_role", "iss": "supabase", "iat": now, "exp": far_future }
   ```
2. **Mettre à jour Vaultwarden** (via UI `vaultwarden.poworkiki.cloud`) :
   - Éditer `supabase-selfhost-jwt-secret` → valeur
   - Éditer `supabase-selfhost-anon-key` → valeur
   - Éditer `supabase-selfhost-service-role-key` → valeur
   - Consigner `last_rotated_at` dans les notes
3. **Mettre à jour Coolify UI** → app `supabase-hma` → Environment Variables :
   - Remplacer les 3 valeurs `JWT_SECRET`, `ANON_KEY`, `SERVICE_ROLE_KEY`
4. **Redéployer** : Coolify UI → bouton **Restart** (pas Deploy, plus rapide).
5. **Mettre à jour les consommateurs** :
   - n8n : workflows qui utilisent Supabase → remplacer `SERVICE_ROLE_KEY`
   - App Next.js (quand elle existera) : `.env.production` côté Vercel/Coolify
   - Scripts locaux : fichier `.env.local` du super-admin
6. **Valider** :
   ```bash
   # ancienne SERVICE_ROLE_KEY doit maintenant renvoyer 401
   curl -sS -o /dev/null -w "%{http_code}\n" \
     -H "apikey: $OLD_SERVICE_ROLE_KEY" \
     https://supabase.hma.business/rest/v1/test_contract_table
   # → attendu : 401
   ```
7. **Consigner** dans le tableau ci-dessus (date, opérateur, raison).

## Procédure : rotation annuelle mot de passe PostgreSQL

⚠️ **Impact** : Supabase Studio et tous les outils internes se déconnectent ; les clés API GoTrue continuent de fonctionner (transparent pour les utilisateurs finaux).

1. Générer : `NEW_PG_PASSWORD=$(openssl rand -base64 32 | tr -d '+/=' | head -c 32)`
2. **Se connecter à PG en tant que postgres** (via tunnel SSH) et exécuter :
   ```sql
   ALTER USER postgres WITH PASSWORD '<nouveau>';
   ```
3. Mettre à jour `supabase-selfhost-postgres-password` dans Vaultwarden.
4. Mettre à jour `POSTGRES_PASSWORD` dans Coolify UI env vars.
5. Redéployer l'app Supabase dans Coolify (Restart, pas Deploy — éviter une récréation du volume).
6. Mettre à jour `/etc/supabase-backup/env` sur le VPS :
   ```bash
   sudo sed -i 's|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=<nouveau>|' /etc/supabase-backup/env
   # (si la variable y figure — dans la config actuelle pg-backup.sh ne l'utilise pas directement,
   #  pg_dump est exécuté via docker exec et l'env var est lue dans le conteneur)
   ```
7. Tester manuellement `sudo /usr/local/bin/pg-backup.sh` → succès attendu.

## Procédure : rotation OIDC client_secret / R2

### OIDC client_secret Authentik (remplace SMTP Brevo)

1. Se connecter à Authentik (`https://auth.hma.business`) → **Applications → supabase-hma → Provider** → bouton **"Regenerate client secret"**.
2. Copier la nouvelle valeur dans un Notepad local (jamais dans le chat).
3. Mettre à jour `supabase-selfhost-oidc-client-secret` dans Vaultwarden (org `stack_hma`).
4. Coolify UI → env var `GOTRUE_EXTERNAL_KEYCLOAK_SECRET` → nouvelle valeur → **Restart** app Supabase.
5. Test : tenter un login → flow OIDC doit aboutir sans erreur de client authentication.
6. Fermer Notepad sans sauvegarder.

### R2

1. Créer une nouvelle API key R2 dans Cloudflare (scope bucket `hma-supabase-backups`).
2. **Ne pas supprimer l'ancienne immédiatement** — période de chevauchement 24 h pour permettre le cron backup courant de finir.
3. Mettre à jour `supabase-selfhost-r2-access-key-id` et `supabase-selfhost-r2-secret-access-key` dans Vaultwarden.
4. Mettre à jour `/etc/supabase-backup/env` sur le VPS.
5. Lancer un backup manuel : `sudo /usr/local/bin/pg-backup.sh` → doit réussir.
6. Lancer un drill : `sudo /usr/local/bin/pg-restore-drill.sh` → doit réussir (accès R2 OK).
7. Supprimer l'ancienne API key dans Cloudflare.

## Cas particulier : **`RESTIC_PASSWORD`**

⚠️ **La rotation de `RESTIC_PASSWORD` est irréversible et coûteuse** :
- Cette clé déchiffre **toutes** les sauvegardes existantes.
- Changer la clé = les backups existants restent déchiffrables **uniquement** avec l'ancienne clé.
- **Ne jamais perdre l'ancienne clé** pendant la période de chevauchement.

Rotation conseillée uniquement si compromise. Procédure :

1. Générer la nouvelle clé : `openssl rand -hex 40`.
2. `restic key add` avec la nouvelle clé (les snapshots existants sont maintenant accessibles avec les **deux** clés).
3. Mettre à jour Vaultwarden + cold-storage (papier).
4. Mettre à jour `/etc/supabase-backup/env`.
5. Lancer un backup + drill pour confirmer.
6. **Après au moins 30 jours** sans incident : `restic key remove <old-key-id>` pour révoquer l'ancienne.
7. Mettre à jour le cold-storage en supprimant l'ancienne clé papier.

## Post-rotation — journal

Chaque rotation doit mettre à jour :
- La colonne "Dernière rotation" dans le tableau ci-dessus
- Le champ `last_rotated_at` dans les notes Vaultwarden du secret concerné
- L'annexe audit dans ce document si incident ayant motivé la rotation
