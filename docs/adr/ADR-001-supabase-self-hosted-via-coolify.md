# ADR-001 : Supabase self-hosted déployé via Coolify

- **Date** : 2026-04-22
- **Statut** : Accepted
- **Décideurs** : Kiki (super-admin) — contexte Sprint 1, feature MVP
- **Contexte feature** : [001-supabase-selfhost](../../specs/001-supabase-selfhost/)

## Contexte

hmanagement est un dashboard financier DAF/CFO pour le groupe HMA, avec une stratégie de pivot vers SaaS multi-tenant ultra-marin. Le MVP vise un déploiement mono-tenant souverain.

Le socle data de la plateforme doit fournir :
- une base PostgreSQL avec architecture 4 schémas (`raw`, `staging`, `marts`, `app`),
- une authentification forte (Magic Link + MFA TOTP),
- une API REST / GraphQL auto-générée pour les apps consommatrices,
- des sauvegardes chiffrées quotidiennes testées mensuellement,
- hébergement sous contrôle direct (pas de SaaS américain non-souverain).

**Contraintes constitutionnelles non-négociables** ([`.specify/memory/constitution.md`](../../.specify/memory/constitution.md)) :
- Art. 2 — Souveraineté : hébergement sur infra sous contrôle
- Art. 3.4 — Stack figée (Supabase self-hosted obligatoire)
- Art. 4.3 — MFA TOTP obligatoire super_admin / admin
- Art. 4.5 — Secrets jamais en clair
- Art. 10.3 — Sauvegardes quotidiennes + test restauration mensuel

**Ressources existantes** :
- VPS Hostinger `187.124.150.82` (Ubuntu 24.04)
- Coolify v4 déjà en place sur `https://coolify.hma.business`
- Vaultwarden org `stack_hma` pour les secrets
- Cloudflare DNS pour `hma.business`
- Uptime Kuma + Telegram bot `hmagents_bot` pour monitoring
- Deux projets Supabase Cloud "en veille" sur `uhuvuhyszrudzgcefolo.supabase.co`

## Options considérées

### Option A — Supabase Cloud (pricing payant)

- ✅ Zéro ops, updates gérées par Supabase Inc.
- ✅ PITR disponible sur plan Pro
- ❌ **Viole Art. 2** : données financières HMA hébergées sur AWS US / EU géré par un tiers
- ❌ Pricing croissant avec le volume, verrou de facto
- ❌ Latence potentielle depuis la Guyane (datacenters US ou EU-west)

**Rejeté** pour non-souveraineté.

### Option B — Supabase self-hosted via Docker Compose custom (bricolage)

- ✅ Contrôle total
- ✅ Portable vers n'importe quel Docker
- ❌ Maintenance du compose file = duplication de ce que Supabase maintient déjà
- ❌ Ajout manuel de Traefik, Let's Encrypt, réseau, volumes — surface d'erreur élevée
- ❌ Pas d'intégration UI avec l'écosystème Coolify existant (monitoring, logs, redeploy)

**Rejeté** pour complexité opérationnelle sans valeur ajoutée (YAGNI Art. 7.2).

### Option C — Supabase self-hosted via **template Coolify officiel** ← retenue

- ✅ Coolify v4 maintient un template "Supabase" officiel (one-click)
- ✅ Intégration native avec Traefik + Let's Encrypt déjà en place dans Coolify
- ✅ Dashboard de monitoring container, logs, redeploy via UI
- ✅ Couple bien avec les autres apps Coolify existantes (`n8n.hma.business`, `auth.hma.business`, etc.)
- ✅ Réversible : un `docker-compose.yml` de référence peut être versionné pour reconstruction hors-Coolify en cas de besoin
- ⚠️ Dépendance au maintien du template par la communauté Coolify
- ⚠️ Les versions de Supabase / GoTrue dépendent du rythme de mise à jour du template (typiquement quelques jours de retard)

### Option D — Supabase CLI (`supabase start`) sur VPS nu

- ✅ Outil officiel Supabase, fidèle à la config attendue
- ❌ Sort complètement de l'orchestration Coolify → contradiction avec la stack figée
- ❌ Pas de reverse-proxy automatique, pas d'intégration TLS
- ❌ Migration ultérieure vers Coolify non triviale

**Rejeté** pour fragmentation de l'écosystème d'ops.

## Décision

**Déployer Supabase via le template Coolify officiel**, avec :

