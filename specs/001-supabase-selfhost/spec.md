# Feature Specification: Socle data self-hosted et souverain

**Feature Branch**: `001-supabase-selfhost`
**Created**: 2026-04-22
**Status**: Draft
**Input**: User description: "Supabase self-hosted (option #1 du cadrage Sprint 1) — plateforme data souveraine hébergée sur infrastructure sous contrôle, pré-requis de toutes les autres features MVP hmanagement"

## Clarifications

### Session 2026-04-22

- Q: Comment gérer le descope des tâches T014-T017 (création compte Brevo SMTP) et T024-T025 (création chat Telegram ops) sans casser US2 (auth MFA) ni US5 (notifications) ? → A: **Authentik OIDC comme IdP délégué**. L'authentification utilisateur (Magic Link, MFA TOTP, session) est entièrement déléguée au serveur Authentik self-hosted existant (`auth.hma.business`). GoTrue (Supabase) est configuré comme **OIDC relying party** d'Authentik. Conséquences : (a) aucun compte Brevo à créer — Authentik utilise son propre SMTP ; (b) les FR-006/007/008/009/010/013 restent valides mais leur **implémentation** est côté Authentik, pas côté GoTrue natif ; (c) nouveaux env vars GoTrue à prévoir : `GOTRUE_EXTERNAL_OIDC_*` ; (d) une feature ultérieure pourra revenir sur ce choix si l'ouverture multi-tenant l'exige (Strangler Fig Art. 11.1) ; (e) tasks.md à retravailler : T014-T017 supprimés, remplacés par des tâches de configuration OIDC côté Authentik + côté GoTrue.
- Q: Quel canal pour les notifications backup/monitoring maintenant que la création d'un nouveau chat Telegram (T024) est descopée ? → A: **Réutiliser un chat Telegram HMA existant** via le bot `hmagents_bot` (déjà dans Vaultwarden, alimente déjà n8n/Authentik). Conséquences : (a) US5 et FR-018/020/021/022 restent intacts ; (b) T024 (créer un nouveau chat) est supprimée, T025 (stocker chat_id) se transforme en "récupérer le chat_id existant depuis Vaultwarden ou l'historique Telegram" ; (c) les scripts déjà écrits (`pg-backup.sh`, `disk-alert.sh`) ne changent pas — ils utilisent `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` env vars ; (d) risque cosmétique de mélange avec d'autres notifications (n8n, Authentik) → atténué par le préfixe `[supabase-backup]` / `[restore-drill]` / `[disk-alert]` déjà présent dans les scripts.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Le super-admin dispose d'une plateforme data opérationnelle (Priority: P1)

Kiki (super-admin HMA) doit pouvoir, en fin de Sprint 1, accéder à une plateforme data hébergée sur infrastructure HMA contrôlée, accessible via un nom de domaine HTTPS stable, et utilisable immédiatement comme socle pour le reste du MVP (auth, schémas, pipelines, application).

**Why this priority**: Sans socle data, aucune autre brique MVP ne peut démarrer (auth, dbt, n8n, Next.js). C'est le **goulot d'étranglement** du Sprint 1.

**Independent Test**: Depuis un poste extérieur, le super-admin se connecte à l'URL d'administration de la plateforme, authentifie avec ses identifiants, et visualise une base de données vide opérationnelle. Test de connectivité réussi = feature validable indépendamment.

**Acceptance Scenarios**:

1. **Given** la plateforme est déployée, **When** le super-admin ouvre l'URL d'administration dans un navigateur, **Then** il voit l'interface d'administration servie en HTTPS avec un certificat valide.
2. **Given** le super-admin est authentifié sur l'interface d'administration, **When** il consulte la liste des bases de données, **Then** il voit au minimum une base PostgreSQL opérationnelle sans erreur.
3. **Given** la plateforme est déployée, **When** un outil externe (client SQL, script de diagnostic) se connecte à la base avec les identifiants service, **Then** la connexion aboutit et une requête `SELECT 1` renvoie le résultat attendu.
4. **Given** la plateforme est déployée, **When** le super-admin redémarre l'infrastructure hôte, **Then** la plateforme redémarre automatiquement et redevient accessible en moins de 5 minutes sans intervention manuelle.

