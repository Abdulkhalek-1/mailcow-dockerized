.PHONY: help setup up down restart logs logs-mail logs-cert status clean validate pull deploy update backup

help: ## Show this help message
	@echo "Mailcow Mail Server Management"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

setup: ## Initial setup: generate config and create SSL certs
	@if [ ! -L .env ]; then \
		ln -sf mailcow.conf .env; \
		echo "==> Created .env symlink."; \
	fi
	@if [ ! -f mailcow.conf ]; then \
		echo "==> Running generate_config.sh..."; \
		./generate_config.sh; \
	else \
		echo "==> mailcow.conf already exists. Skipping generation."; \
	fi
	@echo ""
	@echo "Setup complete! Next steps:"
	@echo "  1. Verify mailcow.conf settings"
	@echo "  2. Run: make up"

up: ## Start all mailcow services
	docker compose up -d

down: ## Stop all services
	docker compose down

restart: ## Restart all services
	docker compose restart

logs: ## Show all logs (follow mode)
	docker compose logs -f

logs-mail: ## Show postfix and dovecot logs
	docker compose logs -f postfix-mailcow dovecot-mailcow

logs-cert: ## Show certificate dumper logs
	docker logs -f certdumper-mailcow

status: ## Show container status and cert info
	@echo "==> Mailcow container status:"
	@docker compose ps
	@echo ""
	@echo "==> Certificate status:"
	@ls -la data/assets/ssl/cert.pem data/assets/ssl/key.pem 2>/dev/null || echo "    No certificates found!"
	@echo ""
	@echo "==> Containers on 'gateway' network:"
	@docker network inspect gateway --format '{{range .Containers}}  {{.Name}} ({{.IPv4Address}}){{"\n"}}{{end}}' 2>/dev/null || echo "    Network not found."

clean: ## Remove containers (keeps data volumes)
	docker compose down --remove-orphans

validate: ## Validate compose config
	@echo "==> Validating docker-compose config..."
	@docker compose config --quiet && echo "    OK" || (echo "    FAIL" && exit 1)

pull: ## Pull latest images
	docker compose pull

deploy: ## Pull latest code, validate, and restart (used by CI/CD)
	@echo "==> Pulling latest changes from origin/main..."
	@git fetch origin main
	@git reset --hard origin/main
	@echo "==> Ensuring gateway network exists..."
	@docker network create gateway 2>/dev/null || true
	@echo "==> Validating config..."
	@docker compose config --quiet
	@echo "==> Pulling images..."
	@docker compose pull
	@echo "==> Restarting services..."
	@docker compose up -d --remove-orphans
	@echo "==> Deploy complete."

update: ## Run mailcow upstream update script
	./update.sh

backup: ## Backup mailcow data
	@echo "==> Creating backup..."
	@./helper-scripts/backup_and_restore.sh backup all
	@echo "==> Backup complete."
