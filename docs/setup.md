# Setup — hmanagement

> **Objectif** : tout dev (ou toi, dans 3 mois) peut cloner et lancer le projet en local en **< 30 minutes**.
> **Prérequis système** : Windows 11 + WSL2 recommandé, macOS, ou Linux.

---

## 1. Prérequis à installer une fois

| Outil | Version | Installation |
|---|---|---|
| Node.js | 20 LTS | via [nvm](https://github.com/nvm-sh/nvm) : `nvm install 20 && nvm use 20` |
| pnpm | 9+ | `corepack enable && corepack prepare pnpm@latest --activate` |
| Docker Desktop | dernière | [docker.com](https://www.docker.com/products/docker-desktop/) |
| Git | 2.40+ | déjà installé |
| Supabase CLI | dernière | `scoop install supabase` (Windows) ou `brew install supabase/tap/supabase` |
| uv (Python pkg manager) | dernière | `powershell -c "irm https://astral.sh/uv/install.ps1 \| iex"` |
| dbt Core | 1.7+ | `uv tool install dbt-postgres` |
| GitHub CLI | dernière | `scoop install gh` ou `brew install gh` |
| VSCode | dernière | [code.visualstudio.com](https://code.visualstudio.com/) |
| Claude Code | dernière | [claude.com/claude-code](https://claude.com/claude-code) |

### Extensions VSCode recommandées
```json
// .vscode/extensions.json (à committer)
{
  "recommendations": [
    "dbaeumer.vscode-eslint",
    "esbenp.prettier-vscode",
    "bradlc.vscode-tailwindcss",
    "innoverio.vscode-dbt-power-user",
    "supabase.vscode-supabase-extension",
    "ms-playwright.playwright",
    "anthropic.claude-code"
  ]
}
```

---

## 2. Premier clonage (dev local, zéro à running)

```bash
# 1. Clone + accès au remote
gh repo clone poworkiki/hmanagement
cd hmanagement

# 2. Secrets locaux (récupérés depuis Vaultwarden)
cp .env.example .env.local
# Puis éditer .env.local avec les valeurs via Vaultwarden :
#   eval $(./scripts/vw-secret.sh export "Supabase local anon key" NEXT_PUBLIC_SUPABASE_ANON_KEY)

# 3. Dépendances front
pnpm install

# 4. Supabase local (Postgres + Auth + PostgREST + Studio)
supabase start
# → prend 1-2 min la première fois (pull des images)
# → imprime les URLs/keys : API, DB, Studio, Anon key, Service role
# → ces valeurs vont dans .env.local (automatique avec `supabase status -o env`)

# 5. Appliquer les migrations + seed
supabase db reset
# → applique tout ce qui est dans supabase/migrations/ + supabase/seed.sql
# → crée le tenant 'hma', les entités, le super_admin Kiki

# 6. dbt : dépendances + build initial
cd dbt
uv tool run dbt deps
uv tool run dbt build
cd ..
# → materialize tous les marts avec les données de seed

# 7. Lancer Next.js
pnpm dev
# → http://localhost:3000
```

### Vérifier que tout fonctionne
- ✅ `supabase status` → 7 services up
- ✅ `pnpm test:unit` → passe
- ✅ `pnpm typecheck` → 0 error
- ✅ `http://localhost:3000` → page login visible
- ✅ `http://localhost:54323` → Supabase Studio accessible

### `.env.example` (committé, sans secrets)
```env
# Supabase local (générés par `supabase start`)
NEXT_PUBLIC_SUPABASE_URL=http://localhost:54321
NEXT_PUBLIC_SUPABASE_ANON_KEY=...
SUPABASE_SERVICE_ROLE_KEY=...                  # server-only, JAMAIS bundlé client

# Pennylane (sandbox en dev)
PENNYLANE_API_URL=https://app.pennylane.com/api/external/v2
PENNYLANE_API_TOKEN_SANDBOX=...                # via Vaultwarden

# Environnement
NODE_ENV=development
NEXT_PUBLIC_APP_URL=http://localhost:3000

# Features flags (dev)
NEXT_PUBLIC_FEATURE_CRD=true
NEXT_PUBLIC_FEATURE_SIG=true
```

---

## 3. Commandes quotidiennes

### Dev
```bash
pnpm dev                          # Next.js local (port 3000)
supabase start / stop             # DB locale
supabase db reset                 # re-seed complet (drop + migrations + seed)
```

### Qualité
```bash
pnpm lint                         # ESLint + Prettier check
pnpm lint:fix                     # auto-fix
pnpm typecheck                    # tsc --noEmit
pnpm test:unit                    # Vitest unit
pnpm test:integration             # Vitest integration (nécessite supabase start)
pnpm test:e2e                     # Playwright
pnpm test:e2e:ui                  # Playwright UI mode (debug)
pnpm test:coverage                # coverage report
```

### Base de données
```bash
supabase migration new <nom>      # nouvelle migration SQL
supabase db diff -f <nom>         # génère migration depuis état courant Studio
supabase db push                  # pousse migrations vers remote (prod/staging)
supabase gen types typescript --local > src/lib/database.types.ts
```

### dbt
```bash
cd dbt
uv tool run dbt deps                               # installer packages dbt (dbt_utils, etc.)
uv tool run dbt build --select state:modified+    # run + test modèles modifiés
uv tool run dbt test --select mart_crd            # tester un mart précis
uv tool run dbt docs generate && uv tool run dbt docs serve  # docs en local
```

### Git
```bash
git checkout -b feature/nom-feature      # nouvelle branche
git add -p                               # stage hunk par hunk (préféré à -A)
git commit                               # pre-commit hook tourne auto
gh pr create                             # créer PR
```

---

## 4. Setup production (VPS Hostinger + Coolify)

> **Prérequis** : accès SSH VPS (clé dans Vaultwarden), Coolify admin, DNS Cloudflare `hma.business`.

### 4.1 Vérifier la capacité VPS avant de pousser Supabase
```bash
ssh root@187.124.150.82
free -h                           # RAM dispo
df -h                             # disque dispo
docker stats --no-stream          # RAM/CPU par container
```
Libérer Odoo / Metabase / Superset suspendus si RAM < 4Go libre.

### 4.2 Créer le projet Coolify
1. Coolify UI → **New Resource** → **Public Git Repository**
2. URL : `git@github-hmanagement:poworkiki/hmanagement.git`
3. Branch : `main`
4. Build pack : **Dockerfile** (à créer, voir §4.4)
5. Domaine : `hmanagement.hma.business`
6. Env variables : importer depuis Vaultwarden (cf. liste `.env.example` + production)

### 4.3 DNS Cloudflare
- `hmanagement.hma.business` → IP VPS, proxy **OFF** (Traefik gère le TLS)
- `staging.hmanagement.hma.business` → même IP, staging env Coolify
- `supabase.hma.business` → Supabase Studio, proxy **ON** + IP whitelist

### 4.4 Dockerfile Next.js (à créer Sprint 1)
```dockerfile
# syntax=docker/dockerfile:1.7
FROM node:20-alpine AS base
RUN corepack enable

FROM base AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
RUN pnpm build

FROM base AS runner
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
EXPOSE 3000
CMD ["node", "server.js"]
```

### 4.5 Supabase self-hosted sur Coolify
Coolify propose un template Supabase one-click. Étapes :
1. Coolify UI → **Resources** → **One-Click Services** → **Supabase**
2. Domaine : `supabase.hma.business` (Studio + Kong)
3. Secrets auto-générés → **sauvegarder dans Vaultwarden immédiatement**
4. Valider : Studio accessible, health `/api/health` OK
5. Supprimer les 2 entrées Supabase Cloud de Vaultwarden (Article 2)

### 4.6 Secrets (Vaultwarden → Coolify)
Liste minimale à remplir dans Coolify Env variables :
- `NEXT_PUBLIC_SUPABASE_URL` = `https://supabase.hma.business`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` (depuis Supabase Studio → API)
- `SUPABASE_SERVICE_ROLE_KEY` (server-only, JAMAIS exposé client)
- `PENNYLANE_API_TOKEN_HMA`, `_STIVMAT`, `_STA`, `_ETPA` (prod, pas sandbox)
- `DISCORD_WEBHOOK_URL_ALERTS`
- `N8N_WEBHOOK_URL_DBT_TRIGGER`
- `DATABASE_URL` (pour dbt — role `dbt_runner` dédié, pas service_role)

### 4.7 Backups PostgreSQL
Cron quotidien sur le VPS (script à créer Sprint 1) :
```bash
# /etc/cron.d/hmanagement-backup (quotidien 03:00)
0 3 * * * root /opt/hmanagement/scripts/backup-postgres.sh
```

Le script doit :
- `pg_dump` de la DB Supabase (via Docker exec)
- Chiffrement gpg avec clé publique dédiée
- Push vers Backblaze B2 (bucket `hma-backups`) + copie locale `/var/backups/hmanagement/`
- Rétention : 30 daily, 12 monthly, 5 annual
- Webhook Discord en fin de job (succès/échec)

**Test de restauration mensuel obligatoire** (Article 10.3 constitution) : script séparé qui restaure un dump sur un Postgres de test et lance `dbt test`.

### 4.8 Déploiement
- Push sur `main` → Coolify auto-deploy sur prod
- Rollback : Coolify UI → Deployments → Previous → Rollback (1 clic)
- Hotfix : branche `fix/*`, PR, merge `main` → auto-deploy

---

## 5. Configuration Claude Code (repo-level)

### `.claude/settings.json` (à créer)
```json
{
  "permissions": {
    "allow": [
      "Bash(pnpm *)",
      "Bash(supabase *)",
      "Bash(uv tool run dbt *)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)"
    ]
  },
  "hooks": {}
}
```

### Skills disponibles
Le dossier `.claude/skills/` contient :
- `hma-context` — contexte métier HMA (à déplacer depuis `SKILL.md` racine)
- `testing-strategy` — à créer
- `backend-senior`, `frontend-senior`, `architecture-senior`, `project-structure`, `ops-senior`

---

## 6. Workflow Spec-Driven Development

### Installation Spec Kit (une fois par machine)
```bash
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.7.2
```

### Initialiser Spec Kit dans le repo (une fois par projet)
```bash
specify init --here --ai claude --no-git
# ⚠️ Dire NON si ça veut écraser constitution.md (on garde le nôtre)
```

### Commandes par feature > 2 jours dev
```
/speckit.specify "Je veux …"        → spec
/speckit.clarify                    → résout ambiguïtés
/speckit.plan                       → plan technique
/speckit.tasks                      → décomposition
/speckit.analyze                    → quality gate
/speckit.implement                  → exécution
```

---

## 7. Troubleshooting

| Symptôme | Cause probable | Solution |
|---|---|---|
| `supabase start` timeout | Docker Desktop down | Redémarrer Docker Desktop |
| `supabase db reset` → RLS blocks insert | Session non-authentifiée exécute seed | Ajouter `set local role service_role;` en tête du seed |
| Next.js : hydration mismatch | Server/Client divergence sur date/random | Marquer `'use client'` ou passer la valeur par prop |
| `pnpm dev` → port 3000 busy | Instance précédente non tuée | `lsof -ti:3000 \| xargs kill` |
| dbt : `RelationNotFound` | Migration non appliquée | `supabase db reset` puis `dbt build` |
| ESLint : `no-restricted-imports` on `features/A` | Import cross-feature | Promouvoir vers `lib/` ou `components/` |
| Husky hook skip | `--no-verify` utilisé | **Jamais** utiliser `--no-verify`, corriger le hook |
| Coolify : build fail « out of memory » | VPS saturé | Nettoyer containers suspendus, upgrade RAM |

---

## 8. Checklist first-day (pour toi dans 3 mois)

- [ ] `node -v` → v20.x, `pnpm -v` → 9.x
- [ ] `docker ps` → fonctionne
- [ ] `supabase --version` OK
- [ ] `uv tool run dbt --version` OK
- [ ] `.env.local` rempli depuis Vaultwarden
- [ ] `pnpm install` passe
- [ ] `supabase start` → 7 services up
- [ ] `supabase db reset` → seed OK
- [ ] `pnpm test:unit` → passe
- [ ] `pnpm dev` → page login visible sur localhost:3000

Si les 10 passent : **tu es prêt**.

---

*Setup évolutif. Mettre à jour à chaque ajout de dépendance système ou secret.*
