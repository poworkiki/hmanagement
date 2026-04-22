# hmanagement — Synthèse exécutive

**Version** : v0.2 (21 avril 2026)
**Porteur** : Kiki (Gabi Raviki) — POWOR_BUSINESS

---

## Vision en une phrase

> **hmanagement transforme la comptabilité Pennylane en intelligence financière actionnable. En un clic, chaque KPI révèle la ligne comptable qui l'explique.**

## Problème résolu

Les PME multi-filiales (ultra-marines en priorité) passent 2 jours par mois à consolider Excel + Pennylane à la main, sans vue consolidée en temps réel, sans outil adapté aux spécificités fiscales (Octroi de Mer, LODEOM, ZFANG).

## Proposition de valeur

1. **Drill-down 3 niveaux** natif (rubrique → compte → écriture)
2. **CRD et SIG first-class** dès le MVP
3. **Souveraineté totale** (self-hosted Coolify)
4. **Spécificités ultra-marines** intégrées
5. **Multi-tenant ready** (architecture prête pour pivot SaaS)

## North Star Metric

**Temps clôture Pennylane → décision métier**
- Aujourd'hui : 2 jours
- Cible : **< 30 secondes**

## Stratégie produit

- **MVP (2-3 mois)** : livraison à HMA, mono-tenant fonctionnel (compte de résultat uniquement)
- **V1 (+3 mois)** : bilan, ratios, trésorerie, forecast simple
- **V2 (+6 mois)** : ouverture multi-tenant SaaS, autres clients PME

## Scope MVP strict

**Modules inclus** :
- Compte de Résultat standard PCG
- CRD (Compte de Résultat Différentiel) ⭐ module phare
- SIG (9 soldes intermédiaires)
- KPI Home (4 cartes cliquables)
- UI admin users + entités
- Import budget CSV
- Export CSV

**Exclus MVP (V1+)** : bilan, ratios, trésorerie, forecast, multi-devises, import FEC, IA.

## Stack technique

```
Pennylane → n8n → Supabase self-hosted (PostgreSQL + Auth + RLS) → dbt Core → Next.js 15 + shadcn/ui + Tremor
```

**Coolify** pour déploiement, **Vaultwarden** pour secrets, **Grafana/Loki/Prometheus** pour monitoring.

## Utilisateurs MVP (HMA)

3 personnes :
- Kiki (super_admin)
- Gérant HMA (admin)
- Gestionnaire administrative (controleur)

## Méthodologie

- **Spec-Driven Development** via GitHub Spec Kit
- **TDD** sur les calculs financiers (100% couverture)
- **Tests bloquants** : unit + integration (RLS) + dbt data quality + E2E Playwright
- **Claude Code** comme IDE principal avec skills dédiées

## Roadmap 7 sprints

| Sprint | Contenu | Durée |
|---|---|---|
| 0 ✅ | Setup Claude Code + CDC + skills | fait |
| 1 | Supabase + auth + schéma app | 1 sem |
| 2 | Next.js + shadcn + UI admin | 1 sem |
| 3 | Pipeline ELT n8n + dbt | 1-2 sem |
| 4 | Module Compte de Résultat | 1-2 sem |
| 5 | Module CRD | 1 sem |
| 6 | Module SIG + KPI home | 1 sem |
| 7 | Hardening + prod | 1 sem |

**Total MVP** : ~7-9 semaines calendaires (3-4h/jour).

## Definition of Done MVP

- ✅ Kiki consulte le CRD consolidé en < 30s
- ✅ Gérant HMA voit sa home avec 4 KPI exacts chaque matin
- ✅ Gestionnaire importe le budget 2026 via CSV sans friction
- ✅ Aucun chiffre ne diffère de Pennylane (réconciliation à l'euro)
- ✅ App accessible en HTTPS sur Coolify avec MFA actif
- ✅ 100% couverture tests sur calculs financiers
- ✅ Zero bug sécurité RLS détecté

## Ambition commerciale (V2+)

Réplication hmanagement en SaaS pour PME ultra-marines (Guyane, Antilles, Réunion). Marché estimé : 500+ PME cibles. Différenciation : maîtrise spécificités fiscales + souveraineté données.

**Modèle cible** :
- SaaS mutualisé : 90-250 €/mois/structure
- Self-hosted premium : 5-15 k€/an + support

---

*Document évolutif. Source de vérité détaillée : `docs/CDC-v0.2-hmanagement.md`*
