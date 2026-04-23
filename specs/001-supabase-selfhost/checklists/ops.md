# Ops Requirements Quality Checklist: Socle data self-hosted et souverain

**Purpose**: Valider la **qualité des requirements opérationnels** (deploy, backup, monitoring, incident, rotation) de la spec feature 001. Ne teste PAS si la plateforme marche — teste si les requirements sont bien écrits, mesurables, complets et cohérents.
**Mode**: Formal release gate — à passer avant merge sur `main`.
**Created**: 2026-04-23
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [tasks.md](../tasks.md) · [research.md](../research.md)

**Rappel senior** : un item coché ≠ "ça marche en prod". Un item coché = "la spec est claire, complète et mesurable sur ce point". Si ça coince, la spec doit évoluer (via `/speckit-clarify` ou edit chirurgical), pas l'implem.

---

## Deployment Requirements Quality

- [ ] CHK001 Le domaine cible (`supabase.hma.business`) est-il explicitement spécifié dans la spec au niveau FR ou seulement dans Assumptions/Dependencies ? [Completeness, Spec §FR-002]
- [ ] CHK002 Les composants **conteneurs attendus** (PostgreSQL, GoTrue, PostgREST, Studio, Kong, Storage, Realtime, etc.) sont-ils listés exhaustivement dans la spec ou laissés implicites ? [Completeness, Gap]
- [ ] CHK003 Le "temps de redémarrage automatique < 5 min" (FR-003) est-il quantifié avec une **méthode de mesure** reproductible (à partir de quel événement le compteur démarre ?) ? [Measurability, Spec §FR-003]
- [ ] CHK004 Le scope "redémarrage de l'hôte" dans FR-003 est-il distinct d'un "redémarrage de la stack Supabase" ? Les deux sont-ils couverts ou seulement l'un ? [Clarity, Spec §FR-003]
- [ ] CHK005 Les pré-requis matériels/logiciels (VPS, Docker, Coolify, Traefik) sont-ils explicitement listés avec versions minimales dans Dependencies ou implicites dans Assumptions ? [Completeness, Spec §Dependencies]
- [ ] CHK006 La spec définit-elle le comportement **attendu en cas d'échec de déploiement** (rollback automatique ? rollback manuel ? état dégradé acceptable ?) ? [Gap, Recovery Flow]

## Backup Requirements Quality

- [ ] CHK007 La fréquence de backup (FR-014) est-elle quantifiée avec un intervalle maximum explicite (24h) ET un temps cible (ex. 03h30 UTC) ? [Clarity, Spec §FR-014]
- [ ] CHK008 Les requirements de **type de backup** (full vs incrémental vs dump logique vs physique) sont-ils spécifiés ou laissés à l'implémentation ? [Completeness, Gap]
- [ ] CHK009 La condition "chiffré avec clé qui n'est pas stockée à côté" (FR-015) définit-elle "à côté" de manière mesurable (même DB ? même serveur ? même provider ?) ? [Ambiguity, Spec §FR-015]
- [ ] CHK010 La rétention minimale "30 jours" (FR-016) spécifie-t-elle le **type de rétention** (daily ? monthly ? rolling window ?) — research.md R-004 dit 30 daily + 12 monthly, mais la spec seule ? [Clarity, Spec §FR-016]
- [ ] CHK011 Les requirements de **test d'intégrité post-backup** (ex. checksum, pg_restore --list) sont-ils explicites dans la spec ? [Gap, Completeness]
- [ ] CHK012 Le scope "toutes les données persistantes" (FR-014) inclut-il de façon mesurable les volumes Docker, les uploads Storage, les secrets GoTrue, ou se limite-t-il à PostgreSQL ? [Clarity, Spec §FR-014]

## Restore Requirements Quality

- [ ] CHK013 Le délai "moins de 30 minutes" (FR-017) définit-il clairement le **T0** et **T1** du chronomètre (download inclus ? smoke-test inclus ?) ? [Measurability, Spec §FR-017]
- [ ] CHK014 Les requirements de **cadence de drill** (mensuel obligatoire) sont-ils dans la spec ou uniquement dans la constitution (Art. 10.3) ? [Consistency, Gap]
- [ ] CHK015 Le "smoke-test" post-restauration est-il défini avec **critères objectifs** (combien de tables ? combien de relations ? quelle assertion métier ?) ou laissé libre à l'opérateur ? [Measurability, Spec §FR-017]
- [ ] CHK016 Les requirements spécifient-ils ce qui se passe **en cas d'échec** d'un drill (alerte ? blocage du prochain cycle ? escalade ?) ? [Gap, Exception Flow]
- [ ] CHK017 Le scénario "restauration en conditions réelles" (vs drill) est-il distingué dans la spec avec des exigences différentes (ex. restauration acceptant perte de données) ? [Coverage, Gap]

## Monitoring & Alerting Requirements Quality

- [ ] CHK018 Le terme "indisponibilité" (FR-020) est-il quantifié avec un seuil de détection mesurable (combien de checks KO consécutifs ? sur quelle cadence ?) ? [Ambiguity, Spec §FR-020]
- [ ] CHK019 FR-019 parle de "métriques de santé" et FR-019 actuelle dit "endpoints binaires up/down" — y a-t-il une **liste exhaustive** des services à monitorer ou est-ce laissé à l'implémentation ? [Completeness, Spec §FR-019]
- [ ] CHK020 Le "point d'observation externe" (FR-020) est-il défini de manière vérifiable (hors VPS ? depuis quelle région ?) ou laissé ambigu ? [Clarity, Spec §FR-020]
- [ ] CHK021 Le seuil "80 %" disque (FR-022) spécifie-t-il **quel point de montage** (le volume Docker ? la partition racine ? tous les volumes ?) ? [Clarity, Spec §FR-022]
- [ ] CHK022 Le délai "14 jours avant expiration" (FR-021) définit-il la **cadence de re-alerte** si l'alerte initiale n'est pas traitée (silence jusqu'à l'expiration ? re-alerte quotidienne ?) ? [Gap, Spec §FR-021]
- [ ] CHK023 Les requirements de **canal de notification** (Telegram `hmagents_bot`) sont-ils dans la spec ou seulement dans Assumptions/plan.md ? [Traceability, Gap]
- [ ] CHK024 Le comportement si le canal de notification est injoignable (fallback email ? queue ? logs only ?) est-il spécifié ? [Gap, Exception Flow]

