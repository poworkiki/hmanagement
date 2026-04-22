# Phase 0 — Research : Socle data self-hosted et souverain

**Feature** : `001-supabase-selfhost`
**Date** : 2026-04-22

Synthèse des décisions techniques prises pour permettre l'exécution de la feature. Chaque entrée suit le format : *Decision → Rationale → Alternatives considered*. Toutes les `NEEDS CLARIFICATION` du plan technique ont été résolues ici.

---

## R-001 — Méthode de déploiement Supabase sur Coolify

**Decision** : utiliser le **service "Supabase" pré-packagé de Coolify v4** (one-click template officiel), puis surcharger les variables d'environnement via l'UI Coolify. Stocker un **docker-compose de référence** dans `infra/supabase/coolify-service.yml` pour documentation et disaster recovery, même si la source de vérité d'exécution reste Coolify.

**Rationale** :
- Coolify v4 maintient officiellement le template Supabase (incluant postgres, gotrue, postgrest, storage, realtime, kong ou traefik route, studio).
- Évite de réécrire/maintenir une stack Docker Compose identique à celle de Supabase — KISS (Art. 7.1), YAGNI (Art. 7.2).
- Les mises à jour de version Supabase passent par un seul bouton dans Coolify.
- Le docker-compose de référence dans le repo sert de **fallback de reconstruction** en cas de perte Coolify — aligné avec Strangler Fig (Art. 11.1).

**Alternatives considered** :
- *Docker Compose custom déployé via Coolify "Docker Compose" app* : rejeté — duplication de maintenance sans valeur ajoutée.
- *Supabase CLI + `supabase start` sur VPS nu* : rejeté — sort complètement de l'orchestration Coolify (contradiction avec la stack figée Art. 3.4).
- *Supabase Cloud payant* : rejeté — viole l'Article 2 (souveraineté).
- *Nix + Docker déclaratif* : rejeté — sur-ingénierie pour Sprint 1.

---

## R-002 — Nom de domaine et stratégie TLS

**Decision** : exposer l'instance sur **`supabase.hma.business`** (un seul sous-domaine pour Studio + API REST + Auth, routing par path géré par Kong/Traefik). Certificat **Let's Encrypt** auto-renouvelé par Traefik (intégré à Coolify). Alerte préventive 14 jours avant expiration déléguée à Uptime Kuma (certificat monitoring déjà supporté).

**Rationale** :
- `supabase.hma.business` est parfaitement explicite et aligné avec la convention existante (`n8n.hma.business`, `auth.hma.business`, etc.).
- Un seul certificat simplifie l'opérations et réduit la surface de faille.
- Let's Encrypt est gratuit, reconnu par les navigateurs et renouvelé automatiquement (FR-002, FR-021, SC-001).

**Alternatives considered** :
- *`db.hma.business`* : rejeté — trop générique, ne signale pas la stack Supabase spécifiquement.
- *Sous-domaines multiples (`studio.hma.business`, `api.hma.business`, `auth.hma.business`)* : rejeté — 3× la config, aucune valeur opérationnelle au MVP. Réversible plus tard si besoin.
- *Cloudflare Tunnel devant Traefik* : reporté — intéressant pour masquer l'IP du VPS mais non requis MVP (YAGNI).
- *Certificat EV/OV payant* : rejeté — aucun gain utilisateur final, Let's Encrypt est suffisant.

---

## R-003 — ~~Provider SMTP transactionnel~~ **SUPERSEDED par R-011** (/speckit-clarify 2026-04-22)

> **Status** : **Superseded**. La décision initiale (Brevo comme SMTP pour Magic Link natif GoTrue) a été remplacée par la délégation complète de l'auth à Authentik (voir R-011). Aucun compte SMTP externe n'est nécessaire pour cette feature — Authentik utilise son propre SMTP déjà configuré.
>
> Le contenu ci-dessous est conservé pour traçabilité historique. Ne PAS l'exécuter.

