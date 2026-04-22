---
name: hma-context
description: Contexte métier HMA (groupe familial Guyane française) et vision produit hmanagement. Use this skill whenever the conversation involves HMA entities, filiales, French accounting specifics, Pennylane data, Octroi de Mer, LODEOM, ZFANG, or any business rule specific to HMA and the hmanagement product. Also trigger for terms like "CRD", "SIG", "FRNG", "BFR", "PCG", "bilan fonctionnel", "compte de résultat différentiel", "ratios financiers", "hmanagement".
---

# Contexte métier HMA & produit hmanagement

## À propos du groupe HMA

HMA est une **holding familiale** basée en **Guyane française** avec les activités suivantes :
- **Holding** (gestion de filiales)
- **Transport** (activité logistique)
- **Agriculture** (production primaire)
- **Agroalimentaire** (transformation et distribution)

**Note** : pas de BTP dans le groupe HMA (contrairement à l'ancienne mission HGA de Kiki).

## Produit hmanagement

**Mission** : transformer la comptabilité Pennylane en intelligence financière actionnable. En un clic, chaque KPI révèle la ligne comptable qui l'explique.

**Stratégie** :
- **MVP (2-3 mois)** : livraison HMA (mono-tenant), compte de résultat uniquement
- **V1 (+3 mois)** : bilan, ratios, forecast
- **V2+ (+6 mois)** : ouverture SaaS multi-tenant aux autres PME ultra-marines

**North Star Metric** : temps entre clôture Pennylane et décision métier < 30 secondes (vs 2 jours actuellement).

## Structure groupe

```
HMA (holding mère)
 ├── Filiale Transport
 ├── Filiale Agriculture
 └── Filiale Agroalimentaire
```

Modélisation DB dans `app.entites` avec `parent_id` pour la hiérarchie.

## Utilisateurs MVP (réels)

| Persona | Rôle | Usage |
|---|---|---|
| **Kiki (Gabi Raviki)** | `super_admin` | Dev + pilotage quotidien |
| **Gérant HMA** | `admin` | Morning check, décisions direction |
| **Gestionnaire administrative** | `controleur` | Suivi, saisie budget |

## Spécificités fiscales Guyane française

### Octroi de Mer
Taxe spécifique aux départements d'outre-mer français.
- S'applique aux importations et livraisons de biens produits localement
- Deux composantes : Octroi de Mer + Octroi de Mer Régional
- Taux variables selon les produits (exonérations, taux réduits, taux standards)
- Comptabilisation : à intégrer dans les calculs de prix de revient

### LODEOM (Loi pour le Développement Économique des Outre-Mer)
Dispositif d'exonérations de charges sociales.
- Réduit le coût du travail pour les entreprises ultra-marines
- Impact direct sur le calcul des charges de personnel
- À prendre en compte dans les SIG (valeur ajoutée, charges de personnel)

### ZFANG (Zone Franche d'Activité Nouvelle Génération)
Dispositif fiscal de zones franches en Guyane.
- Exonérations partielles d'impôt sur les sociétés
- Conditions sectorielles et géographiques
- Impact sur le calcul du résultat fiscal et de l'IS

## Plan Comptable Général (PCG) français

hmanagement s'appuie sur le **PCG français**, structure standard :
- Classe 1 — Comptes de capitaux
- Classe 2 — Comptes d'immobilisations
- Classe 3 — Comptes de stocks
- Classe 4 — Comptes de tiers
- Classe 5 — Comptes financiers
- **Classe 6 — Comptes de charges** ⭐ MVP
- **Classe 7 — Comptes de produits** ⭐ MVP

**Focus MVP** : uniquement classes 6 et 7 (compte de résultat). Les classes 1-5 (bilan) sont en V1.

Les comptes Pennylane suivent la structure PCG. À respecter dans les modèles dbt.

## Indicateurs métier MVP

### CR (Compte de Résultat standard PCG)
Structure classique :
- Produits d'exploitation (classe 70-74)
- Charges d'exploitation (classe 60-65, 681)
- Résultat d'exploitation
- Produits financiers (76), Charges financières (66)
- Résultat financier
- Produits exceptionnels (77), Charges exceptionnelles (67)
- Résultat exceptionnel
- Participation (691), IS (695)
- Résultat net de l'exercice

### CRD (Compte de Résultat Différentiel) ⭐ module phare
Modèle qui sépare charges variables et charges fixes pour analyse du seuil de rentabilité.

```
Chiffre d'affaires HT
− Charges variables
= Marge sur Coûts Variables (MCV)
− Charges fixes
= Résultat d'exploitation (REX)
− Résultat financier
= Résultat courant
```

Indicateurs dérivés (voir `compta_analytique.md` §5) :
- **Taux de MCV** = MCV / CA
- **Seuil de rentabilité (SR)** = Charges fixes / Taux de MCV
- **Point mort** (jours) = (SR / CA) × 365
- **Marge de sécurité (MS)** = CA − SR
- **Indice de sécurité** = MS / CA
- **Levier opérationnel (LO)** = MCV / Résultat courant

### SIG (Soldes Intermédiaires de Gestion) — 9 soldes légaux
1. **Marge commerciale** : ventes marchandises − coût d'achat des marchandises vendues
2. **Production de l'exercice** : production vendue + stockée + immobilisée
3. **Valeur ajoutée** : marge commerciale + production − consommations
4. **Excédent Brut d'Exploitation (EBE)** : VA + subventions − impôts et taxes − charges de personnel
5. **Résultat d'exploitation** : EBE + reprises/transferts − DAP − autres charges
6. **Résultat courant avant impôts** : RE + produits financiers − charges financières
7. **Résultat exceptionnel** : produits exceptionnels − charges exceptionnelles
8. **Résultat de l'exercice** : RCAI + RE − participation − IS
9. **Plus ou moins-values sur cessions** : prix de cession − valeur comptable
+ **CAF** (Capacité d'Autofinancement)

Formules précises dans `compta_analytique.md` §1.

## Indicateurs V1 (reportés)

- Bilan comptable
- Bilan fonctionnel (FRNG, BFR, Trésorerie nette)
- 26 ratios financiers (liquidité, solvabilité, rentabilité, activité, structure)
- Tableau de financement
- Forecast par scénarios

## Sources de données

### Pennylane (source unique de vérité)
- Extraction quotidienne via API par n8n à 2h00
- Endpoints principaux : `/invoices`, `/transactions`, `/ledger_entries`, `/customers`, `/vendors`, `/products`
- Stockage brut dans `raw.pennylane_*` en JSONB
- **Attention** : les montants Pennylane sont en **centimes** (à diviser par 100)

### Règles de transformation critiques
1. Conversion centimes → euros : systématique en staging
2. Dates : caster en `DATE` ou `TIMESTAMPTZ`
3. Entité Pennylane → mapping vers `app.entites.code_pennylane`
4. Périodes analytiques : par défaut mois calendaires, option par quinzaine

## Terminologie stricte à respecter

| Terme correct | Ne pas utiliser |
|---|---|
| Compte de résultat | P&L, Income Statement (sauf commentaires code) |
| CRD | CR différentiel, Tableau de différenciation |
| MCV | Contribution margin, Marge contributive |
| SIG | Intermediate management balances |
| FRNG | Working capital (pas strictement équivalent) |
| BFR | WCR, Working Capital Requirement |
| DAP | Amortizations expenses |
| Résultat d'exploitation (REX) | Operating income, EBIT (pas strictement équivalent en norme FR) |
| CA HT | Revenue, Net revenue (sans précision) |

## Périodes analytiques

- **Exercice comptable HMA** : à préciser (généralement année civile)
- **Périodes par défaut** : mois, trimestre, exercice
- **Comparaisons** : période vs N-1, cumul YTD, rolling 12 mois

## Anti-patterns métier à signaler

- ❌ Additionner des CA de filiales sans déduire les **opérations intragroupe** (en V1)
- ❌ Confondre **résultat d'exploitation** et **résultat courant**
- ❌ Mélanger montants HT et TTC sans le préciser
- ❌ Oublier les **retraitements analytiques** (notamment pour le CRD)
- ❌ Ignorer les spécificités Guyane (Octroi de Mer impacte le prix de revient)
- ❌ Calculer un ratio sans préciser sa périodicité (mensuel ? annualisé ?)
- ❌ Afficher un chiffre sans comparaison (vs N-1 ou budget)
- ❌ Intégrer les classes 1-5 dans le MVP (hors scope)

## Classification V/F des charges (pour CRD)

Voir `compta_analytique.md` §5.2 pour la table complète. Règle générale :

**Variables (par défaut)** :
- 601-607 (achats matières, marchandises)
- 6031-6037 (variations stocks)
- 611 (sous-traitance)
- 6132 (locations mobilières pour transport/BTP)
- 6241-6243 (transports sur achats/ventes)
- 623 (publicité)
- 654 (pertes créances)

**Fixes (par défaut)** :
- 6161 (assurances multirisques)
- 6226 (honoraires)
- 6262 (télécommunications)
- 627 (services bancaires)
- 63 (impôts et taxes, hors taxe CA)
- 64 (personnel)
- 66 (charges financières)
- 681 (DAP)

**Mixtes** :
- 6152 (entretien, ~60% variable)
- 625 (déplacements)

**Surcharges possibles** via `app.profil_nature_charge` (par secteur) et `app.entite_override_charge` (par filiale).

## Références externes

- Plan Comptable Général : https://www.plancomptable.com/
- Octroi de Mer : site douanes.gouv.fr
- LODEOM : bulletins officiels des finances publiques
- API Pennylane : https://pennylane.readme.io/reference
- Référentiel interne complet : `compta_analytique.md`
