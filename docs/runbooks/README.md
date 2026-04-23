# Runbooks opérateur — hmanagement

Les **runbooks** sont des procédures pas-à-pas destinées au super-admin pour opérer la plateforme en conditions normales, préventives ou d'incident.

## Principes

- **Un runbook = une procédure exécutable** par une personne qualifiée, sans contexte préalable.
- **Rédaction au fil des incidents réels** : la première version peut être un squelette, enrichi à chaque utilisation.
- **Testable** : chaque runbook critique (restore, rotation, incident) doit avoir été joué au moins une fois sur un environnement de test avant d'être déclaré "ready".
- **Horodaté** : les runbooks opérationnels peuvent contenir un journal (`*-log.md`) des exécutions passées.

## Inventaire

### Socle Supabase (feature [001-supabase-selfhost](../../specs/001-supabase-selfhost/))

| Runbook | Type | Trigger | Statut |
|---|---|---|---|
| [`supabase-deploy.md`](./supabase-deploy.md) | Install | Déploiement initial ou redéploiement complet | **Skeleton** — à enrichir après 1er deploy réel |
| [`supabase-restore-drill.md`](./supabase-restore-drill.md) | Test récurrent | Drill mensuel auto (1er du mois 05h) | Ready |
| [`restore-drill-log.md`](./restore-drill-log.md) | Journal | Registre des exécutions de drill | Initialisé |
| [`supabase-secret-rotation.md`](./supabase-secret-rotation.md) | Maintenance | Rotation trimestrielle JWT, annuelle autres, immédiate sur incident | Ready |
| [`supabase-incident.md`](./supabase-incident.md) | Incident | Alerte reçue : DB down, auth down, backup KO, disque plein, cert expiration | Ready |

### À venir (features suivantes)

- `dbt-pipeline.md` — exécution et debug des pipelines dbt (feature 002+)
- `pennylane-sync.md` — workflows n8n de synchronisation (feature ultérieure)
- `app-release.md` — procédure de déploiement app Next.js

## Conventions

- Toutes les commandes supposent un accès `ssh hma` (entrée dans `~/.ssh/config`).
- Tout runbook qui modifie la plateforme en production **doit** préciser : temps estimé, impact utilisateur, rollback, canal de notification.
- Un incident pendant l'exécution d'un runbook → fait l'objet d'un ajout dans `supabase-incident.md` ou d'un nouveau runbook dédié.
