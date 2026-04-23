---

description: "Task list for feature 001-supabase-selfhost"
---

# Tasks: Socle data self-hosted et souverain

**Input**: Design documents from `/specs/001-supabase-selfhost/`
**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/platform-env-contract.md`, `contracts/admin-api-contract.md`, `quickstart.md`

**Tests**: La feature n'implique pas de code applicatif testé par unit tests. En lieu et place, chaque SC-### (Success Criterion) fait l'objet d'une **tâche de vérification** qui reproduit l'acceptance scenario correspondant (smoke-tests `curl`/`psql`, drill de restauration, vérification monitoring). Ces tâches sont marquées explicitement `[VALID]`.

**Organization**: Organisées par user story (US1 → US5) selon la priorité spec.md. Les chemins `infra/supabase/` et `docs/runbooks/` sont créés par cette feature (nouveaux dossiers dans le repo).

## Format: `[ID] [P?] [Story] Description`

- **[P]** : peut s'exécuter en parallèle (fichier différent, pas de dépendance bloquante)
- **[Story]** : US1, US2, US3, US4, US5 — mappe vers les user stories du `spec.md`
- **[VALID]** : tâche de validation / smoke-test (couvre une SC-###)
- Tous les chemins de fichiers sont **relatifs à la racine du repo** `C:\hmanagement\`

## Path Conventions

- `infra/supabase/` — IaC (configuration + scripts d'ops, créé par cette feature)
- `docs/runbooks/` — runbooks opérateur (créé par cette feature)
- `docs/adr/` — décisions d'architecture (créé par cette feature)
- `specs/001-supabase-selfhost/` — déjà existant (spec, plan, research, data-model, contracts, quickstart)
- Actions Coolify / Vaultwarden / Cloudflare sont réalisées via leurs UI respectives et ne produisent **pas** de fichier dans le repo — ces tâches indiquent explicitement "UI" dans la description.

---

## Phase 1: Setup (shared infrastructure)

**Purpose** : initialiser l'arborescence repo et l'outillage local requis pour toutes les US.

- [x] T001 [P] Créer l'arborescence `infra/supabase/` avec `README.md` pointeur vers `specs/001-supabase-selfhost/quickstart.md`
- [x] T002 [P] Créer l'arborescence `infra/supabase/backups/` (vide, prête à accueillir les scripts)
- [x] T003 [P] Créer l'arborescence `infra/supabase/monitoring/` (vide)
- [x] T004 [P] Créer l'arborescence `docs/runbooks/` avec un `README.md` index
- [x] T005 [P] Créer l'arborescence `docs/adr/` avec un `README.md` expliquant le format ADR utilisé (MADR light)
- [x] T006 [P] Ajouter à `.gitignore` les motifs sensibles : `*.env.local`, `*.env.production`, `*.backup`, `restic-cache/`, `*.sql.gz` (protection secrets Art. 4.5)
- [x] T007 Rédiger l'ADR `docs/adr/ADR-001-supabase-self-hosted-via-coolify.md` consignant la décision de déployer Supabase self-hosted sur Coolify (résumé du `research.md` R-001, R-002, R-003)

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose** : provisionner les ressources externes et les secrets **avant** toute tentative de déploiement. Toutes les user stories dépendent de cette phase.

**⚠️ CRITICAL** : Aucune US ne peut démarrer avant la complétion de cette phase.

### 2.1 DNS & domaine

- [x] T010 [UI Cloudflare] Créer l'enregistrement DNS type `A` : `supabase.hma.business` → `187.124.150.82`, mode "DNS only" (proxy désactivé). Vérification : `dig supabase.hma.business +short` renvoie l'IP du VPS.

### 2.2 Cloudflare R2 pour sauvegardes

- [x] T011 [UI Cloudflare] Créer le bucket R2 `hma-supabase-backups` (région EU automatique). Activer object lifecycle optionnel : rien à configurer, restic gère la rétention.
- [x] T012 [UI Cloudflare] Générer un jeu d'API R2 à scope **restreint au bucket `hma-supabase-backups`** (Read+Write). Récupérer `Access Key ID`, `Secret Access Key`, `Account ID`.
- [x] T013 [UI Vaultwarden] Créer les 3 secrets correspondants : `supabase-selfhost-r2-account-id`, `supabase-selfhost-r2-access-key-id`, `supabase-selfhost-r2-secret-access-key` dans l'org `stack_hma`.

### 2.3 ~~Compte SMTP (Brevo)~~ → **Authentik OIDC (délégation auth)**

> **Clarification /speckit-clarify 2026-04-22** : T014-T017 supprimés. L'authentification est déléguée à l'IdP Authentik existant (`auth.hma.business`) qui gère déjà son propre SMTP. Remplacés par T014-T017 configuration OIDC ci-dessous.

- [x] T014 [API Authentik] ~~UI~~ Créer via API REST la Provider OAuth2/OIDC `supabase-hma-provider` + Application `supabase-hma` (slug). `client_id` et `client_secret` générés automatiquement. ✅ Fait 2026-04-22 via script idempotent.
- [x] T015 [API Authentik] ~~UI~~ Configurer via API : Redirect URI = `https://supabase.hma.business/auth/v1/callback`, scopes = `openid email profile`, authorization/authentication/invalidation flows = défauts, signing key = authentik Self-signed.
- [x] T016 [API Authentik] Créer groupe `supabase-hma-admins` via API. **Note** : policy MFA n'est pas bindée spécifiquement au groupe — la stage `default-authentication-mfa-validation` (ordre 30) dans `default-authentication-flow` enforce MFA **globalement** sur toute auth Authentik (acceptable MVP car seul user humain actif = hmadmin dans le groupe).
- [x] T017 [API Vaultwarden] Stocker `supabase-selfhost-oidc-client-id` + `supabase-selfhost-oidc-client-secret` (chiffrés, org `stack_hma`) via `vw-crypto.py`.
- [x] T017.1 [BONUS non prévu] Créer user Authentik `hmadmin` (email `hmagestion@gmail.com`, type `internal`), assigné au groupe `supabase-hma-admins`, avec password initial 32 chars stocké dans Vaultwarden `authentik-hmadmin-password`. `akadmin` original est en fait un service account outpost Authentik (non modifiable via API).
- [x] T017.2 [manuel UI] Enrôlement TOTP de `hmadmin` via Microsoft Authenticator (QR code Authentik → Microsoft Authenticator → code 6 chiffres). **Vérifié par API** : 1 device TOTP `confirmed=true`, login incognito avec TOTP challenge validé.