~~**Decision** : Brevo (ex-Sendinblue) plan gratuit…~~

~~**Rationale** : siège européen RGPD, quota gratuit suffisant…~~

~~**Alternatives considered** : Mailgun/SendGrid US rejetés, Postfix self-hosted rejeté pour délivrabilité.~~

---

## R-004 — Stratégie de sauvegarde

**Decision** :
- **Moteur** : `pg_dump -Fc` (format custom) quotidien à 03h30 heure VPS (04h30 UTC-3 = 07h30 Europe/Paris), déclenché par **cron système** (pas par n8n — découplage total de l'orchestrateur pour ne pas dépendre d'un service tiers pour la sécurité des données).
- **Chiffrement** : `restic` avec repository Cloudflare R2, **clé de chiffrement stockée dans Vaultwarden** (jamais sur le VPS hors mémoire).
- **Cible de stockage** : bucket Cloudflare **R2** `hma-supabase-backups` (pay-as-you-go, zéro egress fees, datacenter EU).
- **Rétention** : 30 dernières sauvegardes quotidiennes + 12 mensuelles (le 1er de chaque mois), purge automatique restic `forget --keep-daily 30 --keep-monthly 12`.
- **Test mensuel** : restauration automatisée tous les 1er du mois sur un container PostgreSQL éphémère, vérification smoke-test `SELECT count(*)` sur au moins 3 tables critiques (rendez-vous runbook `supabase-restore-drill.md`).

**Rationale** :
- `pg_dump -Fc` est la méthode standard Supabase, compatible `pg_restore` point-in-time au fichier près (FR-014, FR-017).
- `restic` chiffre au niveau repository (AES-256) + déduplique les blocks → taille backup réelle bien inférieure à la somme brute (FR-015).
- Cloudflare R2 : zéro egress (restore sans coût bande passante), certifié EU, l'équipe a déjà un compte CF et un API token (crédentiel listé).
- Cron système > n8n : n8n est lui-même hébergé sur le même VPS (risque de panne corrélée). Indépendance critique sur les sauvegardes (Art. 4.5 esprit).
- Test mensuel automatisé évite la dérive silencieuse des sauvegardes (Art. 10.3).

**Alternatives considered** :
- *Supabase point-in-time recovery (PITR)* : nécessite des paquets premium Supabase — reporté à une V2 si besoin.
- *Barman* : fonctionnel mais complexité opérationnelle supérieure pour 1 seule instance.
- *Backblaze B2* : équivalent R2 mais frais d'egress non nuls (B2 a un quota gratuit modeste). R2 gagne sur le total cost of ownership si restores fréquents.
- *OVH Object Storage (S3 compatible)* : option de repli retenue comme alternative à R2 si CF devient indésirable.
- *Sauvegarde vers un second VPS HMA (`168.231.69.226`)* : rejeté en primaire — reste la même panne potentielle (même provider, même région géographique probable). Pourrait être ajouté en secondaire ultérieurement.

---

## R-005 — Monitoring & notifications

**Decision** :
- **Disponibilité (uptime)** : **Uptime Kuma** existant (`https://status.hma.business`) → nouvelles sondes HTTPS sur `https://supabase.hma.business/rest/v1/` (PostgREST), `https://supabase.hma.business/auth/v1/health` (GoTrue), `https://supabase.hma.business/` (Studio). Cadence : 60 s. Alerte après 2 échecs consécutifs (≈ 2 min, conforme FR-020 / SC-009).
- **Canal de notification** : **Telegram** via `hmagents_bot` (secret présent) en primaire + **email** `hmagestion@gmail.com` en secondaire. Configuré au niveau Uptime Kuma.
- **Certificat TLS** : Uptime Kuma supporte nativement l'alerte préventive (seuil 14 jours, conforme FR-021).
- **Santé conteneurs / CPU / RAM / disque** : dashboard Coolify natif consulté à la demande ; alerte disque 80 % via script cron dédié (`df --output=pcent` → webhook Telegram si > 80 %) — conforme FR-022.
- **Métriques PostgreSQL détaillées (Prometheus + `postgres_exporter`)** : **reporté à une feature ultérieure** (YAGNI Art. 7.2). Besoin non prouvé en MVP et surveillance existante Uptime Kuma + Coolify suffit à couvrir tous les SC.
- **Journal événements auth** : les logs GoTrue sont agrégés par Docker et consultables via Coolify. Rétention par défaut 7 jours, suffisante pour un audit initial (FR-023). Persistence long terme reportée à la feature *observability-stack*.

