# Security Requirements Quality Checklist: Socle data self-hosted et souverain

**Purpose**: Valider la **qualité des requirements sécurité** (auth, secrets, crypto, audit, rate-limit, souveraineté, DR) de la spec feature 001. Ne teste PAS si le système est sécurisé — teste si les requirements de sécurité sont bien écrits, mesurables, complets et cohérents avec la constitution (Art. 4 notamment).
**Mode**: Formal release gate — à passer avant merge sur `main` + revue sécurité systématique.
**Created**: 2026-04-23
**Feature**: [spec.md](../spec.md) · [plan.md](../plan.md) · [tasks.md](../tasks.md) · [research.md](../research.md)
**Constitution refs**: Art. 2 (souveraineté), Art. 4 (sécurité), Art. 10.3 (sauvegardes)

---

## Authentication Requirements Quality (AuthN)

- [ ] CHK001 FR-006 définit-elle **exhaustivement** le mécanisme d'auth accepté (OIDC via Authentik) ET rejette-t-elle explicitement les alternatives (password direct, API tokens longs, etc.) ? [Completeness, Spec §FR-006]
- [ ] CHK002 La contrainte "MFA TOTP obligatoire pour super_admin et admin" (FR-007) définit-elle **comment** le système détecte le rôle au moment de l'auth (claim JWT ? group Authentik ? policy applicative ?) ? [Clarity, Spec §FR-007]
- [ ] CHK003 Le cap session "1h admin / 8h user" (FR-008) est-il mesurable avec des **unités explicites** (minutes ? secondes ?) et un **moment de référence** clair (iat vs idle timeout) ? [Measurability, Spec §FR-008]
- [ ] CHK004 FR-009 "Magic Link expire après 15 min d'inactivité" — "inactivité" est-il défini de manière mesurable (pas de clic ? pas de requête au backend ? session non-utilisée ?) ? [Ambiguity, Spec §FR-009]
- [ ] CHK005 La règle "usage unique" du Magic Link (FR-009) spécifie-t-elle le comportement si l'utilisateur clique 2× rapidement (race condition : accepter ? rejeter ? 1er arrivé gagne ?) ? [Gap, Edge Case]
- [ ] CHK006 Le mécanisme d'auth pour les **non-humains** (scripts backup, app MVP future, n8n) est-il distinctement spécifié (clés API service-role ?) ou mélangé avec l'auth humaine ? [Clarity, Spec §FR-011]
- [ ] CHK007 L'état post-déconnexion (logout) est-il spécifié (invalidation JWT côté Authentik ? côté GoTrue ? blacklist de tokens ?) ? [Gap, Completeness]

## Authorization & Role Management Requirements

- [ ] CHK008 Les 4 rôles (super_admin, admin, controleur, consultant) sont-ils mentionnés dans la spec de cette feature ou reportés à feature 002 ? [Coverage, Spec §FR-024/025]
- [ ] CHK009 La spec définit-elle le **mapping entre groupe Authentik et rôle DB PostgreSQL** ou est-ce flou ? [Gap, Consistency]
- [ ] CHK010 Les requirements d'**escalade** (super_admin devient admin temporairement) sont-ils spécifiés ou hors scope ? [Coverage, Gap]
- [ ] CHK011 FR-011 "clés API service distinctes des comptes utilisateurs" — la spec définit-elle le **nombre max** de clés actives, les permissions par défaut, les modalités de révocation individuelles ? [Completeness, Spec §FR-011]

## Secrets Management Requirements

