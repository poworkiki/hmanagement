# Architecture Decision Records (ADR)

Les **ADR** tracent les décisions architecturales structurantes du projet hmanagement. Chaque décision majeure ou irréversible (choix de stack, schéma DB, pattern d'intégration, politique de sécurité) génère un ADR dédié.

## Format

Format utilisé : **MADR light** (Markdown Any Decision Records, simplifié).

Template :

```markdown
# ADR-NNN : Titre décision

- **Date** : YYYY-MM-DD
- **Statut** : Proposed / Accepted / Superseded by ADR-XXX / Deprecated
- **Décideurs** : Kiki (super-admin), éventuels co-décideurs
- **Contexte feature** : #NNN-feature-name (si applicable)

## Contexte

Description du problème qui nécessite une décision. Contraintes imposées
(constitution, stack, sécurité, budget, délai).

## Options considérées

- **Option A** — description, avantages, inconvénients
- **Option B** — ...
- **Option C** — ...

## Décision

Option retenue et **pourquoi**. Impact sur les features existantes et futures.
Conséquences irréversibles à accepter.

## Conséquences

- Positives (gains attendus)
- Négatives (coûts acceptés)
- Suivi (ce qu'on surveille pour confirmer que la décision reste bonne)

## Références

- Liens vers spec, plan, research.md, discussions externes, docs vendeurs
```

## Principes

1. **Un ADR = une décision irréversible ou structurante**. Les micro-choix
   techniques (quel linter, quel formatter) ne méritent pas un ADR.
2. **Numérotation séquentielle** : `ADR-001`, `ADR-002`, etc. Les numéros
   ne sont jamais réutilisés, même pour un ADR déprécié.
3. **Superseded ≠ supprimé** : un ADR remplacé reste lisible et voit son
   statut passer à `Superseded by ADR-NNN`. Art. constitution 11.3.
4. **Amendements** : un ADR n'est pas modifié après acceptation. Pour
   changer une décision → nouvel ADR qui référence l'ancien.

## Index

| ADR | Titre | Statut | Feature |
|---|---|---|---|
| [ADR-001](./ADR-001-supabase-self-hosted-via-coolify.md) | Supabase self-hosted déployé via Coolify | Accepted (2026-04-22) | [001-supabase-selfhost](../../specs/001-supabase-selfhost/) |

## Quand écrire un ADR ?

- Choix d'un composant de stack qui sera difficile à remplacer (DB, framework)
- Choix d'un pattern architectural structurant (ELT vs ETL, monolithe vs micro)
- Politique de sécurité majeure (stratégie d'auth, gestion des secrets)
- Intégration d'un produit tiers qui devient central
- Arbitrage entre deux options équivalentes avec conséquences durables

## Quand **ne pas** écrire un ADR ?

- Choix de bibliothèque utilitaire (date-fns vs dayjs)
- Style de code, nommage, organisation des dossiers (→ CLAUDE.md ou conventions)
- Bugs résolus, corrections ponctuelles (→ message de commit / PR description)
- Préférences personnelles sans impact architectural
