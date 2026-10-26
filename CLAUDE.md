# Devis — app locale PostgREST + htmx + PostgreSQL

Outil personnel de saisie de devis (quelques minutes par devis), historique complet en base.
**100 % local** : tout est lié à `127.0.0.1`, aucune authentification (volontaire : pas de JWT, un seul rôle).

## Démarrage
```
make up        # http://127.0.0.1:8080  (Docker Desktop doit tourner)
make open      # ouvre le navigateur
make seed      # (option) données de démo
make down      # arrête, données conservées
```
Autres : `make logs`, `make psql`, `make api` (recrée util+api sans perdre les données),
`make backup` / `make restore FILE=backups/x.sql`, `make reset` (**efface tout**).
Config : `.env` (gitignoré, modèle `.env.example`). Postgres accessible sur `127.0.0.1:5433`.

## Architecture
```
navigateur → nginx :8080 ─ /      → web/ (htmx vendorisé, css, js)
                         └ /api/* → PostgREST :3000 (non publié) → PostgreSQL 16 (volume devis_pgdata)
```
- **Schémas SQL** : `data` (tables, jamais exposé) · `util` (helpers HTML, non exposé) · `api` (seul schéma exposé).
- **Un seul rôle** `web_anon` : PostgREST se connecte avec (`PGRST_DB_URI`) et l'utilise comme rôle anonyme
  (`PGRST_DB_ANON_ROLE`). Il n'a **que** `USAGE` sur `api` + `EXECUTE` sur ses fonctions (EXECUTE retiré à `PUBLIC`).
  Les fonctions `api.*` sont `SECURITY DEFINER` avec `search_path` fixé.
- **htmx ↔ PostgREST** : les fonctions RPC renvoient du HTML (domaine `api."text/html"` = media type handler PostgREST).
  Le body porte `hx-headers='{"Accept":"text/html"}'` et `hx-ext="json-enc"` (POST en JSON, clés = noms des paramètres).
- `enregistrer_devis(jsonb)` a un **paramètre jsonb unique et sans nom** : PostgREST y passe tout le corps JSON du
  formulaire (ne pas utiliser `Prefer: params=single-object`, supprimé depuis PostgREST v13). Les champs répétés
  (lignes) arrivent en tableau, ou en simple chaîne s'il n'y a qu'une ligne → `util.as_arr()`.

## Fichiers
| Fichier | Rôle |
|---|---|
| `db/init.sql` | point d'entrée, joué par Postgres **au 1er démarrage seulement** : inclut les fichiers ci-dessous dans l'ordre |
| `db/roles.sql` | rôle `web_anon` (mot de passe `WEB_ANON_PASSWORD` du `.env`, lu via `\getenv`) |
| `db/tables.sql` | schéma `data` : tables, numérotation `DEV-AAAA-NNNN`, trigger `updated_at`, vue des totaux |
| `db/util.sql` | schéma `util` : helpers HTML (`esc`, `money`, `ligne`, `table_devis`…) — recréé par `make api` |
| `db/api.sql` | schéma `api` : fonctions RPC exposées + droits — recréé par `make api` |
| `db/seed_demo.sql` | données de démo (`make seed`) |
| `web/` | `index.html`, `css/app.css`, `js/app.js` (totaux en direct, toasts), `js/htmx.min.js` 2.0.4, `js/json-enc.js` |

Le dossier `db/` est monté dans le conteneur Postgres sur `/db` (utilisé par `init.sql`, `make api`, `make seed`).

## Conventions (à respecter)
- **Noms de fichiers clairs, sans préfixe numéroté** : l'ordre d'exécution est défini dans `db/init.sql`.
- **Toute valeur issue de la base/utilisateur passe par `util.esc()`** avant d'être mise dans du HTML (anti-XSS).
- Fonctions de lecture : `STABLE` (PostgREST les appelle en GET) ; écritures : volatiles, appelées en POST.
- Erreurs métier : `RAISE EXCEPTION 'message lisible'` → affiché en toast (`htmx:responseError`).
- Totaux jamais stockés : calculés dans `data.v_devis_totaux` (arrondi par ligne, identique dans `recalc()` de `app.js`).
- Modif SQL sur base existante :
  - `util.sql` / `api.sql` : éditer puis `make api`. Ces schémas ne contiennent que du code : ils sont supprimés
    puis recréés (`DROP SCHEMA … CASCADE`) dans une transaction. Changer une signature ou supprimer une fonction
    ne demande donc rien de plus.
  - `tables.sql` : `make backup` puis `make reset` (les scripts d'init ne rejouent que sur volume vide).

## Conformité avec la doc PostgREST (vérifiée le 2026-10-20)
Conforme à https://docs.postgrest.org (sources : dépôt `PostgREST/postgrest`, dossier `docs/`) :
isolation de schéma (seul `api` exposé), media type handler `"text/html"` (cf. how-to « Providing HTML Content
Using Htmx »), `SECURITY DEFINER`, EXECUTE retiré à `PUBLIC`, fonction à paramètre JSON unique sans nom, rechargement
du cache par `NOTIFY pgrst, 'reload schema'`.
- Écart volontaire : la doc décrit un rôle `authenticator` (connexion) distinct du rôle anonyme, utile seulement
  avec JWT. Sans authentification, `web_anon` sert aux deux (les noms de rôles sont libres d'après la doc).
- Version : l'image est figée sur `postgrest/postgrest:v12.2.3` ; la dernière version est la v16.5 (2026-10-20).
  Plus rien dans le projet n'utilise de fonctionnalité supprimée en v13–v16, mais la montée de version reste à tester.

## Suivi
- [x] Phase 1 — Fondations : docker-compose, rôles, schéma, nginx
- [x] Phase 2 — Clients + devis : tables, RPC HTML (testées en curl : création 1/3 lignes, XSS échappé, statut, erreurs)
- [x] Phase 3 — Front htmx : liste + recherche/filtre, formulaire à lignes dynamiques, édition, statut inline, suppression
- [x] Phase 4 — Aperçu imprimable (`window.print()` → PDF), totaux en direct
- [x] Phase 5 — `make backup` / `restore` testés, persistance après redémarrage vérifiée, `seed_demo.sql`
- [x] Phase 6 — Réorganisation (2026-10-20) : fichiers SQL sans numéros, un seul rôle (plus d'`authenticator`),
      `make api` recrée util+api, suppression de `Prefer: params=single-object` et de la config inutile.
      Retesté en curl sur une stack isolée (pages, création 1/3 lignes, XSS, erreurs, statut, droits, backup/restore).
- [ ] Vérification visuelle complète dans le navigateur (à faire par l'utilisateur : `make open`)

## Idées futures (non faites)
- Modifier un client existant (aujourd'hui : ajout/suppression seulement)
- Bloc « émetteur » (nom, adresse, SIRET, mentions légales) sur l'aperçu/PDF — table `data.parametres` + petite page
- Dupliquer un devis ; export CSV
- Monter PostgREST en v16 (lire les « Migration to v13…v16 » du CHANGELOG)

## Pièges connus
- Docker Desktop doit être lancé (`open -a Docker`).
- Ne pas publier `postgrest`/`db` sur `0.0.0.0` : garder le préfixe `127.0.0.1:` dans `docker-compose.yml`.
- `.env` : la variable s'appelle `WEB_ANON_PASSWORD` (anciennement `AUTHENTICATOR_PASSWORD`).
