-- API exposée par PostgREST (schéma "api") : uniquement des fonctions RPC qui renvoient du HTML.
-- SECURITY DEFINER : web_anon n'a AUCUN accès direct aux tables, seulement EXECUTE sur ces fonctions.
-- Idempotent : rejouable via `make api`.
CREATE SCHEMA IF NOT EXISTS api;

-- Media type handler PostgREST : une fonction qui renvoie ce domaine répond en Content-Type text/html
DO $do$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
                    WHERE n.nspname = 'api' AND t.typname = 'text/html') THEN
        CREATE DOMAIN api."text/html" AS text;
    END IF;
END $do$;

-------------------------------------------------------------------------------
-- Liste des devis
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.liste_devis(q text DEFAULT '', statut text DEFAULT '')
RETURNS api."text/html" LANGUAGE sql STABLE SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
    SELECT util.table_devis(q, statut)::api."text/html"
$f$;

CREATE OR REPLACE FUNCTION api.page_devis()
RETURNS api."text/html" LANGUAGE sql STABLE SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
    SELECT (
$h$<section>
  <div class="head">
    <h2>Devis</h2>
    <button class="primary" hx-get="/api/rpc/form_devis" hx-target="#main">+ Nouveau devis</button>
  </div>
  <form id="filtres" class="filters" onsubmit="return false"
        hx-get="/api/rpc/liste_devis" hx-trigger="input delay:300ms, change" hx-target="#liste">
    <input type="search" name="q" placeholder="Rechercher (n° ou client)…" autocomplete="off">
    <select name="statut" aria-label="Filtrer par statut">
      <option value="">Tous les statuts</option>
      <option value="brouillon">Brouillon</option>
      <option value="envoye">Envoyé</option>
      <option value="accepte">Accepté</option>
      <option value="refuse">Refusé</option>
    </select>
  </form>
  <div id="liste">$h$ || util.table_devis('', '') || '</div></section>'
    )::api."text/html"
$f$;

-------------------------------------------------------------------------------
-- Formulaire de devis (création si p_id NULL, sinon édition)
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.ligne_vide()
RETURNS api."text/html" LANGUAGE sql STABLE SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
    SELECT util.ligne('', 1, NULL, 20)::api."text/html"
$f$;

CREATE OR REPLACE FUNCTION api.form_devis(p_id bigint DEFAULT NULL)
RETURNS api."text/html" LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
DECLARE
    d         data.devis;
    v_clients text;
    v_lignes  text;
    v_statuts text;