**Rationale** :
- Réutilise exhaustivement ce qui existe (Uptime Kuma, Telegram bot, Coolify dashboard) — KISS.
- Chaque SC (001, 005, 009) adressé par une sonde / seuil mesurable et vérifiable.
- Report explicite de Prometheus/Grafana : aucune SC n'exige des métriques fines de PostgreSQL en MVP.

**Alternatives considered** :
- *Grafana + Prometheus + postgres_exporter dès Sprint 1* : rejeté — sur-ingénierie, aucun besoin MVP prouvé.
- *Pingdom / Betterstack SaaS* : rejeté — SaaS non souverain.
- *Datadog* : rejeté — idem + coût.

---

## R-006 — Gestion des secrets Vaultwarden → Coolify

**Decision** :
- Tous les secrets vivent dans **Vaultwarden** (`vaultwarden.poworkiki.cloud`, org `stack_hma`).
- Ajouter à Vaultwarden les 10 secrets requis par Supabase (voir `contracts/platform-env-contract.md`) sous le préfixe **`supabase-selfhost-*`** pour identification.
- Injection dans Coolify : **copier-coller manuel** dans l'UI Coolify "Environment Variables" de l'application Supabase à la création. Marquer chaque variable "**secret / masked**".
- **Aucun** fichier `.env` n'est versionné ni stocké sur le VPS hors mémoire Docker.
- Rotation : procédure manuelle documentée dans `docs/runbooks/supabase-secret-rotation.md` — cadence cible **trimestrielle** pour `JWT_SECRET` et `SERVICE_ROLE_KEY`, **annuelle** pour les credentials SMTP et R2 (ou immédiate sur incident).

**Rationale** :
- Vaultwarden est déjà la source de vérité des 41 secrets stack HMA (Art. 4.5).
- Injection manuelle dans Coolify = simple, auditable, zéro nouvelle dépendance. Automatiser via API Coolify est possible mais apporte plus de surface d'attaque que de valeur (YAGNI).
- Rotation trimestrielle JWT / service role : compromis raisonnable entre hygiène de sécurité et coût opérationnel (pas de session utilisateur perdue car TTL courts).

**Alternatives considered** :
- *HashiCorp Vault + Vault Agent* : sur-ingénierie MVP.
- *Doppler / Infisical* : SaaS payant, réplique Vaultwarden sans valeur ajoutée propre.
- *Secrets dans `.env.local` versionné chiffré (SOPS + age)* : envisageable plus tard si le besoin de git-ops émerge ; reporté.
- *Coolify Secrets API auto-synchronisée avec Vaultwarden* : à réévaluer en V2 (script dédié).

---

## R-007 — Politique d'authentification GoTrue (Magic Link + MFA TOTP obligatoire)

