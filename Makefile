# Jekyll Development Makefile for Docker
# Usage: make <target>

.PHONY: help install build serve stop clean restart logs shell bundle-install bundle-update new-post deploy status

# Default target
help: ## Show this help message
	@echo "Jekyll Development Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Development Commands
install: ## Install dependencies and build container
	@echo "� Installing dependencies..."
	docker-compose build --no-cache
	docker-compose run --rm jekyll bundle install
	@echo "✅ Installation complete!"

build: ## Build the Jekyll site
	@echo "�️  Building Jekyll site..."
	docker-compose run --rm jekyll bundle exec jekyll build
	@echo "✅ Build complete!"

serve: ## Start the development server
	@echo "� Starting Jekyll development server..."
	@echo "� Site will be available at: http://localhost:4000"
	@echo "� LiveReload available at: http://localhost:35729"
	docker-compose up

stop: ## Stop the development server
	@echo "� Stopping Jekyll development server..."
	docker-compose down

restart: ## Restart the development server (useful after config changes)
	@echo "� Restarting Jekyll development server..."
	docker-compose down
	docker-compose up

clean: ## Clean up build artifacts and caches
	@echo "� Cleaning up..."
	docker-compose down
	docker-compose run --rm jekyll bundle exec jekyll clean
	rm -rf .jekyll-cache _site
	@echo "✅ Cleanup complete!"

# Dependency Management
bundle-install: ## Install/update gems
	@echo "� Installing gems..."
	docker-compose run --rm jekyll bundle install
	@echo "✅ Gems installed!"

bundle-update: ## Update all gems
	@echo "⬆️  Updating gems..."
	docker-compose run --rm jekyll bundle update
	@echo "✅ Gems updated!"

bundle-add: ## Add a new gem (usage: make bundle-add GEM=gem-name)
	@if [ -z "$(GEM)" ]; then \
		echo "❌ Please specify a gem: make bundle-add GEM=gem-name"; \
		exit 1; \
	fi
	@echo "� Adding gem: $(GEM)"
	docker-compose run --rm jekyll bundle add $(GEM)
	@echo "✅ Gem $(GEM) added!"

# Content Management
new-post: ## Create a new blog post (usage: make new-post TITLE="Post Title")
	@if [ -z "$(TITLE)" ]; then \
		echo "❌ Please specify a title: make new-post TITLE=\"Your Post Title\""; \
		exit 1; \
	fi
	@DATE=$$(date +%Y-%m-%d); \
	SLUG=$$(echo "$(TITLE)" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | sed 's/[^a-z0-9-]//g'); \
	FILENAME="_posts/$$DATE-$$SLUG.md"; \
	echo "� Creating new post: $$FILENAME"; \
	mkdir -p _posts; \
	echo "---" > $$FILENAME; \
	echo "layout: post" >> $$FILENAME; \
	echo "title: \"$(TITLE)\"" >> $$FILENAME; \
	echo "date: $$(date '+%Y-%m-%d %H:%M:%S %z')" >> $$FILENAME; \
	echo "categories: []" >> $$FILENAME; \
	echo "tags: []" >> $$FILENAME; \
	echo "---" >> $$FILENAME; \
	echo "" >> $$FILENAME; \
	echo "Your post content goes here..." >> $$FILENAME; \
	echo "✅ Post created: $$FILENAME"

new-page: ## Create a new page (usage: make new-page TITLE="Page Title" PERMALINK="/page-url/")
	@if [ -z "$(TITLE)" ]; then \
		echo "❌ Please specify a title: make new-page TITLE=\"Your Page Title\""; \
		exit 1; \
	fi
	@if [ -z "$(PERMALINK)" ]; then \
		echo "❌ Please specify a permalink: make new-page TITLE=\"Your Page Title\" PERMALINK=\"/page-url/\""; \
		exit 1; \
	fi
	@SLUG=$$(echo "$(TITLE)" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | sed 's/[^a-z0-9-]//g'); \
	FILENAME="$$SLUG.md"; \
	echo "� Creating new page: $$FILENAME"; \
	echo "---" > $$FILENAME; \
	echo "layout: page" >> $$FILENAME; \
	echo "title: \"$(TITLE)\"" >> $$FILENAME; \
	echo "permalink: $(PERMALINK)" >> $$FILENAME; \
	echo "---" >> $$FILENAME; \
	echo "" >> $$FILENAME; \
	echo "Your page content goes here..." >> $$FILENAME; \
	echo "✅ Page created: $$FILENAME"

# Debugging and Maintenance
logs: ## Show Jekyll server logs
	docker-compose logs -f jekyll

shell: ## Open a shell in the Jekyll container
	@echo "� Opening shell in Jekyll container..."
	docker-compose run --rm jekyll sh

status: ## Show container status
	@echo "� Container Status:"
	docker-compose ps

# Production/Deployment
deploy-build: ## Build for production (GitHub Pages)
	@echo "� Building for production..."
	JEKYLL_ENV=production docker-compose run --rm jekyll bundle exec jekyll build
	@echo "✅ Production build complete!"

# Setup and Reset
fresh-start: ## Complete fresh start (removes everything)
	@echo "⚠️  This will remove all containers, images, and volumes. Continue? [y/N]" && read ans && [ $${ans:-N} = y ]
	@echo "�️  Removing all Docker resources..."
	docker-compose down -v --rmi all
	rm -rf .jekyll-cache _site Gemfile.lock
	@echo "� Rebuilding from scratch..."
	$(MAKE) install
	@echo "✅ Fresh start complete!"

reset-gems: ## Reset and reinstall all gems
	@echo "� Resetting gems..."
	rm -f Gemfile.lock
	docker-compose down
	docker-compose build --no-cache
	$(MAKE) bundle-install
	@echo "✅ Gems reset complete!"

# Quick shortcuts
dev: serve ## Alias for serve
up: serve ## Alias for serve
down: stop ## Alias for stop