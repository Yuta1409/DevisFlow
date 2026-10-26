-- Rôle de connexion de PostgREST. Pas d'authentification (pas de JWT) : toutes les requêtes
-- s'exécutent avec ce rôle, qui sert donc aussi de rôle anonyme (PGRST_DB_ANON_ROLE).
-- Ses seuls droits (USAGE sur api + EXECUTE sur ses fonctions) sont donnés à la fin de api.sql.
\getenv web_anon_password WEB_ANON_PASSWORD
CREATE ROLE web_anon LOGIN PASSWORD :'web_anon_password';
