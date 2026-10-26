-- Initialisation de la base : exécuté par Postgres UNIQUEMENT au 1er démarrage (volume vide).
-- L'ordre d'exécution est défini ici. Le dossier db/ est monté dans le conteneur sur /db.
\i /db/roles.sql
\i /db/tables.sql
\i /db/util.sql
\i /db/api.sql
