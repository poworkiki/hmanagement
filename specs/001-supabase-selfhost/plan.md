# Implementation Plan: Socle data self-hosted et souverain

**Branch**: `001-supabase-selfhost` | **Date**: 2026-04-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-supabase-selfhost/spec.md`

## Summary

Déployer une instance **Supabase self-hosted** (PostgreSQL + GoTrue + PostgREST + Supabase Studio + optionnellement Realtime & Storage) sur le VPS Hostinger `187.124.150.82` via **Coolify** (`https://coolify.hma.business`), exposée en HTTPS sur `supabase.hma.business` via Traefik (TLS Let's Encrypt automatique), avec :

- secrets centralisés dans **Vaultwarden** (`stack_hma`) et injectés dans Coolify comme variables d'environnement d'application,
- authentification **Magic Link + MFA TOTP obligatoire** pour `super_admin` / `admin`,
- sauvegardes PostgreSQL quotidiennes chiffrées vers **Cloudflare R2**, rétention 30 jours, test de restauration mensuel,
- monitoring disponibilité via **Uptime Kuma** existant (`status.hma.business`) + sondes applicatives Coolify,
- notifications opérationnelles via **Telegram (`hmagents_bot`)** et fallback email (`hmagestion@gmail.com`).

**Objectif North Star** : socle opérationnel au jour J+10 (cible MVP), zéro dépendance SaaS non-souveraine, zéro secret en clair dans le repo ou les logs.

## Technical Context

**Language/Version** : aucun code applicatif propre à cette feature. Artefacts produits = configuration Coolify + scripts shell (bash) + fichiers YAML pour probes et backups.
**Primary Dependencies** : Supabase stable `2025.x` (images officielles `supabase/postgres`, `supabase/gotrue`, `supabase/postgrest`, `supabase/studio`, `supabase/kong` ou Traefik reverse-proxy), Coolify ≥ v4, Traefik (livré par Coolify), `pg_dump` / `pg_restore` (PostgreSQL 15 client), `restic` 0.17+ pour backups chiffrés, `rclone` (optionnel) pour synchronisation vers R2.
**Storage** : PostgreSQL 15 (volume Docker persistant sur VPS Hostinger). Backups : Cloudflare R2 bucket `hma-supabase-backups` (chiffrement restic).
**Testing** : shell scripts de smoke-test + tests manuels de restauration (mensuel). Tests fonctionnels de l'app consommatrice hors scope (viennent avec les features suivantes).
**Target Platform** : Ubuntu 24.04 LTS sur VPS Hostinger 187.124.150.82, Docker via Coolify, Cloudflare pour DNS + CDN.
**Project Type** : **platform / infrastructure-as-code** (pas de monolithe Next.js dans cette feature — il est produit par une feature ultérieure).
**Performance Goals** :
- PostgreSQL : utilisation CPU < 40 % moyenne, espace disque < 60 % alerté à 80 %
- API REST auto (PostgREST) : p95 < 300 ms pour `SELECT 1` depuis le VPS, < 800 ms depuis Internet
- Redémarrage complet de la stack Supabase < 5 minutes
**Constraints** :
- Zéro SaaS non-souverain sur le chemin critique (contrainte constitutionnelle Article 2)
- Zéro secret en clair (Article 4.5)
- MFA obligatoire super_admin/admin (Article 4.3)
- Sauvegarde chiffrée quotidienne + test restauration mensuel (Article 10.3)
- Décision réversible maintenue : choix du provider R2 (Cloudflare) est réversible vers Backblaze B2 ou OVH Object Storage sans reconfiguration majeure de l'app
**Scale/Scope** : 1 tenant logique `hma` en MVP, 3 à 10 comptes utilisateurs à 6 mois, volume de données estimé < 50 GB à horizon 12 mois (factures/ventes/encaissements 4 filiales), charge < 10 req/s sur l'API.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Article constitution | Exigence | Respecté par ce plan ? | Notes |
|---|---|---|---|
| Art. 2 — Souveraineté | Données hébergées sur infra sous contrôle | ✅ | VPS Hostinger + Coolify self-hosted + R2 chiffré par clé HMA |
| Art. 3.1 — Paradigme ELT | Données brutes conservées dans `raw.*` | ✅ (préparé) | Schémas PostgreSQL seront créés par la feature *schémas-rls-bootstrap* suivante, pas par celle-ci ; volume PG prêt à les accueillir |
| Art. 3.4 — Stack figée | Supabase self-hosted obligatoire | ✅ | Aucune déviation |
| Art. 4.1 — Moindre privilège | Rôles DB applicatifs sans `BYPASSRLS` | ✅ (préparé) | Création du rôle applicatif renvoyée à la feature suivante, mais préparée (voir Assumptions plan) |
| Art. 4.2 — RLS | RLS sur `marts.*` et `app.*` | N/A ici | Pas de schéma applicatif dans cette feature |
| Art. 4.3 — Auth forte | Magic Link + MFA TOTP obligatoire admin | ✅ | GoTrue configuré avec TOTP obligatoire post-premier-login via politique d'équipe |
| Art. 4.4 — Audit trail | Actions sensibles tracées | ✅ (préparé) | Logs GoTrue → journal événements auth ; table `app.audit_log` viendra avec la feature suivante |
| Art. 4.5 — Secrets | Jamais en clair dans le code | ✅ | Tous les secrets dans Vaultwarden, injectés via Coolify env UI |
| Art. 10.1 — Pipeline notifié | Notifications fin de job | ✅ | Cron backup → webhook Telegram bot `hmagents_bot` |
| Art. 10.2 — Monitoring | Métriques visualisées | ✅ | Uptime Kuma pour disponibilité ; Coolify dashboard pour conteneurs ; Grafana reporté à une feature ultérieure (YAGNI) |
| Art. 10.3 — Sauvegardes | Quotidiennes + test restauration mensuel | ✅ | Cron quotidien + runbook + rappel calendrier mensuel |
| Art. 11.1 — Strangler Fig | Évolution progressive | ✅ | Peut cohabiter avec Supabase Cloud existants (`uhuvuhyszrudzgcefolo.supabase.co` en veille) |
| Art. 12 — North Star | < 30s entre clôture Pennylane et décision | N/A ici | Cette feature pose le socle ; la métrique sera pilotée par les features app & pipelines |