**Decision** :
- `GOTRUE_EXTERNAL_EMAIL_ENABLED=true`, `GOTRUE_MAILER_AUTOCONFIRM=false` → lien magique explicite requis.
- `GOTRUE_SECURITY_UPDATE_PASSWORD_REQUIRE_REAUTHENTICATION=true`.
- `GOTRUE_MFA_ENABLED=true` + policy applicative : **rejeter toute session dont `aal < aal2`** pour les rôles `super_admin` / `admin` (enforcement via middleware applicatif dans la feature app suivante + via policy SQL dès que les rôles DB existent).
- TTL : `GOTRUE_JWT_EXP=3600` (1 h) pour les tokens — renouvellement silencieux côté client.
- Session admin : **1 h** côté GoTrue + enforcement applicatif 1 h. Utilisateur standard : **8 h** configuré via une deuxième application ou logique applicative (GoTrue est global ; l'enforcement fin par rôle se fera côté middleware app).
- **Password leak detection** : `GOTRUE_SECURITY_PASSWORDS_HIBP_ENABLED=true` (Have I Been Pwned) — conforme FR-010.
- **Rate-limit émission Magic Link** : `GOTRUE_RATE_LIMIT_EMAIL_SENT=10` par heure par IP (FR-013 volet émission).
- **Rate-limit vérification / login** : `GOTRUE_RATE_LIMIT_VERIFY=30` par heure par IP + `GOTRUE_RATE_LIMIT_TOKEN_REFRESH=150` par heure par IP (FR-013 volet consommation — anti brute-force sur les endpoints `/verify` et `/token`).
- **Identification IP réelle derrière reverse-proxy** : `GOTRUE_RATE_LIMIT_HEADER=X-Real-IP` + `GOTRUE_SECURITY_MANUAL_LINKING_ENABLED=false`.
- **TTL Magic Link** : `GOTRUE_OTP_EXP=900` (15 min) — conforme FR-009. **À valider au déploiement** : certaines versions de GoTrue utilisent `GOTRUE_MAILER_OTP_EXP` — l'intention TTL = 15 min reste fixe.

**Rationale** :
- Couvre FR-006, FR-007, FR-008, FR-009, FR-010, FR-013.
- MFA activé globalement ; la granularité "obligatoire pour admin" se fait via policy applicative car GoTrue ne permet pas de rendre MFA conditionnel par rôle avant v2.170+ (à vérifier au déploiement — fallback documenté : obliger TOUS les utilisateurs à activer MFA au premier login).
- **FR-008 note scope MVP** : seuls des comptes administrateur existent au MVP (cap 1 h uniforme via `GOTRUE_JWT_EXP=3600`). La différenciation session 8 h pour utilisateurs non-admin sera enforcée par le middleware applicatif dès l'introduction des rôles `controleur` / `consultant` dans la feature suivante `002-schemas-rls-bootstrap` ou la feature app.

**Alternatives considered** :
- ~~*Intégration Authentik (SSO) comme IdP OIDC de GoTrue* : reporté V2~~ → **RETENU finalement** (voir R-011). L'ouverture multi-tenant SaaS n'est plus le trigger ; la décision est prise dès le MVP suite à /speckit-clarify 2026-04-22, car (a) élimine la création d'un compte Brevo (Art. 2 souveraineté renforcée), (b) centralise l'auth avec le reste du stack HMA (n8n, Authentik lui-même), (c) évite la duplication des mécanismes Magic Link + MFA entre GoTrue et Authentik.
- *Auth par mot de passe + MFA* : rejeté — la spec impose Magic Link (FR-006).
- *Passkeys (WebAuthn)* : intéressant mais encore expérimental côté GoTrue, reporté V2.

---

## R-008 — Clés API service & révocation

**Decision** :
- Exposer **3 clés API service distinctes** à la mise en service :
  1. `ANON_KEY` — lecture publique limitée par RLS (usage app front SSR si besoin)
  2. `SERVICE_ROLE_KEY` — bypass RLS, **réservée aux workflows n8n et aux scripts de maintenance admin**
  3. `DBT_USER_PASSWORD` — compte DB dédié à dbt (pas une "clé" Supabase mais un rôle PG) — créé par la feature suivante, placeholder ici.
- **Révocation** = rotation du secret Supabase (`JWT_SECRET`) via runbook. Impact : toutes les sessions utilisateurs & clés invalidées → conforme SC-008 (effet < 5 min entre rotation + redéploiement Coolify).
- Révocation granulaire d'une seule clé API service : **non disponible nativement** dans Supabase self-hosted (limite produit). Atténuation : rotations globales documentées + provisioning individuel via `api_keys` app-level (reporté à la feature app si nécessaire).

**Rationale** :
- Couvre FR-011 pour les besoins MVP (peu de clés, rotation globale acceptable).
- Explicite la limite produit pour éviter une fausse promesse de granularité fine.

**Alternatives considered** :
- *Construire une couche `app.api_keys` custom* : reporté — aucun besoin prouvé en MVP (1 seul tenant, peu de clés).

---

## R-009 — Environnement de restauration mensuelle

**Decision** : spinner d'un container PostgreSQL 15 éphémère sur le même VPS, nommé `pg-restore-drill`, sur réseau Docker isolé, qui :
1. télécharge depuis R2 la dernière sauvegarde disponible,
2. restaure avec `pg_restore`,
3. exécute un script de smoke-test SQL (`SELECT now()`, `SELECT count(*) FROM pg_tables`, plus tests métier quand les schémas existeront),
4. publie le résultat dans Telegram + ajoute un log horodaté à `docs/runbooks/restore-drill-log.md`,
5. détruit le container.

Déclenché par cron le 1er de chaque mois à 05h00 VPS.

**Rationale** : automatise l'obligation Art. 10.3 sans consommer la production (container isolé, durée < 15 min).

**Alternatives considered** :
- *Drill sur VPS secondaire `168.231.69.226`* : reporté — pas nécessaire MVP, ajouterait latence et complexité réseau.
- *Drill entièrement manuel* : rejeté — dérive garantie sur 6 mois.

---

## R-010 — Positionnement vis-à-vis de l'existant "Supabase Cloud" (en veille)

**Contexte** : l'organisation a déjà deux projets Supabase Cloud (`uhuvuhyszrudzgcefolo.supabase.co`) marqués "en veille" dans l'inventaire credentials.

**Decision** :
- La nouvelle instance self-hosted `supabase.hma.business` **remplace** l'usage MVP de ces projets.
- Les projets Cloud existants ne sont **pas supprimés** mais archivés : changement d'état logique "veille" → "archivé pour historique", aucune donnée y est poussée par hmanagement.
- Migration de données ? **Non requis** : les projets Cloud en veille n'ont pas encore reçu de données de production HMA.

**Rationale** : zéro duplication de surface d'attaque, zéro facture latente côté Supabase Cloud (toujours en plan gratuit de toute façon).

---

## Synthèse des NEEDS CLARIFICATION résolus

| # | Sujet | Valeur retenue |
|---|---|---|
| 1 | Méthode déploiement | Template Coolify v4 officiel Supabase |
| 2 | Sous-domaine | `supabase.hma.business` |
| 3 | Provider SMTP | Brevo plan gratuit (fallback SES Paris) |
| 4 | Provider backup | Cloudflare R2 `hma-supabase-backups` |
| 5 | Rétention backups | 30 quotidiennes + 12 mensuelles |
| 6 | Canal notif | Telegram `hmagents_bot` + email secondaire |
| 7 | Enforcement MFA | Global GoTrue + fallback applicatif |
| 8 | Prometheus/Grafana MVP | Reporté (YAGNI) |
| 9 | Rotation secrets | JWT trimestriel, SMTP/R2 annuel |
| 10 | SSO Authentik | Reporté V2 |

---

## R-011 — Délégation OIDC à Authentik (remplace R-003 + amende R-007)

**Added** : 2026-04-22 via `/speckit-clarify` (Session 2026-04-22, question 1). Supersede R-003.

**Decision** : GoTrue (Supabase) est configuré comme **OIDC relying party** de l'IdP self-hosted Authentik déjà déployé (`https://auth.hma.business`). Toute la logique d'authentification utilisateur (Magic Link, MFA TOTP, sessions, rate-limits, HIBP) est enforcée côté Authentik. GoTrue désactive son Magic Link natif (`GOTRUE_EXTERNAL_EMAIL_ENABLED=false`) et accepte uniquement les tokens OIDC validés par Authentik.

**Config concrète** :
- Côté **Authentik** : créer une Application OAuth2/OIDC `supabase-hma`, provider avec redirect URI `https://supabase.hma.business/auth/v1/callback`, groupe `supabase-hma-admins` avec policy MFA TOTP obligatoire.
- Côté **GoTrue** : injecter `GOTRUE_EXTERNAL_KEYCLOAK_ENABLED=true`, `GOTRUE_EXTERNAL_KEYCLOAK_URL=https://auth.hma.business/application/o/supabase-hma/`, `GOTRUE_EXTERNAL_KEYCLOAK_REDIRECT_URI`, `GOTRUE_EXTERNAL_KEYCLOAK_CLIENT_ID` (Vaultwarden), `GOTRUE_EXTERNAL_KEYCLOAK_SECRET` (Vaultwarden).
- Côté **Vaultwarden** : 2 nouveaux secrets `supabase-selfhost-oidc-client-id` et `supabase-selfhost-oidc-client-secret`.

**Rationale** :
- **Élimine la création d'un compte Brevo** (et toute la config SPF/DKIM/DMARC qui va avec).
- **Souveraineté renforcée** : 1 dépendance SaaS externe en moins (Art. 2).
- **Centralisation auth** : un seul point de gestion des utilisateurs pour tout le stack HMA (n8n, Authentik, Supabase, futures apps). Aligné avec l'esprit V2 multi-tenant : quand un nouveau tenant arrive, il a son propre groupe Authentik, scoping naturel.
- **Réutilise la confiance opérationnelle** : Authentik tourne déjà en production, son SMTP est éprouvé, pas de nouveau canal à valider.
- **Enforcement MFA plus propre** : policy Authentik par groupe = plus simple et plus auditable que policy applicative custom.

**Alternatives considered** :
- *Magic Link natif GoTrue + SMTP Brevo* (décision précédente R-003) : rejeté à /speckit-clarify — friction compte Brevo, duplication mécanismes auth entre 2 briques HMA.
- *Password + TOTP sans Magic Link, sans OIDC* : viable (zéro SMTP) mais perd le bénéfice SSO avec le reste du stack et UX moins bonne.
- *Cloudflare Access devant Supabase* : léger mais SaaS US, compromis sur souveraineté, OTP limité à 50 users free tier.

**Conséquences à traquer** :
- Dépendance opérationnelle dure à Authentik : si Authentik down, login Supabase KO. Mitigation : Authentik tourne sur Coolify avec les mêmes garanties ops que Supabase, pas d'aggravation nette.
- Complexité accrue du runbook deploy : +1 étape de création app OAuth côté Authentik (5-10 min).
- Impact tasks.md : T014-T017 Brevo remplacés par T014-T017 Authentik OAuth setup. T050-T058 (US2) reformulés pour flow OIDC.

**Variables rendues inutiles côté GoTrue** : `GOTRUE_SMTP_*`, `GOTRUE_OTP_EXP`, `GOTRUE_MFA_ENABLED`, `GOTRUE_SECURITY_PASSWORDS_HIBP_ENABLED`, `GOTRUE_RATE_LIMIT_EMAIL_SENT`, `GOTRUE_RATE_LIMIT_VERIFY`, `GOTRUE_RATE_LIMIT_TOKEN_REFRESH`. Leur équivalent fonctionnel vit côté Authentik (Password Policies, Rate-Limit Stages, Token validity).

---

**Phase 0 terminée.** Aucune clarification résiduelle bloquante. Phase 1 peut démarrer.
