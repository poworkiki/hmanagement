# hmanagement — Sprint 0 Bundle (CDC v0.2 consolidé)

Bundle des 6 fichiers fondamentaux à installer **à la racine** du repo `hmanagement` avant Sprint 1.

## Contenu

```
hmanagement-sprint-0/
├── CLAUDE.md                                        ← contexte projet (mis à jour avec tests)
├── README.md                                        ← ce fichier
├── .claude/
│   └── skills/
│       ├── hma-context/
│       │   └── SKILL.md                             ← skill métier (mise à jour hmanagement)
│       └── testing-strategy/
│           └── SKILL.md                             ← NOUVELLE skill stratégie tests
├── .specify/
│   └── memory/
│       └── constitution.md                          ← constitution v0.2 (12 articles)
└── docs/
    ├── CDC-v0.2-hmanagement.md                      ← cahier des charges complet (~30 pages)
    └── synthese-executive.md                        ← version 1 page
```

## Nouveautés v0.2 par rapport au Sprint 0 initial

1. **Nom projet unifié** : `hmanagement` partout (plus de HMAnalytics)
2. **Architecture multi-tenant-ready** : `tenant_id` partout dès MVP
3. **Scope MVP strict** : compte de résultat uniquement (CR + CRD + SIG)
4. **Stratégie de tests complète** : pyramide, patterns, tests bloquants MVP
5. **Nouvelle skill** `testing-strategy` — Claude Code appliquera les bons patterns automatiquement
6. **Constitution renforcée** : article 6 dédié aux tests, article 12 pour North Star Metric
7. **CDC consolidé** : fusion du CDC v0.1 initial + toutes nos décisions de cadrage
8. **Synthèse exécutive** : version 1 page pour pitch rapide

## Installation

### Option A — Repo hmanagement existant
```bash
cd chemin/vers/hmanagement

# Si tu avais déjà le bundle Sprint 0 initial, supprime-le :
rm -rf .claude/skills/hma-context
rm -f CLAUDE.md
rm -f .specify/memory/constitution.md

# Copie le nouveau bundle
cp /chemin/bundle/CLAUDE.md .
cp -r /chemin/bundle/.claude/* .claude/
cp -r /chemin/bundle/.specify/* .specify/
mkdir -p docs
cp /chemin/bundle/docs/*.md docs/

# Ajoute aussi le référentiel comptable si pas encore fait
cp /chemin/compta_analytique.md docs/

# Commit
git add CLAUDE.md .claude/ .specify/ docs/
git commit -m "docs: sprint 0 v0.2 - CDC consolidé + stratégie tests + skill testing-strategy"
```

### Option B — Projet à initialiser
```bash
mkdir -p ~/Projets/hmanagement
cd ~/Projets/hmanagement
git init

# Copie tous les fichiers du bundle
cp -r /chemin/bundle/. .

# Copie aussi le référentiel comptable à docs/
cp /chemin/compta_analytique.md docs/

git add .
git commit -m "chore: init hmanagement - Sprint 0 complet"

# Lie à GitHub
git remote add origin <URL>
git branch -M main
git push -u origin main
```

## Validation du setup

### 1. Ouvre dans VSCode
```bash
code .
```

### 2. Lance Claude Code (icône Spark)

### 3. Teste 4 questions pour valider les skills

**Test 1 — Contexte projet**
> "Quel est le nom du projet et quel est le scope du MVP ?"

Réponse attendue : Claude mentionne `hmanagement`, scope MVP = compte de résultat uniquement (CR + CRD + SIG), classes PCG 6 et 7.

**Test 2 — Contexte métier**
> "Donne-moi la formule du seuil de rentabilité avec un exemple HMA."

Réponse attendue : formule `SR = Charges fixes / Taux MCV`, exemple chiffré, référence au référentiel.

**Test 3 — Tests**
> "Comment j'organise les tests pour une nouvelle fonction de calcul de marge ?"

Réponse attendue : Claude propose du TDD (Red-Green-Refactor), avec Vitest, nommage `*.test.ts`, 100% couverture car calcul financier.

**Test 4 — Anti-pattern**
> "Si je veux vérifier qu'un contrôleur voit bien seulement sa filiale, je teste où ?"

Réponse attendue : test d'intégration RLS (niveau 2 pyramide), jamais juste frontend, avec fixtures de seed et `signInAs()`.

Si les 4 marchent : **Sprint 0 validé** ✅

## Prochaine étape — Installer Spec Kit CLI

```bash
# Prérequis : uv installé (gestionnaire Python moderne)
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.7.2

# Initialiser Spec Kit (ATTENTION : dis NON si ça veut écraser constitution.md)
specify init --here --ai claude --no-git
```

## Sprint 1 à suivre

Une fois Spec Kit installé, on enchaîne sur l'installation Supabase self-hosted sur Coolify via Spec Kit :

```
Dans Claude Code :
/speckit.specify Je veux installer Supabase self-hosted sur Coolify pour hmanagement...
```

Claude Code te guidera alors rigoureusement spec → plan → tasks → implement.

## Documentation complète

- **Contexte technique** : `CLAUDE.md` (racine)
- **Principes non négociables** : `.specify/memory/constitution.md`
- **Cahier des charges complet** : `docs/CDC-v0.2-hmanagement.md`
- **Pitch/synthèse** : `docs/synthese-executive.md`
- **Référentiel comptable** : `docs/compta_analytique.md` (à copier depuis tes uploads)

Tu es prêt pour Sprint 1 ! 🚀