**Résultat gate** : ✅ Pass. Aucune violation. Aucune inscription dans le tableau *Complexity Tracking*.

## Project Structure

### Documentation (this feature)

```text
specs/001-supabase-selfhost/
├── spec.md                          # What & Why (déjà présent)
├── plan.md                          # This file (/speckit-plan)
├── research.md                      # Phase 0 output — décisions techniques motivées
├── data-model.md                    # Phase 1 output — entités de plateforme
├── quickstart.md                    # Phase 1 output — procédure opérateur
├── contracts/
│   ├── platform-env-contract.md     # Contrat env vars & secrets Vaultwarden → Coolify
│   └── admin-api-contract.md        # Surface d'accès externe (PostgREST, GoTrue, Studio, API key service)
├── checklists/
│   └── requirements.md              # déjà présent
└── tasks.md                         # Phase 2 output (/speckit-tasks — NON créé ici)
```

### Source Code (repository root)

Cette feature ne produit **pas** de code applicatif Next.js / dbt / n8n. Elle produit de la configuration, des runbooks et des scripts d'ops. Cible :

```text
infra/
└── supabase/
    ├── README.md                    # pointeur vers specs/001-supabase-selfhost/
    ├── coolify-service.yml          # déclaratif Coolify (si export disponible) OU docker-compose de référence
    ├── env.reference                # liste exhaustive des variables d'environnement requises (valeurs = placeholders)
    ├── gotrue-config-overrides.yml  # overrides GoTrue (MFA forcé, session 1h admin / 8h user, rate-limits)
    └── backups/
        ├── pg-backup.sh             # pg_dump + chiffrement restic + push R2
        ├── pg-restore.sh            # procédure restore test
        ├── backup.cron              # unité cron quotidienne
        └── README.md                # runbook backup / restore

docs/
├── runbooks/
│   ├── supabase-deploy.md           # bootstrap depuis Coolify UI (référence détaillée)
│   ├── supabase-secret-rotation.md  # rotation JWT / SMTP / DB password
│   ├── supabase-restore-drill.md    # drill restauration mensuelle (checklist datée)
│   └── supabase-incident.md         # arbre de décision incident (DB down, auth down, backup KO)
└── adr/
    └── ADR-001-supabase-self-hosted-via-coolify.md   # décision architecturale majeure
```

**Structure Decision** : pas de tree `src/` ni de tests Vitest/Playwright dans cette feature. Les artefacts sont des fichiers shell, YAML et Markdown regroupés sous `infra/supabase/` et `docs/runbooks/`. `infra/` est un **nouveau dossier top-level** introduit par cette feature — il accueillera à terme tout ce qui concerne l'infrastructure déclarative (Coolify services, Traefik, n8n workflows stockés en repo, etc.). Choix cohérent avec l'Article 11.1 (Strangler Fig) : l'infra part simple, dédiée Supabase, et grossit par ajout sans refactor.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

*Aucune violation. Tableau volontairement laissé vide.*
