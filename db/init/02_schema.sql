-- Tables métier (schéma "data", jamais exposé directement par PostgREST)
CREATE SCHEMA data;

CREATE TABLE data.clients (
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nom        text NOT NULL CHECK (length(trim(nom)) > 0),
    email      text,
    telephone  text,
    adresse    text,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE data.devis (
    id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero         text NOT NULL UNIQUE,
    client_id      bigint NOT NULL REFERENCES data.clients(id) ON DELETE RESTRICT,
    date_devis     date NOT NULL DEFAULT current_date,
    validite_jours int  NOT NULL DEFAULT 30 CHECK (validite_jours > 0),
    statut         text NOT NULL DEFAULT 'brouillon'
                   CHECK (statut IN ('brouillon', 'envoye', 'accepte', 'refuse')),
    notes          text,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devis_client_idx ON data.devis (client_id);

CREATE TABLE data.devis_lignes (
    id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    devis_id      bigint NOT NULL REFERENCES data.devis(id) ON DELETE CASCADE,
    position      int NOT NULL,
    designation   text NOT NULL CHECK (length(trim(designation)) > 0),
    quantite      numeric(12,2) NOT NULL CHECK (quantite > 0),
    prix_unitaire numeric(12,2) NOT NULL CHECK (prix_unitaire >= 0),
    taux_tva      numeric(5,2)  NOT NULL DEFAULT 20 CHECK (taux_tva BETWEEN 0 AND 100)
);
CREATE INDEX devis_lignes_devis_idx ON data.devis_lignes (devis_id, position);

-- Numéro auto : DEV-AAAA-NNNN (compteur qui repart à 1 chaque année)
CREATE FUNCTION data.set_numero() RETURNS trigger LANGUAGE plpgsql AS $f$
DECLARE
    y text := to_char(NEW.date_devis, 'YYYY');
BEGIN
    IF NEW.numero IS NULL OR NEW.numero = '' THEN
        PERFORM pg_advisory_xact_lock(hashtext('devis_numero'));
        SELECT 'DEV-' || y || '-' || lpad((coalesce(max(substring(numero FROM '\d+$')::int), 0) + 1)::text, 4, '0')
          INTO NEW.numero
          FROM data.devis
         WHERE numero LIKE 'DEV-' || y || '-%';
    END IF;
    RETURN NEW;
END $f$;
CREATE TRIGGER devis_numero BEFORE INSERT ON data.devis
    FOR EACH ROW EXECUTE FUNCTION data.set_numero();

CREATE FUNCTION data.touch_updated_at() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN NEW.updated_at := now(); RETURN NEW; END $f$;
CREATE TRIGGER devis_touch BEFORE UPDATE ON data.devis
    FOR EACH ROW EXECUTE FUNCTION data.touch_updated_at();

-- Totaux calculés (jamais stockés => toujours cohérents), arrondi par ligne
CREATE VIEW data.v_devis_totaux AS
SELECT d.id AS devis_id,
       coalesce(sum(round(l.quantite * l.prix_unitaire, 2)), 0)                                  AS total_ht,
       coalesce(sum(round(l.quantite * l.prix_unitaire * l.taux_tva / 100, 2)), 0)               AS total_tva,
       coalesce(sum(round(l.quantite * l.prix_unitaire, 2)
                  + round(l.quantite * l.prix_unitaire * l.taux_tva / 100, 2)), 0)               AS total_ttc
  FROM data.devis d
  LEFT JOIN data.devis_lignes l ON l.devis_id = d.id
 GROUP BY d.id;