---

### User Story 2 - Le super-admin peut authentifier des utilisateurs avec MFA renforcé (Priority: P1)

La plateforme doit exposer un service d'authentification permettant à un super-admin ou admin de se connecter par lien magique envoyé par email, avec activation obligatoire d'un second facteur TOTP (application d'authentification), conformément aux exigences de sécurité des données financières HMA.

**Why this priority**: La contrainte constitution Article 4.3 exige MFA obligatoire pour les rôles administrateurs. Sans ce service, aucun utilisateur ne peut accéder légitimement aux données financières.

**Independent Test**: Un compte super-admin de test reçoit un lien magique par email, clique dessus, est invité à configurer un code TOTP, puis complète l'authentification. Session active et vérifiable indépendamment de l'application MVP.

**Acceptance Scenarios**:

1. **Given** un compte super-admin existe, **When** il saisit son email dans le formulaire d'authentification, **Then** un email contenant un lien magique à usage unique est envoyé en moins de 60 secondes.
2. **Given** le super-admin clique sur le lien magique pour la première fois, **When** le flow lui propose l'activation MFA, **Then** l'activation TOTP est obligatoire et bloque la finalisation de session tant qu'elle n'est pas complétée.
3. **Given** un super-admin a activé MFA, **When** il tente une nouvelle connexion, **Then** le système exige à la fois le lien magique **et** un code TOTP valide à 6 chiffres.
4. **Given** un super-admin authentifié avec MFA, **When** 60 minutes s'écoulent sans activité, **Then** sa session expire automatiquement et il est redirigé vers le formulaire de connexion.
5. **Given** un lien magique a été cliqué une fois, **When** le même lien est réutilisé, **Then** le second usage est refusé avec un message d'erreur clair.

---

### User Story 3 - Les données sont sauvegardées quotidiennement et restaurables (Priority: P1)

La plateforme doit exécuter des sauvegardes chiffrées quotidiennes de toutes les données persistantes, stockées dans un emplacement distinct de l'hôte principal, avec un processus de restauration documenté et testable mensuellement.

**Why this priority**: La constitution Article 10.3 rend les sauvegardes testées mensuellement **obligatoires**. La perte de données financières est un risque inacceptable pour HMA.

**Independent Test**: Le super-admin déclenche manuellement une procédure de restauration sur un environnement de test, à partir d'une sauvegarde du jour précédent, et vérifie que les données sont intègres et cohérentes (ligne par ligne sur un échantillon).

**Acceptance Scenarios**:

1. **Given** la plateforme est en production, **When** 24 heures s'écoulent, **Then** au moins une nouvelle sauvegarde complète est présente dans l'emplacement de stockage dédié.
2. **Given** une sauvegarde a été produite, **When** le super-admin inspecte le fichier, **Then** celui-ci est chiffré (non lisible sans clé) et porte un horodatage exploitable.
3. **Given** une sauvegarde du jour J existe, **When** le super-admin exécute la procédure de restauration sur un environnement de test, **Then** la restauration aboutit en moins de 30 minutes et la base restaurée contient l'intégralité des données attendues.
4. **Given** la planification de sauvegarde est active, **When** une sauvegarde échoue, **Then** une notification est envoyée au super-admin dans les 15 minutes suivant l'échec.
5. **Given** les sauvegardes s'accumulent, **When** la rétention configurée est dépassée, **Then** les sauvegardes obsolètes sont automatiquement purgées sans intervention manuelle.

---

### User Story 4 - Les développeurs et outils internes consomment la plateforme via une API stable (Priority: P2)

Un développeur (ou un outil interne : orchestrateur de workflows, outil de transformation de données, application MVP) doit pouvoir se connecter à la plateforme via une API documentée, stable et contractuelle, en utilisant des identifiants techniques distincts des identifiants utilisateur.

**Why this priority**: Sans cette capacité, ni les pipelines de données ni l'application MVP ne peuvent consommer la plateforme. C'est un prérequis à toutes les features downstream.

**Independent Test**: Un script externe, muni d'une clé API service, effectue une opération de lecture et d'écriture sur une table de test, et reçoit des réponses conformes au contrat d'API documenté.

**Acceptance Scenarios**:

1. **Given** la plateforme est déployée, **When** un outil externe appelle l'API avec une clé service valide, **Then** la réponse HTTP est 200 et le contenu respecte le contrat documenté.
2. **Given** une clé API invalide ou expirée, **When** elle est utilisée pour un appel, **Then** la plateforme refuse l'appel avec un code d'erreur explicite.
3. **Given** une opération d'écriture via API, **When** elle aboutit, **Then** les données sont immédiatement lisibles par une opération de lecture postérieure.

---

### User Story 5 - Le super-admin est notifié en cas d'indisponibilité (Priority: P2)

Si la plateforme devient injoignable, si une sauvegarde échoue, ou si une erreur critique survient, le super-admin doit recevoir une notification active (pas uniquement un log à consulter) pour pouvoir intervenir rapidement.

**Why this priority**: Sans alertes actives, une panne peut passer inaperçue plusieurs heures — inacceptable pour un outil DAF en production. L'Article 10 de la constitution impose l'observabilité.

**Independent Test**: Simuler un arrêt volontaire de la plateforme, puis vérifier qu'une notification arrive dans le canal configuré (email, messagerie interne) en moins de 5 minutes.

**Acceptance Scenarios**:

1. **Given** la plateforme est en fonctionnement, **When** elle devient injoignable depuis l'extérieur pendant plus de 2 minutes consécutives, **Then** une notification d'alerte est envoyée au super-admin.
2. **Given** la plateforme est revenue en ligne, **When** le monitoring confirme la disponibilité, **Then** une notification de résolution est envoyée.
3. **Given** une sauvegarde échoue, **When** le job de sauvegarde se termine en erreur, **Then** une notification distincte est envoyée identifiant la cause probable.

---

### Edge Cases

- **Accès non autorisé** : si un tiers tente une énumération de comptes ou une attaque par force brute sur l'authentification, la plateforme doit bloquer temporairement les tentatives après un seuil raisonnable sans divulguer l'existence ou non des comptes testés.
- **Perte du secret de configuration** : si la base de secrets devient inaccessible (incident sur le gestionnaire de secrets), la plateforme doit continuer de fonctionner avec sa configuration active jusqu'au prochain redémarrage — pas de dépendance runtime dure au gestionnaire de secrets pour l'exécution courante.
- **Certificat HTTPS expiré** : le renouvellement doit être automatique, avec une alerte préventive 14 jours avant expiration au cas où le renouvellement échoue.
- **Disque plein sur l'hôte** : la plateforme doit refuser les écritures avec un message d'erreur explicite plutôt que corrompre silencieusement les données, et une alerte disque doit se déclencher bien avant (seuil 80 %).
- **Restauration partielle** : si une restauration de sauvegarde échoue en cours de route, l'état de la base doit rester celui d'avant tentative (pas d'état intermédiaire corrompu).
- **Clé API de service compromise** : le super-admin doit pouvoir révoquer une clé API en moins de 5 minutes et toutes les sessions/intégrations associées doivent cesser de fonctionner immédiatement.

## Requirements *(mandatory)*

### Functional Requirements

**Déploiement et accès**

- **FR-001**: La plateforme **MUST** être hébergée sur une infrastructure sous contrôle direct du projet (pas de SaaS tiers non souverain).
- **FR-002**: La plateforme **MUST** être accessible via un nom de domaine dédié servi en HTTPS avec un certificat reconnu et renouvelé automatiquement.
- **FR-003**: La plateforme **MUST** redémarrer automatiquement en moins de 5 minutes après un redémarrage de l'hôte, sans intervention humaine.
- **FR-004**: La plateforme **MUST** exposer une interface d'administration accessible au super-admin pour gérer les utilisateurs, les bases, les clés API et la configuration.
- **FR-005**: La plateforme **MUST** exposer un point d'accès PostgreSQL compatible avec les outils standards (clients SQL, ORMs, outils de transformation de données), protégé par identifiants.

**Authentification et sécurité**

- **FR-006**: La plateforme **MUST** déléguer l'authentification utilisateur à un fournisseur **OIDC self-hosted** (Authentik à `auth.hma.business`). Le mécanisme visible côté utilisateur — lien magique email, MFA TOTP, session — est implémenté **par l'IdP**. La plateforme (GoTrue / Supabase) est configurée comme **OIDC relying party** et accepte uniquement les identités authentifiées par l'IdP.
- **FR-007**: La plateforme **MUST** rendre obligatoire l'activation d'un second facteur TOTP pour les rôles super-admin et admin avant toute utilisation opérationnelle.
- **FR-008**: La plateforme **MUST** imposer une expiration de session automatique. Cibles : 8 heures maximum pour un utilisateur standard, 1 heure maximum pour un administrateur. **En MVP**, seuls des comptes administrateur existent et la plateforme applique donc uniformément la borne la plus stricte (1 heure) ; la différenciation "8 heures utilisateur standard" sera ajoutée par la couche applicative dès l'introduction des rôles non-administrateur (features ultérieures `002-schemas-rls-bootstrap` + app).
- **FR-009**: La plateforme **MUST** refuser tout lien magique après un premier usage (usage unique) et après 15 minutes d'inactivité.
- **FR-010**: La plateforme **MUST** vérifier les mots de passe éventuels contre une liste de compromissions connues au moment de leur création.
- **FR-011**: La plateforme **MUST** permettre au super-admin de générer, lister et révoquer des clés API service distinctes des comptes utilisateurs.
- **FR-012**: La plateforme **MUST** stocker tous ses secrets (clés JWT, mots de passe service, secrets SMTP, etc.) hors du code source, dans un emplacement chiffré accessible uniquement aux opérateurs autorisés.
- **FR-013**: La plateforme **MUST** limiter le nombre de tentatives d'authentification ratées et bloquer temporairement toute source qui dépasse un seuil raisonnable, sans divulguer l'existence des comptes.

**Sauvegardes et restauration**

- **FR-014**: La plateforme **MUST** produire une sauvegarde complète de toutes les données persistantes au moins une fois par 24 heures.
- **FR-015**: Les sauvegardes **MUST** être chiffrées au repos avec une clé qui n'est pas stockée à côté des sauvegardes elles-mêmes.
- **FR-016**: Les sauvegardes **MUST** être conservées pendant au minimum 30 jours avec rotation automatique au-delà.
- **FR-017**: Une procédure de restauration documentée **MUST** permettre à un super-admin de restaurer une sauvegarde donnée en moins de 30 minutes sur un environnement de test.
- **FR-018**: Le super-admin **MUST** recevoir une notification active en cas d'échec d'une sauvegarde planifiée, dans un délai maximum de 15 minutes après l'échec.

**Observabilité**

- **FR-019**: La plateforme **MUST** exposer des **endpoints de santé binaires (up/down, réponse HTTP structurée)** sur chacun de ses services principaux (interface admin, authentification, API REST), consommables par un outil de monitoring externe. Des métriques quantitatives détaillées (CPU, débit, latences internes, métriques PostgreSQL) ne sont **pas** exigées en MVP et feront l'objet d'une feature d'observabilité ultérieure.
- **FR-020**: Le super-admin **MUST** recevoir une notification active si la plateforme devient injoignable depuis un point d'observation externe pendant plus de 2 minutes consécutives.
- **FR-021**: Le super-admin **MUST** recevoir une alerte préventive au moins 14 jours avant l'expiration du certificat HTTPS.
- **FR-022**: Le super-admin **MUST** recevoir une alerte lorsque l'utilisation disque de l'hôte dépasse 80 %.
- **FR-023**: La plateforme **MUST** conserver un journal des événements d'authentification (succès, échecs, révocations) consultable par le super-admin pour audit.

**Multi-tenant-ready (contraintes architecturales héritées)**

- **FR-024**: La plateforme **MUST** permettre, à l'avenir, l'ajout de nouveaux tenants sans redéploiement de l'infrastructure (capacité d'isolation logique au niveau base).
- **FR-025**: La configuration initiale **MUST** fonctionner en mode mono-tenant avec un seul tenant logique `hma` actif.

**Exclusions explicites (hors scope Sprint 1)**

- L'application Next.js MVP n'est **PAS** livrée par cette feature.
- Les schémas applicatifs (`raw`, `staging`, `marts`, `app`), les tables métier, les policies RLS détaillées et les rôles applicatifs **NE SONT PAS** dans le scope (feature séparée).
- Les pipelines de données (synchronisation Pennylane, transformations dbt) **NE SONT PAS** dans le scope.
- L'invitation et la gestion fine des utilisateurs finaux (au-delà du premier super-admin) **NE SONT PAS** dans le scope.
- Les exports de données destinés aux utilisateurs finaux **NE SONT PAS** dans le scope.

### Key Entities *(include if feature involves data)*

- **Utilisateur de plateforme** : compte capable de s'authentifier sur la plateforme. Attributs métier pertinents : identifiant email, état MFA (activé/non), rôle logique associé (super-admin, admin), horodatage dernier accès.
- **Clé API service** : identifiant technique réservé aux intégrations machine-à-machine (orchestrateur, application, outils internes). Attributs : libellé, portée (lecture / écriture / admin), état (active / révoquée), date de création.
- **Sauvegarde** : artefact chiffré représentant l'état complet des données persistantes à un instant T. Attributs : horodatage, taille, somme de contrôle d'intégrité, emplacement de stockage.
- **Secret de configuration** : valeur sensible (clé, mot de passe, jeton) nécessaire au fonctionnement de la plateforme. Attributs : identifiant, dernière rotation, emplacement canonique de stockage.
- **Événement d'authentification** : trace d'une tentative de connexion, succès ou échec, consultable pour audit.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Le super-admin peut accéder à l'interface d'administration de la plateforme via son URL HTTPS en moins de 3 secondes depuis un navigateur standard, avec un certificat reconnu valide.
- **SC-002**: Le super-admin active un nouveau compte avec MFA TOTP de bout en bout en moins de 5 minutes, sans aide extérieure, en suivant uniquement la procédure documentée.
- **SC-003**: 100 % des sauvegardes planifiées d'une fenêtre de 30 jours aboutissent avec succès.
- **SC-004**: Une restauration de sauvegarde ponctuelle sur un environnement de test aboutit en moins de 30 minutes, avec vérification d'intégrité sur un échantillon des données clés.
- **SC-005**: Un redémarrage de l'hôte remet la plateforme en ligne et accessible via son URL en moins de 5 minutes.
- **SC-006a** (*perf serveur — contractuel*) : Un outil externe maintenant une connexion HTTPS persistante (keepalive) et muni d'une clé API service valide effectue chaque requête REST (GET, POST, GET) en **moins de 300 ms de TTFB warm**, et la séquence lecture-écriture-lecture cumulée en **moins de 2 secondes** (hors setup TLS initial). Mesure la perf serveur pure (PostgreSQL + PostgREST), indépendante de la géo du client. Régression = problème côté plateforme.
- **SC-006b** (*UX utilisateur — observationnel, non bloquant*) : Pour un client créant une nouvelle connexion TLS par requête (cas worst-case : script cURL ad-hoc, test de CI non optimisé), la même séquence read-write-read exécutée depuis la Guyane française vers le VPS EU s'exécute **typiquement en moins de 5 secondes cumulées**. Baseline observée : RTT physique ~230 ms + TLS handshake ~3×RTT par connexion fraîche. Ce critère n'est **pas une promesse serveur ni un gate de build** — la mesure one-shot est volatile (jitter TLS/réseau). Son rôle : sentinelle pour détecter une dégradation structurelle (ex. configuration Traefik, cert chain trop long) qui ferait exploser le coût par connexion au-delà de 1.5 s de façon récurrente. Mode d'évaluation : si une mesure dépasse 5 s, le script warn ; si 3 mesures consécutives dépassent, investiguer.
- **SC-007**: Aucun secret de configuration n'est présent en clair dans le dépôt de code ou les logs (vérifiable par inspection automatisée au moment de la clôture de la feature).
- **SC-008**: Une révocation d'une clé API service prend effet en moins de 5 minutes (les appels suivants sont rejetés).
- **SC-009**: Le super-admin est notifié d'une indisponibilité simulée (arrêt volontaire) en moins de 5 minutes.
- **SC-010**: 0 incident de sécurité dû à un défaut de configuration identifiable sur la plateforme pendant le premier mois d'exploitation (audit initial sans alerte critique).

## Assumptions

- **Infrastructure** : un serveur hôte suffisamment dimensionné pour héberger la plateforme est déjà provisionné et accessible par le super-admin. Le choix précis du fournisseur est tranché par la constitution et la stack figée du projet, pas par cette spec.
- **Nom de domaine** : un nom de domaine dédié est disponible ou acquis avant le démarrage des travaux de déploiement. Le choix précis (sous-domaine) est de l'ordre du plan d'implémentation, pas de la spec.
- **Messagerie sortante** : l'authentification utilisateur est déléguée à **Authentik** (décidé Session 2026-04-22) ; l'envoi des liens magiques est géré par le SMTP déjà configuré dans Authentik — aucun service email supplémentaire à provisionner côté Supabase.
- **Gestionnaire de secrets** : un gestionnaire de secrets self-hosted est déjà en service pour stocker les secrets de configuration (existant dans les intégrations du projet).
- **Canal de notification** : le super-admin dispose d'un canal de messagerie (email, messagerie d'équipe) déjà utilisé par le projet pour recevoir les alertes, configurable par l'opérateur.
- **Compétences opérateur** : le super-admin a accès à un client SQL et aux outils administrateur standards pour vérifier manuellement l'état de la plateforme si nécessaire.
- **Stack technique figée** : le choix de la plateforme Supabase self-hosted est acté par la constitution du projet et n'est pas rediscuté dans cette spec. L'objet de la spec est de décrire **ce que la plateforme doit fournir**, pas **quelle plateforme choisir**.
- **Portée temporelle** : cette feature est le socle du Sprint 1. Les features qui en dépendent (schémas, RLS détaillée, application, pipelines) feront l'objet de spécifications ultérieures.

## Dependencies

- Disponibilité confirmée du serveur hôte et des accès réseau entrants (ports HTTPS, SSH administrateur).
- Disponibilité confirmée du nom de domaine et droits de configuration DNS.
- Disponibilité confirmée du serveur **Authentik** (`auth.hma.business`) en état opérationnel, configuré en production (SMTP interne actif, groupes et policies gérables), et du droit d'y créer une application OAuth client pour GoTrue.
- Disponibilité confirmée du gestionnaire de secrets self-hosted, accessible par le super-admin.
- Canal de notification : **chat Telegram HMA existant** joint par le bot `hmagents_bot` (credential Vaultwarden `Telegram Bot — HMAGENTS`). Le `chat_id` de ce chat est présumé déjà connu ou récupérable depuis l'historique Telegram ; aucun nouveau chat n'est à créer pour cette feature.
