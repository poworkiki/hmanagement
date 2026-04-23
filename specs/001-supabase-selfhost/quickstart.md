# Quickstart — Opérateur super-admin

**Feature** : `001-supabase-selfhost`
**Audience** : super-admin HMA (Kiki) déployant l'instance pour la première fois **ou** validant un état existant.
**Durée estimée** : 60 à 90 minutes pour un déploiement propre, 10 minutes pour un smoke-test.

Ce document est un **guide linéaire opérationnel**. Les scripts et fichiers de config détaillés viendront avec `/speckit-tasks` → `/speckit-implement`. Ici, on décrit **l'expérience opérateur cible**.

---

## 1. Pré-requis (avant de commencer)

À valider **avant** de lancer le déploiement :

- [ ] VPS Hostinger `187.124.150.82` accessible via `ssh hma`
- [ ] Coolify v4+ fonctionnel sur `https://coolify.hma.business`, compte super-admin actif
- [ ] Accès Vaultwarden (`vaultwarden.poworkiki.cloud`, org `stack_hma`)
- [ ] Accès Cloudflare DNS pour `hma.business`
- [ ] Bucket **Cloudflare R2** `hma-supabase-backups` créé avec jeu d'API dédié (scope = ce bucket uniquement)
- [ ] Compte **Brevo** actif avec API SMTP (ou alternative retenue) + quota suffisant
- [ ] **12 secrets Vaultwarden** préfixés `supabase-selfhost-*` créés (voir `contracts/platform-env-contract.md`)
- [ ] Telegram bot `hmagents_bot` joint, chat ID ops obtenu

---

## 2. Bootstrap initial (60-90 min)

### 2.1 DNS

1. Cloudflare DNS zone `hma.business` → **ajouter** un enregistrement `A` :
   - Name : `supabase`
   - Value : `187.124.150.82`
   - Proxy : **DNS only** (grise, pas orange — Traefik gère TLS directement ; CF proxy reporté)
   - TTL : auto
2. Vérifier en < 60 s : `dig supabase.hma.business +short` retourne `187.124.150.82`.

### 2.2 Création de l'application Supabase dans Coolify

1. Ouvrir Coolify → **Resources → + New → Service** → choisir le template **"Supabase"**.
2. Onglet **"Domains"** : saisir `supabase.hma.business` comme domaine principal, activer TLS Let's Encrypt.
3. Onglet **"Environment Variables"** : coller une par une les 12 valeurs issues de Vaultwarden selon `contracts/platform-env-contract.md`. Chaque valeur secrète doit être marquée **"Masked"**.
4. Onglet **"Volumes"** : vérifier qu'un volume persistant est monté pour `/var/lib/postgresql/data` — **critique** pour éviter la perte au redémarrage conteneur.
5. Cliquer **"Deploy"**.

### 2.3 Premier démarrage et vérification

Attendre que Coolify affiche **tous** les conteneurs en état "Healthy" (≈ 3 à 5 min) :

- [ ] `postgres` : Healthy
- [ ] `gotrue` : Healthy
- [ ] `postgrest` : Healthy
- [ ] `studio` : Healthy
- [ ] `kong` (ou `traefik` label) : route externe OK
- [ ] `storage` : Healthy (inactif MVP mais doit démarrer)

Puis ouvrir `https://supabase.hma.business/` dans le navigateur :
- [ ] Certificat HTTPS valide (cadenas vert)
- [ ] Page de login Supabase Studio s'affiche
- [ ] Connexion `admin` + `DASHBOARD_PASSWORD` réussie
- [ ] La base `postgres` est visible, vide de tables applicatives

### 2.4 Configuration des sondes Uptime Kuma

1. Ouvrir `https://status.hma.business` → **+ Add New Monitor** × 4 (les 4 probes de `contracts/admin-api-contract.md` §4).
2. Chaque probe : type HTTP(s), intervalle 60 s, seuil de retries 2, notifs Telegram + email.

### 2.5 Cron de backup

