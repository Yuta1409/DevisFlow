-- Données de démonstration (facultatif) : `make seed`
INSERT INTO data.clients (nom, email, telephone, adresse) VALUES
    ('Boulangerie Martin', 'contact@boulangerie-martin.fr', '01 23 45 67 89', '12 rue du Pain, 75011 Paris'),
    ('Studio Lumière', 'hello@studio-lumiere.fr', NULL, NULL);

WITH d AS (
    INSERT INTO data.devis (client_id, statut, notes)
    SELECT id, 'envoye', 'Paiement à 30 jours.' FROM data.clients WHERE nom = 'Boulangerie Martin'
    RETURNING id
)
INSERT INTO data.devis_lignes (devis_id, position, designation, quantite, prix_unitaire, taux_tva)
SELECT d.id, v.p, v.des, v.q, v.pu, v.tva FROM d,
    (VALUES (1, 'Création de site vitrine', 1, 1200.00, 20), (2, 'Hébergement (12 mois)', 12, 9.90, 20)) AS v(p, des, q, pu, tva);