- [ ] CHK012 "Secrets stockés hors du code source" (FR-012) — définit-elle de manière exhaustive **où** (Vaultwarden uniquement ? env vars Coolify ? fichier `/etc` chiffré ?) ou laisse-t-elle ambigu ? [Completeness, Spec §FR-012]
- [ ] CHK013 Le **cold storage papier obligatoire** du `RESTIC_PASSWORD` (issu de la T023.5) est-il dans la spec ou seulement dans les runbooks/tasks ? [Traceability, Gap]
- [ ] CHK014 La cadence de rotation par type de secret (trimestriel JWT, annuel SMTP/R2) est-elle dans un **tableau normatif** de la spec ou noyée dans research/runbooks ? [Clarity, Gap]
- [ ] CHK015 Les requirements pour la **génération** des secrets (entropie min, charset, longueur) sont-ils spécifiés par type ou laissés à l'opérateur ? [Completeness, Gap]
- [ ] CHK016 Le comportement en cas de **fuite suspectée** (procédure de rotation d'urgence) est-il formalisé dans la spec avec un SLO de remédiation ? [Gap, Exception Flow]

## Encryption Requirements

- [ ] CHK017 Le chiffrement "au repos" (FR-015) des backups est-il défini avec un **algorithme minimum** (AES-256 ? ChaCha20 ?) ou laissé à `restic` par défaut ? [Completeness, Spec §FR-015]
- [ ] CHK018 Le chiffrement "en transit" pour TOUS les endpoints (FR-002) est-il spécifié avec une **version TLS minimum** (TLS 1.2 ? 1.3 only ?) et cipher suites ? [Gap, Spec §FR-002]
- [ ] CHK019 Les requirements de chiffrement pour les **données en mémoire** (secrets chargés dans env var container) sont-ils adressés ou hors scope ? [Gap, Coverage]
- [ ] CHK020 La **clé de chiffrement R2** vs la **RESTIC_PASSWORD** : la spec distingue-t-elle clairement qu'une fuite R2 access key ne compromet pas les backups (car chiffrés client-side par restic) ? [Clarity, Spec §FR-015]

## Audit & Logging Requirements

- [ ] CHK021 FR-023 "journal des événements d'authentification" — définit-elle **quels événements** (succès, échec, révocation, changement password, activation MFA) de manière exhaustive ? [Completeness, Spec §FR-023]
- [ ] CHK022 La **rétention** du journal d'auth est-elle quantifiée (7 jours ? 90 jours ? 1 an pour RGPD ?) ? [Clarity, Gap]
- [ ] CHK023 Les requirements d'**immuabilité** du journal (pas d'UPDATE/DELETE possible) sont-ils dans la spec ou seulement dans la constitution (Art. 4.4) ? [Consistency, Spec §FR-023]
- [ ] CHK024 La **localisation du journal** (logs GoTrue stdout + Coolify, OU Authentik Events upstream, OU les deux) est-elle spécifiée, ou ambiguë ? [Ambiguity, Spec §FR-023]
- [ ] CHK025 Les événements **ops sensibles** (création/suppression de backup, rotation de secret, restart service) sont-ils exigés dans l'audit log ou seulement les événements auth ? [Coverage, Gap]

## Rate Limiting & Abuse Protection

- [ ] CHK026 FR-013 "seuil raisonnable" — est-il quantifié avec un chiffre concret (ex. ≥ 30 tentatives/heure/IP) dans la spec, ou juste "raisonnable" ? [Ambiguity, Spec §FR-013]
- [ ] CHK027 Le "bloc temporaire" après dépassement (FR-013) définit-il la **durée** du bloc (5 min ? 1h ? escalade ?) ? [Clarity, Spec §FR-013]
- [ ] CHK028 La protection "sans divulguer l'existence des comptes" (FR-013) est-elle testable objectivement (ex. même réponse HTTP/timing pour email existant vs inexistant) ? [Measurability, Spec §FR-013]
- [ ] CHK029 Les requirements de **rate limiting API service-role** (pas juste login) sont-ils couverts ? [Gap, Coverage]

## Data Residency & Sovereignty

- [ ] CHK030 Art. 2 constitution exige "infrastructure sous contrôle" — la spec précise-t-elle les **régions acceptables** pour chaque dépendance (VPS Hostinger = où ? R2 = EU ? Telegram = ?) ? [Completeness, Spec §FR-001]
- [ ] CHK031 Le critère "pas de SaaS US" est-il **mesurable** (ex. liste de providers acceptables vs interdits dans la spec) ou subjectif au cas par cas ? [Clarity, Ambiguity]
- [ ] CHK032 Le **cas Telegram** (hosted in UAE, not fully aligned with EU sovereignty) est-il explicitement exempté dans la spec (car utilisé uniquement pour notif ops, pas données HMA) ? [Consistency, Gap]
- [ ] CHK033 Les exigences de **portabilité/réversibilité** vers d'autres providers (R2 → OVH Object Storage en cas de besoin) sont-elles explicitement dans la spec ? [Gap, Non-Functional]

