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
| 2026-04-23 05:11 UTC | manual | `cbfe7451` | 9 s | ✅ OK | Kiki + Claude | Bootstrap — 11 user schemas, 174 relations. Besoin d'avoir patch `--no-owner --no-acl` (Supabase roles absents sur postgres:15 vanilla). |

## Anomalies connues

_(liste des drills KO et leur résolution — format chronologique)_

Rien à signaler pour le moment.

## Cumul mensuel (Art. constitution 10.3)

| Mois | Drill auto (1er) | Drill manuel supplémentaire ? | Couverture respectée ? |
|---|---|---|---|
| 2026-04 | _n/a — bootstrap en cours de mois_ | ✅ 2026-04-23 drill manuel bootstrap | ✅ |
| 2026-05 | _pending auto 2026-05-01 05:00 UTC_ | _–_ | _–_ |