### 2.4 Secrets Supabase dans Vaultwarden

- [x] T018 [P] [API Vaultwarden] Générer et stocker `supabase-selfhost-jwt-secret` (64 chars hex, `secrets.token_hex(32)`).
- [x] T019 [P] [API Vaultwarden] Générer et stocker `supabase-selfhost-anon-key` (JWT HS256 signé avec JWT_SECRET, claim `role=anon`, exp +10 ans).
- [x] T020 [P] [API Vaultwarden] Générer et stocker `supabase-selfhost-service-role-key` (JWT HS256 signé, claim `role=service_role`).
- [x] T021 [P] [API Vaultwarden] Générer et stocker `supabase-selfhost-postgres-password` (32 chars alphanum).
- [x] T022 [P] [API Vaultwarden] Générer et stocker `supabase-selfhost-dashboard-password` (24 chars).
- [x] T023 [P] [API Vaultwarden] Générer et stocker `supabase-selfhost-restic-password` (80 chars hex, `secrets.token_hex(40)`). **Cold storage papier à faire séparément, cf. T023.5.**
- [x] T023.5 [GATE] ✅ **Cold storage papier effectué 2026-04-23** (attestation Kiki). Gate levé, T076 peut désormais être exécuté sans risque de perte backups sur incident corrélé Vaultwarden + PG. **Rappel annuel** à programmer : test de transcription (rescanner la valeur papier → comparer avec Vaultwarden) + drill de restauration utilisant la copie papier au lieu de Vaultwarden. Prochaine échéance : 2027-04-23.

### 2.5 ~~Canal Telegram (création nouveau chat)~~ → **Réutilisation chat existant**

> **Clarification /speckit-clarify 2026-04-22** : T024 supprimée (pas de nouveau chat), T025 simplifiée en récupération du chat_id du canal Telegram HMA existant dans lequel `hmagents_bot` envoie déjà les notifications (n8n, Authentik).

