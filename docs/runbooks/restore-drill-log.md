# Journal des drills de restauration Supabase

Registre historique des exécutions de [`pg-restore-drill.sh`](../../infra/supabase/backups/pg-restore-drill.sh). Source de vérité pour l'Art. constitution 10.3 (test restauration mensuel obligatoire).

## Format

Une ligne par drill (auto ou manuel). Colonnes :
- **Date** : date d'exécution
- **Type** : `auto` (cron) / `manual` (trigger opérateur)
- **Snapshot ID** : short_id restic restauré
- **Durée** : secondes totales de bout en bout
- **Résultat** : OK / KO (+ brève note)
- **Opérateur** : qui a lancé / validé

## Entrées

| Date | Type | Snapshot ID | Durée | Résultat | Opérateur | Notes |
|---|---|---|---|---|---|---|
| _(à remplir après le 1er drill T078)_ | _manual_ | _–_ | _–_ | _–_ | _Kiki_ | Bootstrap initial |

## Anomalies connues

_(liste des drills KO et leur résolution — format chronologique)_

Rien à signaler pour le moment.

## Cumul mensuel (Art. constitution 10.3)

| Mois | Drill auto (1er) | Drill manuel supplémentaire ? | Couverture respectée ? |
|---|---|---|---|
| 2026-04 | _pending_ | _–_ | _–_ |
| 2026-05 | _pending_ | _–_ | _–_ |
