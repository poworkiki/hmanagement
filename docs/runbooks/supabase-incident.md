# Runbook — Gestion d'incident Supabase

Arbre de décision pour les incidents courants sur la plateforme Supabase self-hosted.

- **Couverture** : FR-018, FR-020, FR-021, FR-022, SC-009
- **Canal d'alerte primaire** : Telegram (`hmagents_bot` → chat ops)
- **Canal secondaire** : email `hmagestion@gmail.com`

## Réflexe commun à tout incident

1. **Noter l'heure** et prendre une capture du message d'alerte.
2. **Ne pas paniquer / ne pas faire de `docker system prune` en panique** — c'est destructeur.
3. Identifier la **classe** d'incident via le tableau ci-dessous.
4. Appliquer la procédure associée.
5. Rédiger un post-mortem bref à la fin (section "Journal d'incidents").

## Classification rapide

| Symptôme | Alerte source | Gravité | Procédure |
|---|---|---|---|
| `Uptime Kuma: supabase-studio DOWN` | Uptime Kuma | **Haute** si > 10 min | [§ Studio / Auth / REST down](#a--service-down-studio--auth--rest) |
| `Uptime Kuma: supabase-auth DOWN` | Uptime Kuma | **Critique** (bloque les logins) | [§ Studio / Auth / REST down](#a--service-down-studio--auth--rest) |
| `Uptime Kuma: supabase-rest DOWN` | Uptime Kuma | **Haute** (bloque apps) | [§ Studio / Auth / REST down](#a--service-down-studio--auth--rest) |
| `❌ [supabase-backup] backup failed` | Telegram (cron) | **Haute** | [§ Sauvegarde en échec](#b--sauvegarde-en-chec) |
| `❌ [restore-drill] drill failed` | Telegram (cron) | **Critique** (remise en cause fiabilité backups) | [§ Drill de restauration KO](#c--drill-de-restauration-ko) |
| `⚠️ [disk-alert] utilisé à 80%+` | Telegram (cron) | **Moyenne** si 80%, **Haute** si 90%+ | [§ Disque plein](#d--disque-qui-se-remplit) |
| `Uptime Kuma: TLS cert expires in 14 days` | Uptime Kuma | **Moyenne** (14 j), **Haute** (< 7 j) | [§ Certificat TLS qui approche expiration](#e--certificat-tls-qui-approche-expiration) |
| Magic Link jamais reçu par un utilisateur | utilisateur manuel | **Moyenne** | [§ Magic Link non reçu](#f--magic-link-non-reu) |
| Toute alerte non listée | — | à évaluer | [§ Incident inconnu](#g--incident-inconnu) |

---

## A — Service down (Studio / Auth / REST)

### Diagnostic

```bash
ssh hma

# 1. État des conteneurs Supabase
docker ps --filter 'name=supabase' --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

# 2. Logs du conteneur suspect (les 200 dernières lignes)
docker logs --tail 200 <nom-du-conteneur-down>

# 3. État mémoire / CPU / disque
free -h
df -h
uptime
```

### Résolution courante

1. Si un conteneur est `Exited` ou `Restarting` en boucle :
   - Coolify UI → app `supabase-hma` → bouton **Restart** (préférable à un rebuild).
   - Attendre 2-3 min, vérifier Uptime Kuma.
2. Si plusieurs conteneurs sont down en même temps :
   - Probable : VPS saturé ou Coolify en souffrance.
   - Vérifier `docker system df` → si plus de 80% du disque est en Docker, voir [§ Disque plein](#d--disque-qui-se-remplit).
3. Si le conteneur redémarre puis tombe à nouveau :
   - Capturer les logs complets : `docker logs <nom> > /tmp/incident-$(date +%s).log`
   - Chercher les 5 dernières lignes avant crash.
   - Causes courantes : env var manquante après rotation de secret mal faite, volume corrompu, OOM.

### Rollback de dernier recours

Si aucun redémarrage ne fonctionne :
1. **Arrêter** l'app dans Coolify UI.
2. Prendre un backup manuel des volumes : `docker run --rm -v supabase-db-data:/src -v $(pwd):/dst alpine tar czf /dst/volume-backup-$(date +%s).tgz /src`.
3. Évaluer une restauration depuis `restic` (voir `supabase-restore-drill.md` section "Restauration en conditions réelles").

---

## B — Sauvegarde en échec

### Diagnostic

```bash
ssh hma
sudo tail -100 /var/log/supabase-backup.log
```

### Causes courantes et fix

| Pattern dans les logs | Cause | Fix |
|---|---|---|
| `connection refused` / `network timeout` vers r2.cloudflarestorage.com | R2 inaccessible ou API key compromise | Vérifier CF status page ; tester la clé avec `restic snapshots` |
| `container not found: supabase-db-...` | Nom de conteneur Coolify a changé | Mettre à jour `SUPABASE_PG_CONTAINER` dans `/etc/supabase-backup/env` |
| `pg_dump: error: connection to database failed` | PG non accessible depuis docker exec | Vérifier état du conteneur PG, credentials |
| `repository does not exist` | Repo restic jamais initialisé ou inaccessible | Re-lancer `sudo /usr/local/bin/pg-backup.sh --first-run` |
| `restic forget --prune failed` | Concurrence ou timeout sur R2 | Re-lancer manuellement ; cause rare, souvent transitoire |

### Action post-fix

Une fois le fix identifié :
```bash
sudo /usr/local/bin/pg-backup.sh
# → doit produire une notif ✅
```

Si le fix prend > 24 h : 2 sauvegardes consécutives manquées → escalade, vérifier qu'aucune restauration ne serait catastrophique d'ici la résolution.

---

## C — Drill de restauration KO

### Gravité

**Critique** — remet en cause la fiabilité annoncée des backups (Art. constitution 10.3). **Ne pas ignorer même si un backup produit réussit**.

### Procédure

1. Ne pas lancer plusieurs drills en parallèle.
2. Consulter les logs : `sudo tail -300 /var/log/supabase-restore-drill.log`.
3. Matcher avec le tableau d'exit codes de [`supabase-restore-drill.md`](./supabase-restore-drill.md).
4. **Si le drill KO est lié à un fichier dump corrompu** : les backups produits sont peut-être tous inexploitables → alerte maximale, investigation approfondie avant de supprimer quoi que ce soit.
5. Lancer un drill manuel immédiatement après fix : `sudo /usr/local/bin/pg-restore-drill.sh`.
6. Si drill manuel OK → consigner dans `restore-drill-log.md` avec note "remplacement drill auto KO du JJ/MM/AAAA".

---

## D — Disque qui se remplit

### Seuils et réaction

| Utilisation | Gravité | Action |
|---|---|---|
| 80-85 % | Moyenne | Investiguer sans urgence, plan de nettoyage |
| 85-90 % | Haute | Nettoyage immédiat |
| > 90 % | **Critique** | Risque de corruption écriture PostgreSQL → agir dans l'heure |

### Diagnostic

```bash
ssh hma

# Vue d'ensemble
df -h

# Top consommateurs dans /var/lib/docker
sudo du -sh /var/lib/docker/* 2>/dev/null | sort -h | tail -10

# Taille par conteneur
docker system df -v | head -50

# Logs Docker volumineux ?
sudo find /var/lib/docker/containers -name '*.log' -size +100M -ls 2>/dev/null
```

### Nettoyage ordonné (du moins destructeur au plus)

1. **Purger les images Docker inutilisées** (safe) :
   ```bash
   docker image prune -af
   ```
2. **Purger les volumes orphelins** (⚠️ vérifier qu'aucun n'est critique avant !) :
   ```bash
   docker volume ls
   # identifier les volumes non rattachés à un conteneur
   docker volume prune  # interactif, dit non si doute
   ```
3. **Tronquer les logs Docker géants** :
   ```bash
   # identifier les log files trop gros
   sudo find /var/lib/docker/containers -name '*.log' -size +500M
   # les vider (pas supprimer — le daemon peut encore avoir le handle ouvert)
   sudo truncate -s 0 /var/lib/docker/containers/<container-id>/*.log
   ```
4. **Configurer une log rotation Docker globale** (action de fond) — ajouter dans `/etc/docker/daemon.json` :
   ```json
   {"log-driver": "json-file", "log-opts": {"max-size": "100m", "max-file": "3"}}
   ```
   Redémarrer Docker daemon (⚠️ downtime de tous les conteneurs) — planifier hors heures d'activité.

### Ce qu'il ne faut **jamais** faire en urgence

- ❌ `docker system prune -a --volumes` → supprime TOUT incluant volumes persistants, perte de données PG possible.
- ❌ `rm -rf /var/lib/docker/overlay2/*` → corruption Docker complète.

---

## E — Certificat TLS qui approche expiration

### Contexte

Traefik (intégré à Coolify) renouvelle automatiquement les certificats Let's Encrypt **30 jours** avant expiration. Une alerte Uptime Kuma à 14 jours signifie que le renouvellement automatique **a échoué**.

### Diagnostic

```bash
ssh hma

# Logs Traefik (Coolify)
docker logs coolify-proxy --tail 200 2>&1 | grep -i 'letsencrypt\|acme\|supabase'

# Tester manuellement l'accessibilité du challenge HTTP
curl -I http://supabase.hma.business/.well-known/acme-challenge/test
# → doit renvoyer 404 (pas 503, pas timeout)
```

### Causes courantes

| Cause | Symptôme | Fix |
|---|---|---|
| Rate limit Let's Encrypt | `too many failed authorizations` | Attendre 1 h, retenter. Si persistant, utiliser un LE staging puis repasser en prod |
| Port 80 fermé côté VPS ou Hostinger | `connection timeout` sur challenge | Vérifier `ufw status` / firewall Hostinger panel |
| DNS ne pointe plus vers le VPS | `wrong IP` dans les logs | Vérifier `dig supabase.hma.business` |
| Traefik en état dégradé | Pas de log ACME | `docker restart coolify-proxy` |

### Action de fallback

Forcer un renouvellement manuel via Coolify UI → app `supabase-hma` → onglet Domains → bouton "Regenerate certificate".

Si impossible avant expiration : générer un cert Let's Encrypt via `certbot` standalone en mode DNS-01 (Cloudflare plugin) et l'injecter manuellement dans Traefik.

---

## F — Magic Link non reçu

### Diagnostic ordre

1. **Vérifier côté Brevo** (`https://app.brevo.com`) → Transactional → Logs
   - Le mail est-il parti ?
   - Soft bounce / Hard bounce ?
   - Marqué spam ?
2. **Vérifier côté GoTrue** (Coolify UI → logs du conteneur `gotrue`) :
   - Le POST `/magiclink` a-t-il réussi ?
   - Une erreur SMTP est-elle visible ?
3. **Côté utilisateur** :
   - Dossier spam / courriers indésirables
   - Filtre email qui intercepterait `no-reply@hma.business`

### Causes courantes

| Cause | Fix |
|---|---|
| Quota Brevo dépassé (300/jour plan free) | Upgrade temporaire OU switch SMTP vers SES Paris fallback |
| SPF/DKIM/DMARC mal configurés → mails en spam | Re-vérifier les enregistrements DNS Brevo (T016) |
| `GOTRUE_SMTP_PASS` obsolète suite à rotation | Restaurer la bonne clé (cf. runbook rotation) |
| Rate limit `GOTRUE_RATE_LIMIT_EMAIL_SENT=10/h/IP` atteint | Attendre 1 h ou augmenter temporairement |

---

## G — Incident inconnu

Protocole générique :

1. **Isoler** : ne pas redémarrer en aveugle, ne pas supprimer de fichiers.
2. **Collecter** :
   ```bash
   ssh hma
   mkdir -p /tmp/incident-$(date +%s)
   cd /tmp/incident-*
   docker ps -a > containers.txt
   free -h > mem.txt
   df -h > disk.txt
   docker logs --tail 500 <conteneur-suspect> > logs-<nom>.txt 2>&1
   ```
3. **Consulter** la documentation Supabase / Coolify / GoTrue via Context7 MCP (tooling Claude) :
   - `https://supabase.com/docs/guides/self-hosting`
   - `https://coolify.io/docs`
4. **Décider** entre fix immédiat, rollback backup, ou incident rate-limited (wait & see).
5. **Consigner** dans le journal ci-dessous.

---

## Journal d'incidents

### Format

Pour chaque incident significatif :
- **Date + heure (UTC)** de détection
- **Classe** (A, B, C, D, E, F, G)
- **Durée d'indisponibilité** (si applicable)
- **Cause racine** identifiée
- **Fix appliqué**
- **Leçons / actions de fond** (ajustements runbook, monitoring, code)

### Entrées

_Aucun incident à ce jour — journal initialisé lors de la création de la feature 001-supabase-selfhost._