## Network & Access Control

- [ ] CHK034 La spec exige-t-elle que **port 5432 PostgreSQL ne soit PAS exposé publiquement** (ou seulement implicite dans `admin-api-contract.md`) ? [Completeness, Gap]
- [ ] CHK035 Les exigences de **liste de ports autorisés** (80 redirect + 443 uniquement) sont-elles dans la spec (FR ?) ou dans un contrat annexe ? [Traceability, Gap]
- [ ] CHK036 La **vérification nmap clean** (SC-010) est-elle reproductible par un auditeur externe (ex. quelle IP source ? quelle fréquence ?) ? [Measurability, Spec §SC-010]
- [ ] CHK037 Les requirements de **network isolation** (Supabase vs Authentik vs n8n — chacun son réseau Docker ou partagé) sont-ils dans la spec ? [Gap, Coverage]

## Compliance & Governance

- [ ] CHK038 Les obligations **RGPD** (DPA, registre des traitements, droit à l'oubli) sont-elles mentionnées dans la spec ou hors scope MVP ? [Coverage, Gap]
- [ ] CHK039 Les obligations spécifiques **ultramarines** (LODEOM, Octroi de Mer) — pertinentes pour HMA en Guyane — sont-elles référencées ? [Coverage, Gap]
- [ ] CHK040 Les requirements de **consentement à l'envoi de données** (ex. si n8n envoie à un LLM externe) sont-ils formalisés ? [Gap, Coverage]

## Disaster Recovery Security

- [ ] CHK041 La spec définit-elle un **scénario DR concret** (perte Vaultwarden + PG simultanée) avec procédure de récupération testable ? [Coverage, Exception Flow]
- [ ] CHK042 Les requirements pour la **revalidation annuelle** du cold storage papier (test de transcription) sont-ils spécifiés ou implicites ? [Gap, Non-Functional]
- [ ] CHK043 Le scénario "clé API service-role compromise" (fuite dans un script client, commit accidentel) définit-il un délai de révocation objectif (SC-008 dit "< 5 min" — testable ?) ? [Measurability, Spec §SC-008]

---

## Notes

- **Items traçables** : 41/43 (~95%) avec référence `[Spec §…]`, `[Gap]`, `[Ambiguity]`, ou constitution article.
- **Items `[Gap]`** : ~18 — concentration sur DR scénarios, compliance RGPD/LODEOM, rate-limits non-login — **candidats V2 ou feature 002+** (002-schemas-rls-bootstrap traitera RBAC + RLS + audit_log).
- **Items `[Ambiguity]`** : ~5 — cibles prioritaires d'un prochain `/speckit-clarify` orienté sécurité.
- **Intersection avec `ops.md`** : quelques items (cold storage, rotation cadence) apparaissent dans les 2 — intentionnel pour couvrir les 2 angles.

### Priorités senior identifiées

Les items **les plus critiques** pour un release gate (à cocher ou diffré explicitement) :

1. **CHK002** (comment FR-007 détecte le rôle MFA-required)
2. **CHK009** (mapping groupe Authentik → rôle DB PG)
3. **CHK026** (FR-013 chiffre concret de rate-limit — déjà adressé en round 2 dans research.md R-007 mais pas remonté dans spec)
4. **CHK030** (liste régions acceptables par dépendance)
5. **CHK034** (explicite interdiction port 5432 public)
6. **CHK041** (scénario DR Vaultwarden + PG simultanée)

Pour release gate, cible réaliste : **≥ 80% d'items cochés ✅ ou différés**, avec **100% des 6 priorités senior** adressés avant merge main.
