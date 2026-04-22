# Runbook — Drill de restauration mensuelle Supabase

- **Trigger automatique** : cron `0 5 1 * *` (1er du mois, 05h00 VPS) — entrée `/etc/cron.d/supabase-backup`
- **Trigger manuel** : `sudo /usr/local/bin/pg-restore-drill.sh`
- **Durée cible** : ≤ 30 min (SC-004)
- **Impact production** : **aucun** — drill sur container éphémère isolé réseau
- **Couverture** : FR-017, SC-004, Art. constitution 10.3

## Pré-requis

- VPS Hostinger `187.124.150.82` opérationnel, accès `ssh hma`
- `/etc/supabase-backup/env` en place avec credentials R2 + restic + Telegram
- `restic` ≥ 0.17 installé (`apt install restic`)
- Docker opérationnel, image `postgres:15` disponible (sinon pull auto au 1er run)
- Au moins 1 snapshot dans `restic snapshots` (cron `pg-backup.sh` tourne depuis ≥ 24 h)

## Procédure exécution manuelle

```bash
# 1. Se connecter au VPS
ssh hma

# 2. Vérifier l'état avant drill
sudo restic -r $(grep ^RESTIC_REPOSITORY /etc/supabase-backup/env | cut -d= -f2-) snapshots --latest 1

# 3. Lancer le drill
sudo /usr/local/bin/pg-restore-drill.sh
# → durée attendue 5-15 min selon taille base
# → un message Telegram ✅ s'affiche en fin d'exécution

# 4. Consulter les logs
sudo tail -100 /var/log/supabase-restore-drill.log
```

## Résultat attendu

### Succès

1. Notification Telegram :
   ```
   ✅ [restore-drill] drill OK · snapshot XXXXXXXX · 327s · 4 schemas · 182 relations
   ```
2. Exit code `0`.
3. Aucun container `pg-restore-drill-*` ne reste actif (`docker ps` ne doit rien montrer).

### Échec possible

| Exit code | Cause probable | Première action |
|---|---|---|
| 1 | config invalide (env manquant) | Vérifier `/etc/supabase-backup/env`, permissions 600 root |
| 2 | `restic restore` KO | Vérifier credentials R2, connectivité réseau sortante, état du bucket |
| 3 | `pg_restore` KO ou container PG ne démarre pas | `docker logs pg-restore-drill-*`, checker compatibilité version PG |
| 4 | smoke-tests KO | Le dump restauré ne contient pas les schémas attendus — **investigation urgente** |

Tout échec déclenche une notification Telegram `❌ [restore-drill] …`. Cette alerte **bloque le mois** tant qu'un drill n'a pas réussi.

## Liste de contrôle d'intégrité manuelle (trimestrielle, en plus du drill auto)

Une fois par trimestre (calendrier), passer du temps sur un drill "enrichi" :

- [ ] Le drill auto de ce trimestre a réussi (consulter `restore-drill-log.md`)
- [ ] La durée est stable (pas de dérive > 50% vs trimestre précédent)
- [ ] Le nombre de schemas / relations correspond à l'état attendu
- [ ] Faire un `pg_restore` manuel vers un container dédié, puis :
  - [ ] `SELECT count(*) FROM app.audit_log WHERE created_at > now() - interval '30 days'` → cohérent avec l'activité ?
  - [ ] `SELECT max(date_cloture) FROM marts.mart_compte_resultat` → date récente ?
  - [ ] Un spot-check de 3-5 lignes métier (une facture connue, un paiement connu) → retrouvé ?
- [ ] Consigner la date et les observations dans `restore-drill-log.md`

## Après le drill

- Le container `pg-restore-drill-*` est automatiquement détruit (flag `--rm` + trap de cleanup).
- Le répertoire `/tmp/pg-restore-drill.XXXXXX` est automatiquement purgé.
- Le network Docker `pg-restore-drill-*-net` est détruit.

Si l'un de ces éléments subsiste (après exit non nominal), nettoyer manuellement :

```bash
docker rm -f pg-restore-drill-* 2>/dev/null
docker network rm pg-restore-drill-*-net 2>/dev/null
sudo rm -rf /tmp/pg-restore-drill.*
```

## Consigner l'exécution

Chaque drill (auto ou manuel) **doit** faire l'objet d'une ligne dans [`restore-drill-log.md`](./restore-drill-log.md).

Pour le drill auto, c'est à faire **manuellement** au début du mois suivant par le super-admin (la notification Telegram suffit pour confirmer la réussite, mais le log sert au suivi historique).

## Restauration en conditions réelles (≠ drill)

⚠️ Cette section décrit la **vraie** restauration après incident, pas le drill.

### Scénario : perte de données production

1. **STOP** — **jamais** restaurer en écrasant la prod sans avoir sauvegardé l'état courant.
2. Prendre immédiatement un snapshot de l'état actuel :
   ```bash
   sudo /usr/local/bin/pg-backup.sh  # snapshot "post-incident" daté
   ```
3. Consulter la liste des snapshots :
   ```bash
   sudo restic -r $REPO snapshots
   ```
4. Choisir le point de restauration souhaité.
5. **Ne pas restaurer sur la DB de prod** directement. Restaurer sur un container PG éphémère, inspecter, puis basculer manuellement (dump + restore ciblé) les tables concernées.
6. Si incident majeur (DB prod complètement corrompue), la restauration directe est possible mais suppose un downtime :
   ```bash
   # Arrêter l'app Supabase dans Coolify UI
   # Restaurer vers le volume PG existant (⚠️ destructeur)
   # Redémarrer l'app
   ```
7. Rédiger un post-mortem dans `supabase-incident.md`.
