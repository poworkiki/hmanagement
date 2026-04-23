# Backups Supabase — scripts & cron

Couverture : **FR-014, FR-015, FR-016, FR-017, FR-018** / **Art. constitution 10.3**

## Fichiers

| Fichier | Rôle | Cible d'installation |
|---|---|---|
| `pg-backup.sh` | Dump PG → chiffrement restic → push R2 → rotation + notif | `/usr/local/bin/pg-backup.sh` (chmod 750, chown root:root) |
| `pg-restore-drill.sh` | Download dernier snapshot → restore sur container éphémère → smoke-tests → notif | `/usr/local/bin/pg-restore-drill.sh` (chmod 750, chown root:root) |
| `backup.cron` | Planification : daily 03h30 + drill 1er à 05h00 | `/etc/cron.d/supabase-backup` (chmod 644, chown root:root) |

Tous lisent leur configuration depuis **`/etc/supabase-backup/env`** (chmod 600 root:root), contenu attendu :

```bash
# /etc/supabase-backup/env — chmod 600 root:root
RESTIC_REPOSITORY=s3:https://<R2_ACCOUNT_ID>.r2.cloudflarestorage.com/hma-supabase-backups
RESTIC_PASSWORD=<depuis Vaultwarden supabase-selfhost-restic-password>
AWS_ACCESS_KEY_ID=<supabase-selfhost-r2-access-key-id>
AWS_SECRET_ACCESS_KEY=<supabase-selfhost-r2-secret-access-key>
SUPABASE_PG_CONTAINER=<nom exact du conteneur Coolify, ex. "supabase-db-k0gc44c">
TELEGRAM_BOT_TOKEN=<bot hmagents_bot>
TELEGRAM_CHAT_ID=<chat id ops>
```

## Installation (runbook condensé — voir `docs/runbooks/supabase-restore-drill.md` pour le drill)

```bash
# depuis la racine du repo, sur le VPS :
ssh hma

sudo apt-get update && sudo apt-get install -y restic

sudo mkdir -p /etc/supabase-backup
sudo tee /etc/supabase-backup/env >/dev/null <<'EOF'
RESTIC_REPOSITORY=...
RESTIC_PASSWORD=...
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
SUPABASE_PG_CONTAINER=...
TELEGRAM_BOT_TOKEN=...
TELEGRAM_CHAT_ID=...
EOF
sudo chmod 600 /etc/supabase-backup/env
sudo chown root:root /etc/supabase-backup/env

# copier les scripts (depuis la machine locale ou via scp après git pull sur le VPS)
sudo install -m 0750 -o root -g root pg-backup.sh        /usr/local/bin/
sudo install -m 0750 -o root -g root pg-restore-drill.sh /usr/local/bin/
sudo install -m 0644 -o root -g root backup.cron         /etc/cron.d/supabase-backup

# 1er run manuel (init du repo restic)
sudo /usr/local/bin/pg-backup.sh --first-run

# vérifier
sudo ls -lah /var/log/supabase-backup.log
```

## Codes d'erreur

### `pg-backup.sh`
- `0` : OK
- `1` : config invalide (env manquant)
- `2` : container PG introuvable
- `3` : échec `pg_dump | restic backup`
- `4` : échec `restic forget/prune`

### `pg-restore-drill.sh`
- `0` : drill OK
- `1` : config invalide
- `2` : échec `restic restore`
- `3` : échec démarrage container PG ou `pg_restore`
- `4` : smoke-tests KO

## Politique de rétention

`restic forget --keep-daily 30 --keep-monthly 12 --prune` appliqué **à chaque exécution** de `pg-backup.sh` :
- 30 snapshots quotidiens conservés
- 12 snapshots mensuels conservés (le plus récent du mois)
- tout le reste est purgé et le stockage réclamé (prune inline)

## Notifications Telegram

Tout échec déclenche un message Telegram `❌ [supabase-backup] backup failed at line N (exit rc)`. Un run OK envoie `✅ [supabase-backup] backup OK in Xs · N snapshots · repo SIZE`.

## Tests locaux (sans VPS)

`pg-backup.sh` nécessite Docker + un conteneur PG nommé + accès R2. Pas de mode "dry-run" natif. Si tu veux tester sans toucher R2 :
- pointer `RESTIC_REPOSITORY` vers un répertoire local (`RESTIC_REPOSITORY=/tmp/restic-test`)
- laisser `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` vides (ignorés si repo local)
- lancer `./pg-backup.sh --first-run`

## Disaster recovery

⚠️ **Le `RESTIC_PASSWORD` est la seule clé qui permet de déchiffrer les backups.** Il est stocké dans Vaultwarden (`supabase-selfhost-restic-password`). En plus, une **copie cold storage** (papier en coffre + copie chez un proche) est maintenue — si Vaultwarden est indisponible en même temps qu'un incident PostgreSQL, la copie cold permet la restauration.