BEGIN
    IF p_id IS NOT NULL THEN
        SELECT * INTO d FROM data.devis WHERE id = p_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Devis introuvable'; END IF;
    END IF;
    d.date_devis     := coalesce(d.date_devis, current_date);
    d.validite_jours := coalesce(d.validite_jours, 30);
    d.statut         := coalesce(d.statut, 'brouillon');

    SELECT coalesce(string_agg(format('<option value="%s"%s>%s</option>', c.id,
                    CASE WHEN c.id = d.client_id THEN ' selected' END, util.esc(c.nom)), '' ORDER BY lower(c.nom)), '')
      INTO v_clients FROM data.clients c;

    IF p_id IS NULL THEN
        v_lignes := util.ligne('', 1, NULL, 20);
    ELSE
        SELECT string_agg(util.ligne(l.designation, l.quantite, l.prix_unitaire, l.taux_tva), '' ORDER BY l.position)
          INTO v_lignes FROM data.devis_lignes l WHERE l.devis_id = p_id;
    END IF;

    SELECT string_agg(format('<option value="%1$s"%2$s>%3$s</option>', s,
                    CASE WHEN s = d.statut THEN ' selected' END, util.statut_label(s)), '' ORDER BY o)
      INTO v_statuts FROM unnest(ARRAY['brouillon', 'envoye', 'accepte', 'refuse']) WITH ORDINALITY AS t(s, o);

    RETURN format($h$<section>
  <div class="head"><h2>%1$s</h2></div>
  <form id="devis-form" class="card" hx-post="/api/rpc/enregistrer_devis" hx-target="#main"
        hx-headers='{"Prefer": "params=single-object"}'>
    <input type="hidden" name="id" value="%2$s">
    <div class="grid">
      <label>Client
        <select name="client_id"><option value="">— Choisir un client —</option>%3$s</select>
      </label>
      <label>… ou nouveau client
        <input name="nouveau_client_nom" placeholder="Nom du client" autocomplete="off">
      </label>
      <label>E-mail (nouveau client)
        <input name="nouveau_client_email" type="email" placeholder="facultatif" autocomplete="off">
      </label>
      <label>Téléphone (nouveau client)
        <input name="nouveau_client_tel" placeholder="facultatif" autocomplete="off">
      </label>
    </div>
    <div class="grid">
      <label>Date <input type="date" name="date_devis" value="%4$s" required></label>
      <label>Validité (jours) <input type="number" name="validite_jours" min="1" value="%5$s" required></label>
      <label>Statut <select name="statut">%6$s</select></label>
    </div>

    <table class="tbl lignes">
      <thead><tr><th>Désignation</th><th class="num">Qté</th><th class="num">PU HT</th><th>TVA</th><th class="num">Total HT</th><th></th></tr></thead>
      <tbody id="lignes">%7$s</tbody>
    </table>
    <button type="button" class="ghost" hx-get="/api/rpc/ligne_vide" hx-target="#lignes" hx-swap="beforeend">+ Ajouter une ligne</button>

    <dl class="totaux">
      <dt>Total HT</dt><dd id="t-ht">0,00 €</dd>
      <dt>TVA</dt><dd id="t-tva">0,00 €</dd>
      <dt>Total TTC</dt><dd id="t-ttc" class="ttc">0,00 €</dd>
    </dl>

    <label>Notes / conditions
      <textarea name="notes" rows="3" placeholder="Conditions de paiement, remarques…">%8$s</textarea>
    </label>

    <div class="row">
      <button class="primary" type="submit">Enregistrer le devis</button>
      <button class="ghost" type="button" hx-get="/api/rpc/page_devis" hx-target="#main">Annuler</button>
    </div>
  </form>
</section>$h$,
        CASE WHEN p_id IS NULL THEN 'Nouveau devis' ELSE 'Modifier ' || util.esc(d.numero) END,
        coalesce(p_id::text, ''),
        v_clients,
        d.date_devis, d.validite_jours, v_statuts, v_lignes,
        util.esc(d.notes))::api."text/html";
END $f$;

-------------------------------------------------------------------------------
-- Enregistrement (création / mise à jour) : corps JSON unique (Prefer: params=single-object)
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.enregistrer_devis(payload jsonb)
RETURNS api."text/html" LANGUAGE plpgsql SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
DECLARE
    v_id     bigint := nullif(payload->>'id', '')::bigint;
    v_client bigint := nullif(payload->>'client_id', '')::bigint;
    v_des    jsonb  := util.as_arr(payload->'ligne_designation');
    v_qte    jsonb  := util.as_arr(payload->'ligne_quantite');
    v_prix   jsonb  := util.as_arr(payload->'ligne_prix');
    v_tva    jsonb  := util.as_arr(payload->'ligne_tva');
    v_date   date   := coalesce(nullif(payload->>'date_devis', '')::date, current_date);
    v_valid  int    := coalesce(nullif(payload->>'validite_jours', '')::int, 30);
    v_statut text   := coalesce(nullif(payload->>'statut', ''), 'brouillon');
    v_notes  text   := nullif(trim(payload->>'notes'), '');
    v_pos    int    := 0;
    i        int;