- [x] T025 [API Vaultwarden] Chat_id `1450627120` (DM privé poworkiki + hmagents_bot) récupéré via `getUpdates` et stocké chiffré dans stack_hma. **Test live validé 2026-04-22** : message envoyé depuis API Telegram → reçu sur mobile Kiki.

### 2.6 Reference de configuration versionnée (publique)

- [x] T026 Créer `infra/supabase/env.reference` avec **uniquement** les variables 📄 (publiques) — fait, committé, mis à jour post-OIDC.
- [x] T027 Créer `infra/supabase/gotrue-config-overrides.yml` documentant les overrides GoTrue — fait, committé, v2 avec section OIDC Authentik.

**Checkpoint Phase 2** — État au 2026-04-23 :
- ✅ DNS `supabase.hma.business` → `187.124.150.82` DNS-only
- ✅ Bucket R2 `hma-supabase-backups` + token API scopé (rotate post-leak T075.5)
- ✅ **12 secrets Vaultwarden** chiffrés dans stack_hma :
  - 3 R2 (account-id, access-key-id, secret-access-key)
  - 6 Supabase (jwt, anon-key, service-role-key, postgres-pwd, dashboard-pwd, restic-pwd)
  - 2 OIDC Authentik (client-id, client-secret)
  - 1 Telegram chat-id
  + bonus `authentik-hmadmin-password` (32 chars)
- ✅ Authentik : Provider `supabase-hma-provider`, App `supabase-hma`, Group `supabase-hma-admins`, User `hmadmin` avec TOTP MFA enrollé + validé
- ✅ Canal Telegram live-testé (chat_id `1450627120`)
- ⏳ **T023.5 cold storage papier `RESTIC_PASSWORD`** — unique gate restant avant T076

**Les 5 user stories peuvent démarrer à partir d'ici** (capacité équipe ≥ 2). US3 (backups) reste bloquée par T023.5 avant T076.

---

## Phase 3: User Story 1 — Plateforme data opérationnelle (Priority: P1) 🎯 MVP

**Goal** : déployer l'instance Supabase accessible via `https://supabase.hma.business` avec Studio fonctionnel et PostgreSQL opérationnel.

**Independent Test** : Ouvrir `https://supabase.hma.business/` dans un navigateur, se connecter à Studio, voir la base `postgres` vide opérationnelle. Depuis un tunnel SSH, `psql ... SELECT 1;` renvoie `1`.

### Implementation for User Story 1

- [x] T030 [US1] Coolify UI → **Resources → New → Service** → template Supabase. Service nommé `supabase-hma`. ✅ Fait par Kiki 2026-04-23.
- [x] T031 [US1] Domain `supabase.hma.business` + HTTPS Let's Encrypt via Traefik. Cert valide, TLS check 0 (OK).
- [x] T032 [US1] Env vars injectées. **Leçon** : Coolify regénère JWT_SECRET/ANON_KEY/SERVICE_ROLE_KEY si vides → Vaultwarden resync obligatoire post-deploy (cf. runbook supabase-deploy.md §Piège n°1).
- [x] T033 [US1] Volume persistant OK (PG survit au recreate — vérifié via schemas auth/storage/realtime/graphql présents).
- [x] T034 [US1] Deploy OK. 12 containers healthy : db, auth, kong, rest, studio, storage, minio, meta, analytics, vector, edge-functions, supavisor.
- [x] T035 [US1] Runbook `docs/runbooks/supabase-deploy.md` enrichi avec 3 pièges réels (regen JWT, DB name wipe, container suffix).
- [x] T036 [P] [US1] [VALID] (SC-001) HTTP 401 Kong Basic Auth (endpoint up) + TLS valide + **0.90s total** < 3s ✅.
- [ ] T037 [P] [US1] [VALID] (SC-005) `docker restart` de toute la stack — **non testé explicitement**, mais recreate Coolify complet a remonté 12 containers en ~3 min → signal indirect OK.
- [x] T038 [US1] [VALID] `docker exec supabase-db psql -U postgres -d postgres -c "SELECT now(), ..."` → PG 15.8, DB `postgres`, timestamp OK.
- [x] T039 [US1] Kong Basic Auth (hmadmin + password Vaultwarden) validée par Kiki pour accéder à Supabase Studio en live.

