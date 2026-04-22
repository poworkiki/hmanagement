# `infra/supabase/` — Socle data self-hosted

Scope de la feature **`001-supabase-selfhost`**. Référence complète : [`specs/001-supabase-selfhost/`](../../specs/001-supabase-selfhost/).

## Arborescence

```
infra/supabase/
├── README.md                          (ce fichier)
├── env.reference                      # variables env publiques (NO secrets)
├── gotrue-config-overrides.yml        # overrides GoTrue descriptifs
├── backups/
│   ├── README.md                      # runbook installation scripts
│   ├── pg-backup.sh                   # dump + restic → R2
│   ├── pg-restore-drill.sh            # drill restauration mensuel
│   └── backup.cron                    # crontab / cron.d
├── monitoring/
│   ├── uptime-kuma-probes.yaml        # descriptif des 4 sondes
│   └── disk-alert.sh                  # alerte disque > 80%
└── smoke-tests/
    └── api-contract.sh                # test PostgREST (SC-006)
```

## Procédure de déploiement

Voir [`specs/001-supabase-selfhost/quickstart.md`](../../specs/001-supabase-selfhost/quickstart.md) pour le guide opérateur complet (60-90 min).

**Ordre d'exécution** (extraits des tâches du plan) :
1. **Foundational** : DNS, R2, Brevo, 12 secrets Vaultwarden (T010-T027)
2. **Déploiement** : Coolify UI (T030-T034) → application opérationnelle
3. **Auth MFA** : configuration GoTrue + premier compte (T050-T058)
4. **Backups** : installation scripts + cron + drill initial (T070-T083)
5. **Monitoring** : sondes Uptime Kuma + alertes disque (T120-T127)
6. **Polish** : audits sécurité + PR (T140-T149)

## Ce qui est dans ce dossier vs ailleurs

| Emplacement | Contenu |
|---|---|
| `infra/supabase/` (ici) | **Ce que l'opérateur exécute** : scripts shell, config descriptive, références env |
| `docs/runbooks/supabase-*.md` | **Comment l'opérateur exécute** : procédures, incidents, rotations |
| `docs/adr/ADR-001-*.md` | **Pourquoi c'est comme ça** : décision architecturale |
| `specs/001-supabase-selfhost/` | **Spec / plan / tasks SDD** : source méthodo |

## Pas dans cette feature

- **Schémas applicatifs** (`raw`, `staging`, `marts`, `app`), rôles DB dédiés, policies RLS → feature **`002-schemas-rls-bootstrap`**
- **Modèles dbt, pipelines Pennylane** → features ultérieures
- **Application Next.js** → feature ultérieure

Voir la section "Exclusions explicites" dans [`specs/001-supabase-selfhost/spec.md`](../../specs/001-supabase-selfhost/spec.md#exclusions-explicites-hors-scope-sprint-1) pour le détail.

## Rappels sécurité (Art. constitution 4.5)

- ❌ **Jamais** committer `/etc/supabase-backup/env` ou fichiers `.env` contenant des valeurs
- ❌ **Jamais** copier-coller un secret dans un issue / PR / message
- ✅ Toutes les valeurs secrètes sont dans **Vaultwarden** (`stack_hma`), préfixées `supabase-selfhost-*`
- ✅ Une copie cold-storage de `RESTIC_PASSWORD` existe hors Vaultwarden (disaster recovery)