BEGIN
    IF nullif(trim(payload->>'nouveau_client_nom'), '') IS NOT NULL THEN
        INSERT INTO data.clients (nom, email, telephone)
        VALUES (trim(payload->>'nouveau_client_nom'),
                nullif(trim(payload->>'nouveau_client_email'), ''),
                nullif(trim(payload->>'nouveau_client_tel'), ''))
        RETURNING id INTO v_client;
    END IF;
    IF v_client IS NULL THEN
        RAISE EXCEPTION 'Choisissez un client ou saisissez un nouveau client.';
    END IF;

    IF v_id IS NULL THEN
        INSERT INTO data.devis (client_id, date_devis, validite_jours, statut, notes)
        VALUES (v_client, v_date, v_valid, v_statut, v_notes)
        RETURNING id INTO v_id;
    ELSE
        UPDATE data.devis
           SET client_id = v_client, date_devis = v_date, validite_jours = v_valid,
               statut = v_statut, notes = v_notes
         WHERE id = v_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Devis introuvable'; END IF;
        DELETE FROM data.devis_lignes WHERE devis_id = v_id;
    END IF;

    FOR i IN 0 .. jsonb_array_length(v_des) - 1 LOOP
        CONTINUE WHEN nullif(trim(v_des->>i), '') IS NULL;
        v_pos := v_pos + 1;
        INSERT INTO data.devis_lignes (devis_id, position, designation, quantite, prix_unitaire, taux_tva)
        VALUES (v_id, v_pos, trim(v_des->>i),
                util.num(v_qte->>i, 1), util.num(v_prix->>i, 0), util.num(v_tva->>i, 20));
    END LOOP;
    IF v_pos = 0 THEN
        RAISE EXCEPTION 'Ajoutez au moins une ligne avec une désignation.';
    END IF;

    RETURN api.apercu_devis(v_id);
END $f$;

-------------------------------------------------------------------------------
-- Aperçu imprimable (Imprimer -> Enregistrer en PDF)
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.apercu_devis(p_id bigint)
RETURNS api."text/html" LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
DECLARE
    d       record;
    v_lines text;
BEGIN
    SELECT dv.*, c.nom, c.email, c.telephone, c.adresse, t.total_ht, t.total_tva, t.total_ttc
      INTO d
      FROM data.devis dv
      JOIN data.clients c ON c.id = dv.client_id
      JOIN data.v_devis_totaux t ON t.devis_id = dv.id
     WHERE dv.id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Devis introuvable'; END IF;

    SELECT string_agg(format('<tr><td>%s</td><td class="num">%s</td><td class="num">%s</td><td class="num">%s %%</td><td class="num">%s</td></tr>',
                util.esc(l.designation), trim_scale(l.quantite), util.money(l.prix_unitaire),
                trim_scale(l.taux_tva), util.money(round(l.quantite * l.prix_unitaire, 2))), '' ORDER BY l.position)
      INTO v_lines FROM data.devis_lignes l WHERE l.devis_id = p_id;

    RETURN format($h$<section>
  <div class="head no-print">
    <button class="ghost" hx-get="/api/rpc/page_devis" hx-target="#main">← Liste</button>
    <span class="spacer"></span>
    <button class="ghost" hx-get="/api/rpc/form_devis?p_id=%1$s" hx-target="#main">Modifier</button>
    <button class="primary" onclick="window.print()">Imprimer / PDF</button>
  </div>
  <article class="doc card">
    <header class="doc-head">
      <div><h1>Devis</h1><p class="muted">N° %2$s</p></div>
      <div class="doc-meta">%3$s<br>Date : %4$s<br>Valable jusqu'au : %5$s</div>
    </header>
    <div class="doc-client"><strong>%6$s</strong><br>%7$s</div>
    <table class="tbl">
      <thead><tr><th>Désignation</th><th class="num">Qté</th><th class="num">PU HT</th><th class="num">TVA</th><th class="num">Total HT</th></tr></thead>
      <tbody>%8$s</tbody>
    </table>
    <dl class="totaux">
      <dt>Total HT</dt><dd>%9$s</dd>
      <dt>TVA</dt><dd>%10$s</dd>
      <dt>Total TTC</dt><dd class="ttc">%11$s</dd>
    </dl>
    <p class="notes">%12$s</p>
  </article>
</section>$h$,
        d.id, util.esc(d.numero), util.badge(d.statut), util.fdate(d.date_devis),
        util.fdate(d.date_devis + d.validite_jours),
        util.esc(d.nom),
        concat_ws('<br>', nullif(replace(util.esc(d.adresse), E'\n', '<br>'), ''), nullif(util.esc(d.email), ''), nullif(util.esc(d.telephone), '')),
        v_lines,
        util.money(d.total_ht), util.money(d.total_tva), util.money(d.total_ttc),
        replace(util.esc(d.notes), E'\n', '<br>'))::api."text/html";
END $f$;