**Checkpoint US1** : la plateforme est joignable et administrable. Les US2-US5 peuvent commencer en parallèle.

---

## Phase 4: User Story 2 — Authentification Magic Link + MFA TOTP (Priority: P1)

**Goal** : permettre au super-admin de s'authentifier via **Authentik OIDC** (Magic Link Authentik + MFA TOTP obligatoire enforcé côté IdP). Supabase GoTrue agit comme OIDC relying party.

**Independent Test** : un compte test invité dans Authentik + groupe MFA clique "Sign in with Authentik" sur Supabase Studio → redirection → login Magic Link Authentik → challenge TOTP → retour Supabase avec session JWT valide.

### Implementation for User Story 2

- [ ] T050 [US2] Coolify UI → Env vars `supabase-hma` → injecter les overrides OIDC : `GOTRUE_EXTERNAL_EMAIL_ENABLED=false` (désactive Magic Link natif), `GOTRUE_EXTERNAL_KEYCLOAK_ENABLED=true`, `GOTRUE_EXTERNAL_KEYCLOAK_CLIENT_ID` (depuis `supabase-selfhost-oidc-client-id` Vaultwarden), `GOTRUE_EXTERNAL_KEYCLOAK_SECRET` (depuis `supabase-selfhost-oidc-client-secret`), `GOTRUE_EXTERNAL_KEYCLOAK_URL=https://auth.hma.business/application/o/supabase-hma/`, `GOTRUE_EXTERNAL_KEYCLOAK_REDIRECT_URI=https://supabase.hma.business/auth/v1/callback`. Conserver `GOTRUE_DISABLE_SIGNUP=true`, `GOTRUE_JWT_EXP=3600`. **Vérifier les noms exacts** contre la version GoTrue livrée (alias possible : `GOTRUE_EXTERNAL_CUSTOM_*` selon version, config via JSON si GoTrue v2.170+).
- [ ] T051 [US2] Coolify UI → onglet **Restart** de l'app `supabase-hma` pour que les env vars OIDC prennent effet. Vérifier les logs `gotrue` : pas d'erreur de discovery OIDC (`GET /.well-known/openid-configuration` sur Authentik doit réussir).
- [ ] T052 [US2] Côté Authentik (`auth.hma.business`) : ajouter le compte cible (`poworkiki@gmail.com`) au groupe `supabase-hma-admins` (créé en T016). Envoyer/valider l'invitation Authentik → 1er login Authentik + setup TOTP si jamais fait avant.
- [ ] T053 [US2] Sur `https://supabase.hma.business/` → Supabase Studio login → bouton **"Sign in with Keycloak"** (ou équivalent selon l'UI Studio) → redirection `auth.hma.business`. Authentik envoie le Magic Link à l'email → clic → retour Authentik → challenge TOTP → retour Supabase Studio authentifié.
- [ ] T054 [US2] [VALID] (FR-007) Vérifier dans les claims JWT retourné par Supabase (via DevTools navigateur) la présence d'un attribut attestant MFA (ex. `amr: ["mfa"]` ou claim Authentik équivalent). Cohérence avec l'enforcement côté groupe Authentik.
- [ ] T055 [P] [US2] [VALID] (FR-008, User Story 2 scenario 4) Laisser la session admin inactive 60 min (cap `GOTRUE_JWT_EXP=3600`). Tenter une action → redirection login Authentik attendue.
- [ ] T056 [P] [US2] [VALID] (FR-009) Authentik UI → vérifier que le TTL du Magic Link Authentik est configuré à ≤ 15 minutes. Tester un lien expiré → refus.
- [ ] T057 [P] [US2] [VALID] Retirer le compte du groupe `supabase-hma-admins` sur Authentik → tenter nouveau login → refus/logout immédiat. Valide que la révocation est bien enforcée côté IdP.
- [ ] T058 [P] [US2] [VALID] (SC-002) Chronométrer l'activation d'un **second** compte admin end-to-end (ajout groupe Authentik → 1er login → MFA setup → session Supabase valide) en suivant uniquement `docs/runbooks/supabase-deploy.md` : cible < 5 min.

**Checkpoint US2** : le super-admin est authentifié via Authentik OIDC avec MFA TOTP enforcé côté IdP. L'authentification est production-ready et centralise avec le reste du stack HMA.

---

## Phase 5: User Story 3 — Sauvegardes quotidiennes chiffrées (Priority: P1)

**Goal** : produire une sauvegarde chiffrée quotidienne, la stocker sur R2, et valider la restauration mensuelle.

**Independent Test** : après 24 h, au moins une sauvegarde présente sur R2 ; un drill de restauration sur container éphémère aboutit en < 30 min avec checksums vérifiés.

### Implementation for User Story 3

- [x] T070 [P] [US3] Créer `infra/supabase/backups/pg-backup.sh` — committé, testé live 2026-04-23 (exit 0, snapshot OK, retention appliquée).
- [x] T071 [P] [US3] Créer `infra/supabase/backups/pg-restore-drill.sh` — committé + patch `--no-owner --no-acl` appliqué (Supabase roles absents sur PG vanilla), drill bootstrap OK en 9s.
- [x] T072 [P] [US3] Créer `infra/supabase/backups/backup.cron` — committé, installé sur VPS `/etc/cron.d/supabase-backup` (daily 03h30 UTC + drill 1er mois 05h00 UTC + disk-alert 15 min).
- [x] T073 [P] [US3] `infra/supabase/backups/README.md` — committé.
- [x] T074 [US3] VPS : restic installé, scripts copiés `/usr/local/bin/pg-backup.sh` + `pg-restore-drill.sh` + `disk-alert.sh` (chmod 750, root:root). `/etc/supabase-backup/env` créé (chmod 600 root:root).
- [x] T075 [US3] Cron `/etc/cron.d/supabase-backup` déposé (chmod 644).
- [x] T075.5 [US3] [GATE-PARTIAL] ✅ **Rotation Cloudflare + Vaultwarden effectuée 2026-04-22.** Les étapes (1) révocation token, (2) création token neuf scope identique, (3) mise à jour des 2 entrées Vaultwarden `supabase-selfhost-r2-access-key-id` et `supabase-selfhost-r2-secret-access-key` ont été validées (`access-key-id` CHANGED + `secret-access-key` CHANGED, `account-id` inchangé conformément). Contexte historique : les 3 valeurs initiales avaient été leakées dans un transcript Claude le 2026-04-22 lors de la création ; la fenêtre d'exposition s'est refermée avant toute production de backup. **Sous-tâche restante** : (4) à T074, lors de la création de `/etc/supabase-backup/env` sur le VPS, utiliser les **nouvelles** valeurs Vaultwarden (jamais les leakées). Cette sous-tâche est naturellement absorbée par T074.
- [x] T076 [US3] `pg-backup.sh --first-run` exécuté — exit 0, restic repo init, snapshot `cbfe7451` sur R2, 47 KiB stored après dédup.
- [x] T077 [US3] restic snapshots listing : 1 snapshot visible, taille > 0. ✅
- [x] T078 [US3] Drill bootstrap : 9 s (SC-004 <30 min ✅), 11 user schemas, 174 relations restaurées, exit 0.
- [x] T079 [US3] `docs/runbooks/supabase-restore-drill.md` — skeleton committé.
- [x] T080 [US3] `docs/runbooks/restore-drill-log.md` — 1re entrée consignée (2026-04-23 05:11 UTC, snapshot cbfe7451, 9 s, OK).
- [ ] T081 [P] [US3] [VALID] (SC-003, FR-014) Attendre 24 h après T076 et vérifier qu'un **deuxième** snapshot automatique est apparu sur R2.
- [ ] T082 [P] [US3] [VALID] (SC-004, FR-017) Le drill mensuel T078 valide déjà le critère : restauration < 30 min, intégrité OK.
- [ ] T083 [P] [US3] [VALID] (FR-018) Simuler une panne de `pg-backup.sh` (ex : credentials R2 invalides temporairement) → notification Telegram d'échec reçue en < 15 min.

**Checkpoint US3** : les sauvegardes tournent, restent chiffrées et sont restaurables prouvably.

---

## Phase 6: User Story 4 — API stable pour outils internes (Priority: P2)

**Goal** : exposer une API REST contractuelle aux outils internes (n8n, dbt, scripts) avec clés API service séparées des comptes utilisateurs.

**Independent Test** : un script externe avec `SERVICE_ROLE_KEY` effectue `INSERT` puis `SELECT` sur une table de test et obtient des réponses cohérentes en < 2 s cumulées.

### Implementation for User Story 4

- [ ] T100 [US4] Vérifier dans Coolify que `SERVICE_ROLE_KEY` et `ANON_KEY` sont bien injectés dans le conteneur `postgrest` (logs d'initialisation PostgREST sans erreur de JWT).
- [ ] T101 [US4] Créer `infra/supabase/smoke-tests/api-contract.sh` : script qui (a) ping `GET /rest/v1/` avec `apikey: $ANON_KEY`, (b) tente un `POST /rest/v1/test_contract_table` sans JWT → doit renvoyer 401, (c) refait avec `SERVICE_ROLE_KEY` → 201, (d) `GET` vérifie persistence.
- [ ] T102 [US4] SSH sur VPS → `psql` → créer table `public.test_contract_table (id serial primary key, note text, created_at timestamptz default now())` **temporaire** pour le smoke-test (sera supprimée en polish).
- [ ] T103 [US4] [VALID] (User Story 4 scenarios 1-3, SC-006) Exécuter `infra/supabase/smoke-tests/api-contract.sh` depuis un poste extérieur. Chronométrer : < 2 s cumulées pour la séquence lecture-écriture-lecture.
- [ ] T104 [US4] [VALID] (SC-008) Déclencher une rotation de `JWT_SECRET` (Coolify UI → env var → nouvelle valeur → restart) → confirmer que l'ancienne `SERVICE_ROLE_KEY` renvoie 401 en < 5 min.
- [ ] T105 [US4] Documenter la procédure de rotation dans `docs/runbooks/supabase-secret-rotation.md` (fréquence trimestrielle JWT, annuel autres, action immédiate sur incident).

**Checkpoint US4** : l'API REST est utilisable contractuellement par les outils downstream. Les rotations sont maîtrisées.

---

## Phase 7: User Story 5 — Observabilité & notifications (Priority: P2)

**Goal** : le super-admin est notifié activement en cas d'indisponibilité, d'échec de sauvegarde, d'expiration de certificat, ou de disque plein.

**Independent Test** : arrêt volontaire d'un conteneur Supabase → alerte Telegram reçue en < 5 min. Certificat simulé à 13 jours d'expiration → alerte préventive.

### Implementation for User Story 5

- [ ] T120 [P] [US5] [UI Uptime Kuma] Ajouter 4 probes HTTPS sur `https://status.hma.business` :
  - `supabase-studio` : `HEAD https://supabase.hma.business/`
  - `supabase-auth` : `GET https://supabase.hma.business/auth/v1/health`
  - `supabase-rest` : `GET https://supabase.hma.business/rest/v1/`
  - `supabase-tls-cert` : mode "Certificate Expiry", seuil 14 jours
  Chaque probe : intervalle 60 s, retries 2, notifs Telegram + email.
- [ ] T121 [P] [US5] Créer `infra/supabase/monitoring/uptime-kuma-probes.yaml` : description déclarative des 4 probes (documentation, pas consommé par Uptime Kuma mais permet de rejouer en cas de migration).
- [ ] T122 [P] [US5] Créer `infra/supabase/monitoring/disk-alert.sh` : script bash qui lit `df --output=pcent /var/lib/docker` et pousse un webhook Telegram si > 80 %.
- [ ] T123 [US5] SSH sur VPS → copier `disk-alert.sh` vers `/usr/local/bin/` + entrée cron `*/15 * * * * /usr/local/bin/disk-alert.sh` (toutes les 15 min).
- [ ] T124 [P] [US5] [VALID] (SC-009, User Story 5 scenario 1) Arrêt volontaire du conteneur Studio via Coolify UI pendant 3 min → alerte Telegram reçue en < 5 min.
- [ ] T125 [P] [US5] [VALID] (User Story 5 scenario 2) Redémarrer le conteneur → notif de résolution Telegram reçue.
- [ ] T126 [P] [US5] [VALID] (FR-021) Dans Uptime Kuma → forcer un test du probe certificat → confirmer que l'alerte seuil 14 jours est fonctionnelle.
- [ ] T127 [US5] Rédiger `docs/runbooks/supabase-incident.md` : arbre de décision des incidents courants (DB down, auth down, backup KO, disque plein, cert bientôt expiré). Inclure les 5 cas du tableau §4 de `quickstart.md`.

**Checkpoint US5** : le super-admin est alerté activement sur tous les signaux critiques.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose** : finaliser la documentation, valider les SC transverses et purger les artefacts temporaires.

- [ ] T140 [P] [VALID] (SC-007) `grep -RIn --include='*.md' --include='*.sh' --include='*.yml' --include='*.yaml' -E "(JWT_SECRET|SERVICE_ROLE_KEY|ANON_KEY|POSTGRES_PASSWORD|RESTIC_PASSWORD|SMTP_PASS)=" C:/hmanagement/infra C:/hmanagement/docs` → doit renvoyer **zéro** ligne contenant une valeur (uniquement des noms de variables référencés).
- [ ] T141 [P] [VALID] (SC-007 bis) Inspecter Coolify UI logs des conteneurs `gotrue`, `postgrest`, `postgres` sur les 24 dernières heures → chercher toute fuite de secret. Résultat attendu : aucune.
- [ ] T142 [P] [VALID] (SC-010) Exécuter un `nmap -Pn -p 1-65535 supabase.hma.business` depuis un poste extérieur → seuls 80 (redirect) et 443 doivent apparaître `open`.
- [ ] T143 Cleanup post-US4 : SSH sur VPS → `psql ... DROP TABLE public.test_contract_table;` → supprimer la table temporaire créée en T102.
- [ ] T144 Finaliser `docs/runbooks/supabase-deploy.md` avec toutes les leçons du déploiement réel (variables qui ont posé problème, ordre d'injection des secrets, pièges Coolify).
- [ ] T145 Rédiger `docs/runbooks/supabase-secret-rotation.md` complet : procédure détaillée par type de secret (JWT, SMTP, R2, restic, dashboard, postgres).
- [ ] T146 Mettre à jour `CLAUDE.md` section "État du dépôt" : Sprint 1 jalon 1 complété, plateforme Supabase opérationnelle sur `supabase.hma.business`.
- [ ] T147 [VALID] Exécuter intégralement la checklist "smoke-test" de `quickstart.md` section 3 → tous les checks passent.
- [ ] T149 [P] [VALID] (FR-022) Tester `disk-alert.sh` en abaissant temporairement le seuil à `1` dans le script (ou via variable d'environnement dédiée) et lancer `/usr/local/bin/disk-alert.sh` → confirmer qu'une notification Telegram "disk > threshold" est bien reçue. Restaurer le seuil à 80 %.
- [ ] T148 Ouvrir une Pull Request de la branche `001-supabase-selfhost` vers `main` avec description pointant vers `specs/001-supabase-selfhost/` et demander la revue (Art. constitution 5.3).

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)** : aucune dépendance — démarre immédiatement.
- **Phase 2 (Foundational)** : dépend de Phase 1. **BLOQUE** toutes les US.
- **Phase 3 (US1)** : dépend de Phase 2.
- **Phase 4 (US2)** : dépend de US1 (GoTrue ne peut être configuré qu'une fois Supabase déployé).
- **Phase 5 (US3)** : dépend de US1 (il faut un PostgreSQL à sauvegarder). **Indépendant** de US2.
- **Phase 6 (US4)** : dépend de US1 (PostgREST doit être opérationnel). **Indépendant** de US2, US3.
- **Phase 7 (US5)** : dépend de US1 (endpoints doivent exister pour être surveillés). **Indépendant** de US2, US3, US4.
- **Phase 8 (Polish)** : dépend de toutes les US.

### User Story Dependencies

```
Setup ──▶ Foundational ──┬──▶ US1 ──┬──▶ US2 ─┐
                         │          ├──▶ US3 ─┼──▶ Polish
                         │          ├──▶ US4 ─┤
                         │          └──▶ US5 ─┘
```

### Within Each User Story

- Tâches d'implémentation sans dépendance mutuelle sont marquées `[P]`.
- Les tâches `[VALID]` s'exécutent après les tâches d'implémentation correspondantes.

### Parallel Opportunities

- Phase 1 : T001-T006 peuvent toutes s'exécuter en parallèle (créations de dossiers indépendants).
- Phase 2 : T018-T023 (génération secrets Vaultwarden) peuvent s'exécuter en parallèle.
- US2/US3/US4/US5 : indépendantes une fois US1 done → 4 développeurs pourraient avancer simultanément.
- Tâches `[VALID]` d'une même US : toutes parallèles.
- Phase 8 : T140, T141, T142 parallèles (inspection indépendante).

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Génération des secrets Supabase Vaultwarden en parallèle :
Task: "T018 — générer supabase-selfhost-jwt-secret"
Task: "T019 — générer supabase-selfhost-anon-key"
Task: "T020 — générer supabase-selfhost-service-role-key"
Task: "T021 — générer supabase-selfhost-postgres-password"
Task: "T022 — générer supabase-selfhost-dashboard-password"
Task: "T023 — générer supabase-selfhost-restic-password"
```

## Parallel Example: validation finale Polish

```bash
# Trois audits indépendants :
Task: "T140 — grep secrets en clair dans repo"
Task: "T141 — inspection logs Coolify"
Task: "T142 — nmap ports exposés"
```

---

## Implementation Strategy

### MVP First (US1 seul)

1. Complete Phase 1 (Setup) — T001 à T007.
2. Complete Phase 2 (Foundational) — T010 à T027. **CRITIQUE — bloque tout**.
3. Complete Phase 3 (US1) — T030 à T039.
4. **STOP et VALIDATE** : plateforme joignable, Studio accessible, PG répond.
5. À ce stade la feature a déjà de la valeur (accès admin) mais n'est **pas production-ready** : pas d'auth MFA, pas de backup, pas de monitoring.

### Incremental Delivery (recommandé)

Étapes successives, chacune démontrable :

1. Phase 1 + 2 → Foundation ready.
2. Phase 3 (US1) → Demo 1 : plateforme joignable.
3. Phase 4 (US2) → Demo 2 : auth MFA opérationnelle.
4. Phase 5 (US3) → Demo 3 : backups tournent + 1er drill OK.
5. Phase 7 (US5) → Demo 4 : monitoring actif, Telegram reçoit des alertes réelles.
6. Phase 6 (US4) → Demo 5 : API REST consommable par n8n/dbt.
7. Phase 8 → clôture + PR + revue + merge.

**Ordre suggéré** : US1 → US2 → US3 → US5 → US4 → Polish.
Rationale : US3 (backups) et US5 (monitoring) sont plus critiques en production que US4 (API REST consommée principalement par des features futures pas encore déployées).

### Parallel Team Strategy

Avec 2 personnes (Kiki + 1 binôme) :

1. Ensemble : Phase 1 + Phase 2.
2. Ensemble : Phase 3 (US1) — nécessite accès Coolify non partageable.
3. Parallélisation post-US1 :
   - Personne A : US2 (auth + rédaction runbook deploy)
   - Personne B : US3 (scripts backup + drill + R2)
4. Ensemble : US5 (monitoring — nécessite Uptime Kuma) puis US4 (API smoke-test).
5. Polish séquentiel.

---

## Notes

- `[P]` = fichiers différents, pas de dépendance bloquante.
- `[UI …]` = action manuelle dans l'interface du produit tiers (Coolify, Vaultwarden, Cloudflare, Brevo, Uptime Kuma, Telegram) — ne produit pas de fichier dans le repo mais reste traçable par le runbook correspondant.
- `[VALID]` = validation d'une SC-### ou d'un acceptance scenario de `spec.md` — à exécuter après les tâches d'implémentation de la même US.
- Chaque groupe de tâches complété doit déclencher un **commit dédié** (Art. constitution 5.3). Ex : "T001-T007 Setup arborescence", "T010-T027 Foundational", "T030-T039 US1 deploy", etc.
- Aucune tâche ne doit exposer un secret en clair dans le repo. Si un fichier accepte une valeur secrète, il utilise une variable d'environnement qui pointe vers Vaultwarden.
- Verifier `tests/` ? Non applicable : pas de code applicatif testé. Les smoke-tests (`infra/supabase/smoke-tests/`) + les drills de restauration sont la couche de validation.
- Tout blocage sur une tâche `[UI …]` (quota Brevo, clé R2 qui ne fonctionne pas, etc.) **MUST** être consigné comme incident dans `docs/runbooks/supabase-incident.md` ou dans les notes de PR.
