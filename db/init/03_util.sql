-- Helpers HTML (schéma "util", non exposé par PostgREST). Idempotent : rejouable via `make api`.
CREATE SCHEMA IF NOT EXISTS util;

-- Échappement HTML : À UTILISER pour toute valeur venant de la base / de l'utilisateur
CREATE OR REPLACE FUNCTION util.esc(t text) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT replace(replace(replace(replace(replace(coalesce(t, ''),
           '&', '&amp;'), '<', '&lt;'), '>', '&gt;'), '"', '&quot;'), '''', '&#39;')
$f$;

-- 1234.5 -> "1 234,50 €" (espace insécable)
CREATE OR REPLACE FUNCTION util.money(n numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT regexp_replace(to_char(trunc(r), 'FM999999999990'), '(\d)(?=(\d{3})+$)', '\1' || chr(160), 'g')
           || ',' || to_char(round((r - trunc(r)) * 100), 'FM00') || chr(160) || '€'
      FROM (SELECT round(abs(coalesce(n, 0)), 2) AS r) s
$f$;

CREATE OR REPLACE FUNCTION util.fdate(d date) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT to_char(d, 'DD/MM/YYYY')
$f$;

-- json-enc envoie une valeur seule (string) quand il n'y a qu'une ligne : on force un tableau
CREATE OR REPLACE FUNCTION util.as_arr(j jsonb) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE coalesce(jsonb_typeof(j), 'null')
             WHEN 'array' THEN j
             WHEN 'null'  THEN '[]'::jsonb
             ELSE jsonb_build_array(j)
           END
$f$;

-- "12,5" ou "12.5" -> 12.5 ; vide -> défaut
CREATE OR REPLACE FUNCTION util.num(t text, def numeric DEFAULT 0) RETURNS numeric LANGUAGE sql IMMUTABLE AS $f$
    SELECT coalesce(nullif(replace(trim(t), ',', '.'), '')::numeric, def)
$f$;

CREATE OR REPLACE FUNCTION util.statut_label(s text) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT CASE s WHEN 'brouillon' THEN 'Brouillon' WHEN 'envoye' THEN 'Envoyé'
                  WHEN 'accepte' THEN 'Accepté' WHEN 'refuse' THEN 'Refusé' ELSE s END
$f$;

CREATE OR REPLACE FUNCTION util.badge(s text) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT format('<span class="badge s-%s">%s</span>', s, util.statut_label(s))
$f$;

-- <select> de changement de statut inline (renvoie lui-même après mise à jour)
CREATE OR REPLACE FUNCTION util.statut_select(p_id bigint, p_statut text) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT format($h$<select class="statut s-%1$s" name="p_statut" hx-post="/api/rpc/changer_statut" hx-vals='{"p_id": %2$s}' hx-target="this" hx-swap="outerHTML" aria-label="Statut">%3$s</select>$h$,
        p_statut, p_id,
        (SELECT string_agg(format('<option value="%1$s"%2$s>%3$s</option>',
                    s, CASE WHEN s = p_statut THEN ' selected' END, util.statut_label(s)), '' ORDER BY o)
           FROM unnest(ARRAY['brouillon', 'envoye', 'accepte', 'refuse']) WITH ORDINALITY AS t(s, o)))
$f$;

-- Une ligne du formulaire de devis
CREATE OR REPLACE FUNCTION util.ligne(d text, q numeric, pu numeric, tva numeric) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
    SELECT format($h$<tr class="ligne">
  <td><input name="ligne_designation" value="%1$s" placeholder="Désignation" required></td>
  <td><input class="num" name="ligne_quantite" type="number" step="0.01" min="0.01" value="%2$s" required></td>
  <td><input class="num" name="ligne_prix" type="number" step="0.01" min="0" value="%3$s" placeholder="0,00" required></td>
  <td><select name="ligne_tva" aria-label="TVA">%4$s</select></td>
  <td class="num ligne-total">%5$s</td>
  <td><button type="button" class="icon" title="Supprimer la ligne" onclick="supprimerLigne(this)">✕</button></td>
</tr>$h$,
        util.esc(d),
        coalesce(trim_scale(q)::text, '1'),
        coalesce(trim_scale(pu)::text, ''),
        (SELECT string_agg(format('<option value="%1$s"%2$s>%1$s %%</option>', v, CASE WHEN v = tva THEN ' selected' END), '' ORDER BY v)
           FROM unnest(ARRAY[0, 2.1, 5.5, 10, 20]::numeric[]) AS v),
        util.money(round(coalesce(q, 0) * coalesce(pu, 0), 2)))
$f$;

-- Tableau de la liste des devis, filtré
CREATE OR REPLACE FUNCTION util.table_devis(p_q text, p_statut text) RETURNS text LANGUAGE plpgsql STABLE AS $f$
DECLARE
    v_rows text;
BEGIN
    SELECT string_agg(format($h$<tr>
  <td><a href="#" hx-get="/api/rpc/apercu_devis?p_id=%1$s" hx-target="#main"><strong>%2$s</strong></a></td>
  <td>%3$s</td>
  <td>%4$s</td>
  <td class="num">%5$s</td>
  <td>%6$s</td>
  <td class="actions">
    <button class="ghost" hx-get="/api/rpc/apercu_devis?p_id=%1$s" hx-target="#main">Voir</button>
    <button class="ghost" hx-get="/api/rpc/form_devis?p_id=%1$s" hx-target="#main">Modifier</button>
    <button class="ghost danger" hx-post="/api/rpc/supprimer_devis" hx-vals='{"p_id": %1$s}' hx-confirm="Supprimer le devis %2$s ?" hx-target="closest tr" hx-swap="outerHTML">Supprimer</button>
  </td>
</tr>$h$,
        d.id, util.esc(d.numero), util.esc(c.nom), util.fdate(d.date_devis),
        util.money(t.total_ttc), util.statut_select(d.id, d.statut)),
        '' ORDER BY d.date_devis DESC, d.id DESC)
      INTO v_rows
      FROM data.devis d
      JOIN data.clients c ON c.id = d.client_id
      JOIN data.v_devis_totaux t ON t.devis_id = d.id
     WHERE (coalesce(p_statut, '') = '' OR d.statut = p_statut)
       AND (coalesce(trim(p_q), '') = ''
            OR d.numero ILIKE '%' || trim(p_q) || '%'
            OR c.nom    ILIKE '%' || trim(p_q) || '%');

    RETURN '<table class="tbl"><thead><tr><th>N°</th><th>Client</th><th>Date</th><th class="num">Total TTC</th><th>Statut</th><th></th></tr></thead><tbody>'
        || coalesce(v_rows, '<tr><td colspan="6" class="empty">Aucun devis.</td></tr>')
        || '</tbody></table>';
END $f$;

REVOKE ALL ON SCHEMA util FROM PUBLIC;