1. **Domaine** : `supabase.hma.business` (DNS-only Cloudflare, TLS Let's Encrypt via Traefik).
2. **Secrets** : 11 entrées dans Vaultwarden préfixées `supabase-selfhost-*`, injectées manuellement dans Coolify UI à la création (les ✅ marqués "Masked"). Aucun `.env` versionné.
3. **Persistance** : volume Docker dédié pour `/var/lib/postgresql/data` (Coolify-managed).
4. **Sauvegardes** : `pg_dump -Fc` → `restic` → Cloudflare R2 `hma-supabase-backups` (daily, rétention 30 + 12). Drill mensuel automatisé. **Cold storage papier** du `RESTIC_PASSWORD` obligatoire (T023.5 gate).
5. **Monitoring** : 4 sondes Uptime Kuma (Studio, Auth, REST, cert TLS) + alertes Telegram via **chat HMA existant** + disk-alert sur `/var/lib/docker`.
6. ~~**SMTP Magic Link** : Brevo plan gratuit, fallback AWS SES Paris.~~ **Superseded** → voir point 6bis.
7. ~~**GoTrue** : Magic Link + MFA TOTP global obligatoire, rate-limits stricts.~~ **Superseded** → voir point 7bis.

### Amendement /speckit-clarify 2026-04-22

6bis. **Authentification déléguée à Authentik OIDC** (`auth.hma.business`) — aucun SMTP Brevo à provisionner, aucun nouveau compte SaaS externe. GoTrue = OIDC relying party.
7bis. **GoTrue** : Magic Link natif désactivé (`GOTRUE_EXTERNAL_EMAIL_ENABLED=false`), provider OIDC Keycloak activé (`GOTRUE_EXTERNAL_KEYCLOAK_*`). MFA TOTP obligatoire **enforcé côté Authentik** (groupe `supabase-hma-admins` avec policy MFA). Rate-limits + HIBP reportés côté IdP.

8. **Docker Compose de référence** versionné dans `infra/supabase/coolify-service.yml` (ou équivalent exporté depuis Coolify) — pour disaster recovery uniquement, pas source d'exécution.

### Ce que cette décision **n'inclut PAS**

- La création des schémas applicatifs (`raw`, `staging`, `marts`, `app`) et des rôles DB — c'est la feature **002-schemas-rls-bootstrap** qui s'en occupe.
- L'invitation et la gestion des utilisateurs finaux — future feature.
- L'intégration Authentik comme IdP OIDC (reporté V2).
- Prometheus + Grafana — reporté à une feature d'observabilité.

## Conséquences

### Positives

- **Mise en production rapide** (cible < 10 jours) grâce au template one-click.
- **Stack cohérente** avec l'existant HMA (Coolify, Vaultwarden, Cloudflare, Uptime Kuma).
- **Souveraineté totale** : données, backups chiffrés, secrets, tous sous contrôle HMA.
- **Réversibilité** : en cas d'abandon de Coolify, le `compose` de référence permet de redéployer ailleurs.

### Négatives (coûts acceptés)

- **Dépendance opérationnelle à Coolify** : une panne Coolify = downtime de redeploy / restart. Mitigation : Coolify est simple à réinstaller, données persistent dans les volumes Docker.
- **Mises à jour Supabase non instantanées** : décalage de quelques jours sur les releases. Mitigation : pas un problème MVP, le cycle d'upgrade sera trimestriel.
- **Configuration manuelle des env vars dans Coolify UI** : tatou de 12 secrets à copier-coller. Mitigation : runbook d'installation explicite + fichier `env.reference` versionné pour la vérification croisée.
- **Pas de PITR natif** : granularité de restauration = J-1 minimum. Mitigation : conforme FR-014, PITR reporté en V2 si métrique de perte acceptable le justifie.

### Suivi (monitoring de la décision)

- **Signal d'obsolescence** : si le template Coolify devient abandonné (issues non résolues > 6 mois), évaluer la migration vers compose custom.
- **Signal de pression** : si > 2 pannes Coolify par trimestre, ré-évaluer la stratégie de séparation data / orchestration.
- **Signal de volume** : si taille PG > 50 GB ou charge > 100 req/s, ré-évaluer la topologie (lecture réplicas, sharding).

## Références

- Spec : [`specs/001-supabase-selfhost/spec.md`](../../specs/001-supabase-selfhost/spec.md)
- Plan : [`specs/001-supabase-selfhost/plan.md`](../../specs/001-supabase-selfhost/plan.md)
- Research détaillée (10 décisions techniques) : [`specs/001-supabase-selfhost/research.md`](../../specs/001-supabase-selfhost/research.md)
- Contrats d'API et env vars : [`specs/001-supabase-selfhost/contracts/`](../../specs/001-supabase-selfhost/contracts/)
- Constitution articles pertinents : [Art. 2, 3.4, 4.3, 4.5, 10.3](../../.specify/memory/constitution.md)