1. SSH sur le VPS : `ssh hma`.
2. Installer `restic` si absent : `apt-get install -y restic`.
3. Déposer le script `/usr/local/bin/pg-backup.sh` (version finale livrée par la feature d'implémentation).
4. Créer l'unité systemd-timer **ou** l'entrée `/etc/cron.d/supabase-backup` : exécution quotidienne à 03h30 VPS.
5. Lancer un premier backup manuel : `sudo /usr/local/bin/pg-backup.sh --first-run`.
6. Vérifier dans R2 : l'objet (snapshot restic) est présent, sa taille > 0.

### 2.6 Drill restauration mensuelle

1. Déposer `/usr/local/bin/pg-restore-drill.sh`.
2. Créer l'entrée cron `/etc/cron.d/supabase-restore-drill` : `0 5 1 * *`.
3. **Exécuter manuellement une première fois** pour valider : `sudo /usr/local/bin/pg-restore-drill.sh`. Attendre ≤ 30 min. Résultat attendu : message Telegram `✅ Restore drill OK (N tables, checksums match)`.
4. Consigner la date dans `docs/runbooks/restore-drill-log.md`.

### 2.7 Premier compte super-admin avec MFA

1. Dans Supabase Studio → **Authentication → Users → Invite user** → saisir `poworkiki@gmail.com` (ou compte opérationnel cible).
2. Consulter la boîte mail : cliquer le Magic Link (< 60 s).
3. Dans le parcours GoTrue : configurer TOTP (scanner QR avec app auth cible), saisir le premier code à 6 chiffres.
4. Vérifier dans Studio → Authentication → Users que le compte apparaît avec `mfa_enrolled = true` et `is_active` (manuellement activé par le super-admin lors de la feature suivante, ici juste la preuve de parcours).

---

## 3. Smoke-test (10 min) — à rejouer après chaque changement

Check-list exécutable "sur le tas" pour valider que la plateforme est opérationnelle :

```bash
# Depuis un poste extérieur — Kong exige apikey sur /rest/* et /auth/*
# Récupérer ANON_KEY via vw-secret.sh :
eval "$(bash /c/HMAGESTION_STACK/scripts/vw-secret.sh export 'supabase-selfhost-anon-key' ANON_KEY)"

curl -sS -o /dev/null -w "Studio HTTP %{http_code}\n" https://supabase.hma.business/
# → attendu : 401 (Kong Basic Auth protège Studio UI — accessible seulement via hmadmin login)

curl -sS -o /dev/null -w "PostgREST HTTP %{http_code}\n" -H "apikey: $ANON_KEY" https://supabase.hma.business/rest/v1/
# → attendu : 200 (schema cache OpenAPI) ; 401 sans apikey

curl -fsS -H "apikey: $ANON_KEY" https://supabase.hma.business/auth/v1/health
# → attendu : JSON `{"version":"v2.186.0","name":"GoTrue",...}`

# Depuis une session SSH sur le VPS
ssh hma 'docker ps --format "{{.Names}}\t{{.Status}}" | grep supabase'
# → attendu : 12 containers, tous "Up ... (healthy)" sauf supabase-rest sans healthcheck

# Requête psql (via docker exec, pas de tunnel SSH requis)
ssh hma 'docker exec supabase-db-<SUFFIX> psql -U postgres -d postgres -c "SELECT now(), current_database(), version();"'
```

Résultats attendus :
- [ ] Studio root → **401** (Basic Auth Kong, c'est SAIN — signal que l'auth est enforced)
- [ ] PostgREST avec apikey → **200** (sans apikey : 401, aussi OK)
- [ ] GoTrue `/health` avec apikey → **JSON `{"version":...,"name":"GoTrue"}`**
- [ ] `docker ps` montre 12 conteneurs Supabase `Up`, majoritairement `healthy`
- [ ] `psql` renvoie un horodatage, `postgres`, `PostgreSQL 15.8`

> **Note** : le code de statut `401` sur une URL sans apikey **n'est pas une panne** — c'est la preuve que Kong intercepte bien les routes et enforce l'authentification (Art. sécurité constitution). Une panne serait `502`, `503`, `504`, ou `connection refused`.

---

## 4. Cas d'incident courants (référence rapide)

Pour le détail, voir `docs/runbooks/supabase-incident.md`.

| Symptôme | Première action |
|---|---|
| Uptime Kuma alerte "Down" sur Studio | `docker restart <container studio>` via Coolify UI |
| Magic Link jamais reçu | Vérifier quota Brevo / journal SMTP Brevo → logs GoTrue |
| Disque > 80 % | Purger logs Docker anciens ; vérifier croissance PG ; alerter avant 90 % |
| Certificat TLS bientôt expiré | Traefik doit renouveler auto ; sinon `coolify → app → regenerate cert` |
| Backup Telegram a alerté "échec" | SSH VPS → `sudo /usr/local/bin/pg-backup.sh --verbose` → inspecter erreur R2 |

---

## 5. Sortie attendue de cette feature

À la complétion de l'implémentation :

- `https://supabase.hma.business` répond en HTTPS avec certificat reconnu
- Au moins 1 compte super-admin opérationnel avec MFA TOTP actif
- Au moins 1 sauvegarde présente dans R2, chiffrée par restic
- 1 drill de restauration documenté et réussi
- 4 probes Uptime Kuma actives et vertes
- 0 secret en clair dans le repo (vérifié par `grep`), conforme SC-007
- 12 entrées Vaultwarden `supabase-selfhost-*` remplies
- Runbooks `supabase-deploy.md`, `supabase-secret-rotation.md`, `supabase-restore-drill.md`, `supabase-incident.md` en place
- ADR `ADR-001-supabase-self-hosted-via-coolify.md` committé

### Notes de scope

- **FR-008 session 8h/1h** : en MVP, tous les comptes sont administrateur → cap session uniforme à **1 h** (borne stricte). La différenciation "8 heures utilisateur standard" sera livrée par le middleware applicatif lorsque les rôles non-administrateur existeront (feature `002-schemas-rls-bootstrap` + feature app).
- **FR-019 métriques santé** : la plateforme expose en MVP des **health-checks binaires** (up/down) sur Studio, Auth, REST, surveillés par Uptime Kuma. Les **métriques quantitatives** (CPU, pg_stat, QPS, latences internes via Prometheus + `postgres_exporter`) sont reportées à une feature d'observabilité ultérieure (cf. `research.md` R-005).

**Ensuite** → la feature `002-schemas-rls-bootstrap` peut démarrer (elle consommera cette plateforme pour y créer les schémas `raw`, `staging`, `marts`, `app` et les rôles applicatifs).