## Incident Response Requirements Quality

- [ ] CHK025 La spec définit-elle le **SLO/MTTR cible** pour les incidents (ex. 30 min de résolution médiane) ou est-ce absent ? [Gap, Non-Functional]
- [ ] CHK026 La responsabilité d'astreinte/on-call pour les incidents est-elle documentée dans la spec ou laissée implicite (Kiki super_admin par défaut) ? [Completeness, Gap]
- [ ] CHK027 Les requirements de **consignation post-mortem** sont-ils formalisés (format, délai, accessibilité) ? [Gap]

## Configuration & Rotation Requirements Quality

- [ ] CHK028 La cadence de rotation des secrets (FR-012 + research R-006 disent trimestriel pour JWT, annuel pour autres) est-elle **cohérente** entre spec, research et runbook ? [Consistency, Spec §FR-012]
- [ ] CHK029 Les requirements de **gestion du drift** quand un secret change (propagation à tous les consommateurs : n8n, app, scripts backup) sont-ils spécifiés ? [Gap, Completeness]
- [ ] CHK030 Le runbook `supabase-secret-rotation.md` documente 4 types de rotation — la spec en mentionne-t-elle explicitement 4, ou se limite-t-elle à "rotation trimestrielle/annuelle" agrégée ? [Consistency, Spec §FR-012]
- [ ] CHK031 L'impact d'une rotation sur les **sessions utilisateurs actives** est-il spécifié (invalidation forcée ? transition transparente ?) ? [Gap, Non-Functional]

## External Dependencies Quality

- [ ] CHK032 Les dépendances externes critiques (Cloudflare DNS, R2, Coolify, Authentik, Telegram API, Let's Encrypt) sont-elles **listées exhaustivement** dans Dependencies ou partiellement ? [Completeness, Spec §Dependencies]
- [ ] CHK033 Pour chaque dépendance externe, la spec définit-elle le **comportement de dégradation** en cas d'indisponibilité ? (ex. R2 down → backups queue locale ? Telegram down → fallback email ?) [Gap, Exception Flow]
- [ ] CHK034 La contrainte "zéro SaaS non-souverain" (Art. 2 constitution) est-elle cohérente avec l'usage de Cloudflare (US-based company, même si services EU) ? [Consistency, Gap]
- [ ] CHK035 Les requirements de **SLA attendu** des fournisseurs externes sont-ils formalisés (Cloudflare R2 99.9% ? Hostinger VPS ? Authentik self-hosted = notre SLA) ? [Gap, Non-Functional]

## Runbook & Documentation Quality

- [ ] CHK036 La spec liste-t-elle les runbooks obligatoires (`supabase-deploy.md`, `supabase-restore-drill.md`, `supabase-secret-rotation.md`, `supabase-incident.md`) ou laisse-t-elle l'opérateur improviser ? [Completeness, Gap]
- [ ] CHK037 Les runbooks sont-ils exigés comme **livrable de la feature** (avec critères d'acceptation) ou produits best-effort ? [Acceptance Criteria, Gap]
- [ ] CHK038 La spec définit-elle un critère de **maintenance cyclique** des runbooks (ex. revue trimestrielle, sync avec infra changes) ? [Gap]

## Non-Functional Operational Requirements

- [ ] CHK039 Les requirements de **performance** sont-ils chiffrés (latence p95 < 800 ms depuis Internet pour API REST — est-ce dans plan.md seulement ou dans spec NFR ?) ? [Measurability, Gap]
- [ ] CHK040 Les requirements de **capacité/scaling** (utilisateurs concurrents, volume de données à 6/12 mois) sont-ils quantifiés dans la spec ? [Gap, Non-Functional]
- [ ] CHK041 Les requirements de **disponibilité annuelle** (ex. 99% = 3.65j/an downtime acceptable) sont-ils explicites ou implicites ? [Gap, Non-Functional]
- [ ] CHK042 Le critère "zéro incident de sécurité 1er mois" (SC-010) est-il **mesurable objectivement** (qui audite ? avec quelle méthode ? seuil nmap clean ?) ou subjectif ? [Measurability, Spec §SC-010]

---

## Notes

- **Items traçables** : 40/42 (~95%) avec référence `[Spec §…]`, `[Gap]`, `[Ambiguity]`, etc.
- **Items `[Gap]`** : ~14 — beaucoup signalent des requirements manquants NFR/Exception Flow à considérer **V2** ou **feature 002+**.
- **Items `[Ambiguity]` / `[Clarity]`** : ~8 — cibles d'un prochain `/speckit-clarify` si l'équipe grandit.
- Un item coché ✅ signifie **la spec répond à la question positivement** (le requirement est bien écrit sur ce point).
- Un item coché ❌ signifie **la spec ne couvre pas / mal / ambigu** — à amender avant merge si cochable d'un trait, ou à différer explicitement (V2 / feature suivante) sinon.

Pour release gate, cible réaliste : **≥ 85% d'items cochés ✅ ou explicitement différés** avant merge main.
