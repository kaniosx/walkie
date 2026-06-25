.DEFAULT_GOAL := help
.PHONY: help start reset install-hooks

help: ## Show available commands (default)
	@awk 'BEGIN {FS = ":.*?## "; printf "\nUsage: make <target>\n\nAvailable commands:\n"} \
	     /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: ## Start the project in Docker (web + db)
	docker compose up

install-hooks: ## Wire .githooks/ as git hooks directory (run once per clone)
	git config core.hooksPath .githooks
	@echo "✔ Git hooks installed (.githooks/pre-commit active)"

reset: ## Stop stack, remove volumes and rebuild image from scratch
	@echo "This will delete volumes (pg_data, bundle_cache) and rebuild the image."
	@read -p "Continue? [y/N] " ans && [ "$$ans" = "y" ] || { echo "cancelled"; exit 1; }
	docker compose down -v
	docker compose build --no-cache
	docker compose up
