include .env
export

PSQL = docker compose exec -T db psql -v ON_ERROR_STOP=1 -U $(POSTGRES_USER) -d $(POSTGRES_DB)

.PHONY: up down logs reset psql api seed backup restore open

up:            ## Démarre la stack (http://127.0.0.1:$(WEB_PORT))
	docker compose up -d

down:          ## Arrête la stack (données conservées)
	docker compose down

logs:
	docker compose logs -f --tail=50

reset:         ## ATTENTION : supprime le volume (toutes les données) et rejoue db/init.sql
	docker compose down -v
	docker compose up -d

psql:
	docker compose exec db psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

api:           ## Recrée les schémas util + api (code SQL) sans toucher aux données
	$(PSQL) --single-transaction -f /db/util.sql -f /db/api.sql

seed:          ## Données de démo
	$(PSQL) -f /db/seed_demo.sql

backup:        ## Sauvegarde dans backups/devis-AAAAMMJJ-HHMMSS.sql
	@mkdir -p backups
	docker compose exec -T db pg_dump -U $(POSTGRES_USER) -d $(POSTGRES_DB) --schema=data > backups/devis-$$(date +%Y%m%d-%H%M%S).sql
	@ls -1t backups | head -1

restore:       ## make restore FILE=backups/xxx.sql (schéma data vidé puis rechargé)
	@test -n "$(FILE)" || (echo "Usage: make restore FILE=backups/xxx.sql" && exit 1)
	$(PSQL) -c "DROP SCHEMA data CASCADE;"
	$(PSQL) < $(FILE)
	$(MAKE) api

open:
	open http://127.0.0.1:$(WEB_PORT)