-------------------------------------------------------------------------------
-- Statut / suppression
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.changer_statut(p_id bigint, p_statut text)
RETURNS api."text/html" LANGUAGE plpgsql SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
BEGIN
    IF p_statut NOT IN ('brouillon', 'envoye', 'accepte', 'refuse') THEN
        RAISE EXCEPTION 'Statut invalide';
    END IF;
    UPDATE data.devis SET statut = p_statut WHERE id = p_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Devis introuvable'; END IF;
    RETURN util.statut_select(p_id, p_statut)::api."text/html";
END $f$;

CREATE OR REPLACE FUNCTION api.supprimer_devis(p_id bigint)
RETURNS api."text/html" LANGUAGE plpgsql SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
BEGIN
    DELETE FROM data.devis WHERE id = p_id;
    RETURN ''::api."text/html";
END $f$;

-------------------------------------------------------------------------------
-- Clients
-------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION api.page_clients()
RETURNS api."text/html" LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
DECLARE
    v_rows text;
BEGIN
    SELECT string_agg(format($h$<tr>
  <td><strong>%2$s</strong></td><td>%3$s</td><td>%4$s</td><td class="num">%5$s</td>
  <td class="actions"><button class="ghost danger" hx-post="/api/rpc/supprimer_client" hx-vals='{"p_id": %1$s}'
      hx-confirm="Supprimer le client %2$s ?" hx-target="closest tr" hx-swap="outerHTML">Supprimer</button></td>
</tr>$h$, c.id, util.esc(c.nom), util.esc(c.email), util.esc(c.telephone),
        (SELECT count(*) FROM data.devis d WHERE d.client_id = c.id)), '' ORDER BY lower(c.nom))
      INTO v_rows FROM data.clients c;

    RETURN ($h$<section>
  <div class="head"><h2>Clients</h2></div>
  <form class="card grid" hx-post="/api/rpc/enregistrer_client" hx-target="#main">
    <label>Nom <input name="nom" required autocomplete="off"></label>
    <label>E-mail <input name="email" type="email" autocomplete="off"></label>
    <label>Téléphone <input name="telephone" autocomplete="off"></label>
    <label>Adresse <input name="adresse" autocomplete="off"></label>
    <div class="row"><button class="primary" type="submit">Ajouter le client</button></div>
  </form>
  <table class="tbl">
    <thead><tr><th>Nom</th><th>E-mail</th><th>Téléphone</th><th class="num">Devis</th><th></th></tr></thead>
    <tbody>$h$ || coalesce(v_rows, '<tr><td colspan="5" class="empty">Aucun client.</td></tr>') || '</tbody></table></section>')::api."text/html";
END $f$;

CREATE OR REPLACE FUNCTION api.enregistrer_client(nom text, email text DEFAULT '', telephone text DEFAULT '', adresse text DEFAULT '')
RETURNS api."text/html" LANGUAGE plpgsql SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
BEGIN
    IF nullif(trim(nom), '') IS NULL THEN RAISE EXCEPTION 'Le nom est obligatoire.'; END IF;
    INSERT INTO data.clients (nom, email, telephone, adresse)
    VALUES (trim(nom), nullif(trim(email), ''), nullif(trim(telephone), ''), nullif(trim(adresse), ''));
    RETURN api.page_clients();
END $f$;

CREATE OR REPLACE FUNCTION api.supprimer_client(p_id bigint)
RETURNS api."text/html" LANGUAGE plpgsql SECURITY DEFINER SET search_path = data, util, api, pg_temp AS $f$
BEGIN
    IF EXISTS (SELECT 1 FROM data.devis WHERE client_id = p_id) THEN
        RAISE EXCEPTION 'Ce client a des devis : supprimez-les d''abord.';
    END IF;
    DELETE FROM data.clients WHERE id = p_id;
    RETURN ''::api."text/html";
END $f$;

-------------------------------------------------------------------------------
-- Droits : web_anon n'a QUE l'usage du schéma api + EXECUTE sur ses fonctions
-------------------------------------------------------------------------------
REVOKE ALL ON SCHEMA data FROM PUBLIC;
GRANT USAGE ON SCHEMA api TO web_anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA api TO web_anon;

NOTIFY pgrst, 'reload schema';
