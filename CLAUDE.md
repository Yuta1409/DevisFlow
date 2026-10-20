# Devis — app locale PostgREST + htmx + PostgreSQL

Outil personnel de saisie de devis (quelques minutes par devis), historique complet en base.
**100 % local** : tout est lié à `127.0.0.1`, aucune authentification (volontaire).

## Démarrage
```
make up        # http://127.0.0.1:8080  (Docker Desktop doit tourner)
make open      # ouvre le navigateur
make seed      # (option) données de démo
make down      # arrête, données conservées
```
Autres : `make logs`, `make psql`, `make api` (rejoue util+api sans perdre les données),
`make backup` / `make restore FILE=backups/x.sql`, `make reset` (**efface tout**).
Config : `.env` (gitignoré, modèle `.env.example`). Postgres accessible sur `127.0.0.1:5433`.

## Architecture
```
navigateur → nginx :8080 ─ /      → web/ (htmx vendorisé, css, js)
                         └ /api/* → PostgREST :3000 (non publié) → PostgreSQL 16 (volume devis_pgdata)
```
- **Schémas SQL** : `data` (tables, jamais exposé) · `util` (helpers HTML, non exposé) · `api` (seul schéma exposé).
- `web_anon` (rôle PostgREST) n'a **que** `USAGE` sur `api` + `EXECUTE` sur ses fonctions.
  Les fonctions `api.*` sont `SECURITY DEFINER` avec `search_path` fixé.
- **htmx ↔ PostgREST** : les fonctions RPC renvoient du HTML (domaine `api."text/html"` = media type handler PostgREST).
  Le body porte `hx-headers='{"Accept":"text/html"}'` et `hx-ext="json-enc"` (POST en JSON, clés = noms des paramètres).
- `enregistrer_devis(payload jsonb)` reçoit tout le formulaire (`Prefer: params=single-object`) ; les champs
  répétés (lignes) arrivent en tableau, ou en simple chaîne s'il n'y a qu'une ligne → `util.as_arr()`.

## Fichiers
| Fichier | Rôle |
|---|---|
| `db/init/01_roles.sh` | rôles `authenticator` / `web_anon` (mot de passe via `.env`) |
| `db/init/02_schema.sql` | tables, numérotation `DEV-AAAA-NNNN`, trigger `updated_at`, vue des totaux |
| `db/init/03_util.sql` | helpers HTML (`esc`, `money`, `ligne`, `table_devis`…) — idempotent |
| `db/init/04_api.sql` | fonctions RPC exposées + droits — idempotent |
| `db/seed_demo.sql` | données de démo (`make seed`) |
| `web/` | `index.html`, `css/app.css`, `js/app.js` (totaux en direct, toasts), `js/htmx.min.js` 2.0.4, `js/json-enc.js` |

## Conventions (à respecter)
- **Toute valeur issue de la base/utilisateur passe par `util.esc()`** avant d'être mise dans du HTML (anti-XSS).
- Fonctions de lecture : `STABLE` (PostgREST les appelle en GET) ; écritures : volatiles, appelées en POST.
- Erreurs métier : `RAISE EXCEPTION 'message lisible'` → affiché en toast (`htmx:responseError`).
- Totaux jamais stockés : calculés dans `data.v_devis_totaux` (arrondi par ligne, identique dans `recalc()` de `app.js`).
- Modif SQL sur base existante : éditer `03_util.sql`/`04_api.sql` puis `make api`. Changer une signature
  de fonction ⇒ `DROP FUNCTION` d'abord. Changer `02_schema.sql` ⇒ `make backup` puis `make reset` (les scripts
  d'init ne rejouent que sur volume vide).

## Suivi
- [x] Phase 1 — Fondations : docker-compose, rôles, schéma, nginx
- [x] Phase 2 — Clients + devis : tables, RPC HTML (testées en curl : création 1/3 lignes, XSS échappé, statut, erreurs)
- [x] Phase 3 — Front htmx : liste + recherche/filtre, formulaire à lignes dynamiques, édition, statut inline, suppression
- [x] Phase 4 — Aperçu imprimable (`window.print()` → PDF), totaux en direct
- [x] Phase 5 — `make backup` / `restore` testés, persistance après redémarrage vérifiée, `seed_demo.sql`
- [ ] Vérification visuelle complète dans le navigateur (à faire par l'utilisateur : `make open`)

## Idées futures (non faites)
- Modifier un client existant (aujourd'hui : ajout/suppression seulement)
- Bloc « émetteur » (nom, adresse, SIRET, mentions légales) sur l'aperçu/PDF — table `data.parametres` + petite page
- Dupliquer un devis ; export CSV

## Pièges connus
- Docker Desktop doit être lancé (`open -a Docker`).
- Le dossier parent de ce projet est un dépôt git (home) : aucun commit n'a été fait ; `git init` ici si on veut un dépôt propre.
- Ne pas publier `postgrest`/`db` sur `0.0.0.0` : garder le préfixe `127.0.0.1:` dans `docker-compose.yml`.
