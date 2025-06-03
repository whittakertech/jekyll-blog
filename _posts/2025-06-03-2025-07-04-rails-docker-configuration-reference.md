---
layout: post
date: 2025-06-03 09:00:00 -0600
title: "Rails Docker Migration: Complete Configuration Reference"
slug: "rails-docker-configuration-reference"
canonical_url: "https://whittakertech.com/blog/rails-docker-configuration-reference/"
description: >-
  Complete Rails Docker configuration reference with all Dockerfiles, GitHub Actions, Makefiles, and troubleshooting
  guides. Ready-to-use templates for production deployment.
og_title: "Rails Docker: Complete Configuration Templates & Reference"
headline: >-
  The Complete Rails Docker Reference: Every Configuration File, Command, and Troubleshooting Guide You Need for
  Production-Ready Container Deployment
categories: ["Ruby on Rails", "DevOps", "Reference"]
tags: ["Rails Docker reference", "Configuration templates", "Docker troubleshooting", "Production deployment",
       "Complete guide", "Reference documentation", "Rails containerization", "Docker best practices",
       "Configuration examples"]
---

*A comprehensive reference containing every configuration file, command, and troubleshooting procedure from our
successful Rails Docker migration. Bookmark this guide for your own containerization projects.*

## Quick Start Template

For teams ready to implement Docker containerization immediately, here's the complete file structure and configurations:

### Project Structure
```
your-rails-app/
├── Dockerfile.base          # Shared system dependencies
├── Dockerfile.dev           # Development environment
├── Dockerfile               # Production deployment
├── docker-compose.yml       # Development orchestration
├── heroku.yml              # Heroku container config
├── Makefile                # Development commands
├── .dockerignore           # Build context exclusions
├── .github/
│   └── workflows/
│       ├── deploy.yml      # CI/CD pipeline
│       └── validate.yml    # Quality checks
├── config/
│   ├── database.yml        # Database configuration
│   └── puma.rb            # Production server config
├── package.json            # Node.js dependencies
└── Gemfile                 # Ruby dependencies
```

## Core Docker Configuration Files

### Dockerfile.base (Foundation)

```dockerfile
ARG RUBY_VERSION=3.2.7

FROM ruby:${RUBY_VERSION}-slim

ARG NODE_VERSION=20.18.3

# Essential system packages
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        git \
        gnupg \
        libpq-dev \
        postgresql-client \
        software-properties-common && \
    rm -rf /var/lib/apt/lists/*

# Install Node.js with specific version
RUN NODE_MAJOR=$(echo ${NODE_VERSION} | cut -d. -f1) && \
    curl -sL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get update -qq && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Install compatible bundler version
RUN gem install bundler -v "~> 2.4.0"

# Create app user for security
RUN groupadd -r app && useradd -r -g app app
RUN chown -R app:app /app
```

### Dockerfile.dev (Development)

```dockerfile
FROM whittakertech/choir-base:latest

# Install development and debugging tools
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        python3 \
        g++ \
        make \
        pkg-config \
        libyaml-dev \
        libffi-dev \
        vim \
        htop \
        curl \
        less && \
    rm -rf /var/lib/apt/lists/*

# Development environment configuration
ENV GEM_HOME=/usr/local/bundle
ENV GEM_PATH=/usr/local/bundle
ENV BUNDLE_PATH=/usr/local/bundle
ENV BUNDLE_BIN=/usr/local/bundle/bin
ENV PATH="${BUNDLE_BIN}:${PATH}"
ENV RAILS_ENV=development
ENV NODE_ENV=development

# Install ALL gems including development and test groups
COPY Gemfile* .ruby-version .node-version ./
RUN gem update --system 3.6.6 && \
    bundle config unset without && \
    bundle config set --local with "development test" && \
    bundle install --jobs 4 --retry 3

# Install all yarn packages for development
COPY package.json yarn.lock ./
RUN yarn install

# Copy application code
COPY . .

# Set up file permissions
RUN chown -R app:app /app
USER app

# Expose development ports
EXPOSE 1234 3000

# Default development command
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Dockerfile (Production)

```dockerfile
FROM whittakertech/choir-base:latest

# Production environment configuration
ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_DEPLOYMENT=true \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

# Install production gems only
COPY Gemfile* .ruby-version ./
RUN bundle config set --local without $BUNDLE_WITHOUT && \
    bundle config set --local deployment true && \
    bundle config set --local path vendor/bundle && \
    bundle install --jobs 4 --retry 3

# Install production npm dependencies
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Copy application code
COPY . .

# Build assets in production mode
RUN yarn build && yarn build:css && \
    SECRET_KEY_BASE=temporarykey bundle exec rake assets:precompile

# Remove unnecessary files to reduce image size
RUN rm -rf node_modules/.cache \
           tmp/cache \
           log/* \
           .git \
           spec/ \
           test/ \
           doc/ \
           README.md

# Set file permissions
RUN chown -R app:app /app
USER app

# Expose port (Heroku provides $PORT)
EXPOSE $PORT

# Production startup command
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

## Development Environment Configuration

### docker-compose.yml

```yaml
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile.dev
    container_name: rails-app-web
    command: foreman start -f Procfile.dev
    environment:
      - DATABASE_URL=postgresql://postgres:password@postgres:5432/app_development
      - REDIS_URL=redis://redis:6379/0
      - RAILS_ENV=development
      - NODE_ENV=development
    networks:
      - app_network
    ports:
      - "3000:3000"   # Rails server
      - "1234:1234"   # Live reload
    volumes:
      - .:/app                              # Live code reloading
      - gem_cache:/usr/local/bundle         # Persistent gem cache
      - node_modules:/app/node_modules       # Node modules cache
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_started

  postgres:
    image: postgres:13
    container_name: postgres_dev
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: app_development
    ports:
      - "5432:5432"
    networks:
      - app_network
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: redis_dev
    ports:
      - "6379:6379"
    networks:
      - app_network
    volumes:
      - redis_data:/data

networks:
  app_network:
    driver: bridge

volumes:
  gem_cache:
  node_modules:
  postgres_data:
  redis_data:
```

### Procfile.dev

```
web: env RUBY_DEBUG_OPEN=true bin/rails server -b 0.0.0.0 -p 3000
css: yarn watch:css
js: yarn build --watch
worker: bundle exec sidekiq
```

## Ruby and Node.js Configuration

### Gemfile (Optimized Dependencies)

```ruby
source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.2.7"

# Core Rails
gem "rails", "~> 7.1.0"

# Database
gem "pg", "~> 1.1"

# Server
gem "puma", ">= 5.0"

# Assets (avoid libv8-dev conflicts)
gem "propshaft"
gem "sassc-rails", ">= 2.1.0"  # C-based SASS (no JS runtime)

# JavaScript runtime (self-contained)
gem "mini_racer", "~> 0.8.0"   # Bundled V8 engine

# Essential gems
gem "bootsnap", require: false
gem "sprockets-rails"
gem "stimulus-rails"
gem "turbo-rails"
gem "redis", ">= 4.0.1"

# Background jobs
gem "sidekiq", "~> 7.0"
gem "sidekiq-cron"

# Security
gem "rack-attack"

group :development, :test do
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "web-console"
  gem "listen", "~> 3.3"
  gem "spring"
  gem "spring-watcher-listen", "~> 2.0.0"
end
```

### package.json (Corrected Dependencies)

```json
{
  "name": "rails-app",
  "private": true,
  "dependencies": {
    "@hotwired/stimulus": "^3.2.2",
    "@hotwired/turbo-rails": "^8.0.12",
    "bootstrap": "^5.3.3",
    "autoprefixer": "^10.4.20",
    "esbuild": "^0.25.0",
    "postcss": "^8.5.3",
    "postcss-cli": "^11.0.0",
    "sass": "^1.85.1"
  },
  "devDependencies": {
    "nodemon": "^3.1.9",
    "concurrently": "^8.2.2",
    "foreman": "^3.0.1"
  },
  "scripts": {
    "build": "esbuild app/javascript/*.* --bundle --sourcemap --outdir=app/assets/builds --public-path=/assets --minify",
    "build:dev": "esbuild app/javascript/*.* --bundle --sourcemap --outdir=app/assets/builds --public-path=/assets",
    "build:css": "sass ./app/assets/stylesheets/application.scss:./app/assets/builds/application.css --load-path=node_modules --style=compressed",
    "build:css:dev": "sass ./app/assets/stylesheets/application.scss:./app/assets/builds/application.css --load-path=node_modules --style=expanded --source-map",
    "watch:css": "nodemon --watch ./app/assets/stylesheets/ --ext scss --exec \"yarn build:css:dev\"",
    "dev": "concurrently \"yarn build:dev --watch\" \"yarn watch:css\""
  }
}
```

## Production Deployment Configuration

### heroku.yml

```yaml
build:
  docker:
    web: Dockerfile
  args:
    RUBY_VERSION: "3.2.7"
    NODE_VERSION: "20.18.3"
  config:
    RAILS_ENV: production
    NODE_ENV: production

run:
  web: bundle exec puma -C config/puma.rb
  release: bundle exec rake db:migrate

setup:
  addons:
    - plan: heroku-postgresql:essential-0
    - plan: heroku-redis:mini
  config:
    RAILS_LOG_TO_STDOUT: true
    RAILS_SERVE_STATIC_FILES: true
    RACK_ENV: production
    RAILS_ENV: production
```

### config/puma.rb (Production Optimized)

```ruby
# Puma configuration for containerized deployment

# Number of worker processes (adjust based on dyno size)
workers ENV.fetch("WEB_CONCURRENCY") { 2 }

# Threads per worker (adjust based on application characteristics)
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { max_threads_count }
threads min_threads_count, max_threads_count

# Preload application for memory efficiency
preload_app!

# Port configuration (Heroku provides $PORT)
port ENV.fetch("PORT") { 3000 }

# Environment
environment ENV.fetch("RAILS_ENV") { "development" }

# PID file location
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Allow puma to be restarted by `rails restart` command
plugin :tmp_restart

# Worker configuration for production
on_worker_boot do
  # Worker specific setup for Rails 4.1+
  ActiveRecord::Base.establish_connection if defined?(ActiveRecord)
end

# Master process configuration
before_fork do
  # Disconnect from the database before forking
  ActiveRecord::Base.connection_pool.disconnect! if defined?(ActiveRecord)
end

# Production memory management
if ENV['RAILS_ENV'] == 'production'
  # Restart workers every 1000 requests to prevent memory leaks
  worker_shutdown_timeout 30
  worker_timeout 60

  # Log memory usage
  on_booted do
    puts "Puma booted with #{workers} workers and #{max_threads_count} threads per worker"
  end
end
```

## CI/CD Pipeline Configuration

### .github/workflows/deploy.yml

```yaml
name: Rails CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

env:
  REGISTRY: docker.io
  BASE_IMAGE: whittakertech/rails-base

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: password
          POSTGRES_DB: test_db
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: '3.2.7'
          bundler-cache: true

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20.18.3'
          cache: 'yarn'

      - name: Install dependencies
        run: |
          bundle install --jobs 4 --retry 3
          yarn install --frozen-lockfile

      - name: Set up database
        env:
          DATABASE_URL: postgresql://postgres:password@localhost:5432/test_db
          RAILS_ENV: test
        run: |
          bundle exec rails db:create db:migrate

      - name: Build assets
        run: |
          yarn build:dev && yarn build:css:dev
          bundle exec rails assets:precompile

      - name: Run tests
        env:
          DATABASE_URL: postgresql://postgres:password@localhost:5432/test_db
          REDIS_URL: redis://localhost:6379/0
          RAILS_ENV: test
        run: |
          bundle exec rspec
          bundle exec rails test

      - name: Run security checks
        run: |
          bundle exec brakeman --no-pager
          bundle exec bundle-audit check --update

  build-base-image:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Check if base image needs rebuild
        id: check-base
        run: |
          if git diff --name-only HEAD~1 | grep -E "(Dockerfile.base|.ruby-version|.node-version)"; then
            echo "rebuild=true" >> $GITHUB_OUTPUT
          else
            echo "rebuild=false" >> $GITHUB_OUTPUT
          fi

      - name: Build and push base image
        if: steps.check-base.outputs.rebuild == 'true'
        uses: docker/build-push-action@v5
        with:
          context: .
          file: ./Dockerfile.base
          push: true
          tags: |
            ${{ env.BASE_IMAGE }}:latest
            ${{ env.BASE_IMAGE }}:ruby-3.2.7-node-20.18.3
          build-args: |
            RUBY_VERSION=3.2.7
            NODE_VERSION=20.18.3
          cache-from: type=gha
          cache-to: type=gha,mode=max

  deploy-staging:
    needs: [test, build-base-image]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/develop'
    environment: staging

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy to Heroku Staging
        uses: akhileshns/heroku-deploy@v3.12.14
        with:
          heroku_api_key: ${{ secrets.HEROKU_API_KEY }}
          heroku_app_name: ${{ secrets.HEROKU_STAGING_APP }}
          heroku_email: ${{ secrets.HEROKU_EMAIL }}
          usedocker: true

  deploy-production:
    needs: [test, build-base-image]
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy to Heroku Production
        env:
          HEROKU_API_KEY: ${{ secrets.HEROKU_API_KEY }}
          HEROKU_APP_NAME: ${{ secrets.HEROKU_PRODUCTION_APP }}
        run: |
          # Install Heroku CLI
          curl https://cli-assets.heroku.com/install.sh | sh

          # Login to Heroku Container Registry
          heroku container:login

          # Build and push container
          heroku container:push web -a $HEROKU_APP_NAME

          # Release container
          heroku container:release web -a $HEROKU_APP_NAME

      - name: Run post-deployment tasks
        env:
          HEROKU_API_KEY: ${{ secrets.HEROKU_API_KEY }}
          HEROKU_APP_NAME: ${{ secrets.HEROKU_PRODUCTION_APP }}
        run: |
          # Wait for deployment to complete
          sleep 30

          # Verify deployment
          heroku ps -a $HEROKU_APP_NAME

          # Check application health
          curl -f https://$HEROKU_APP_NAME.herokuapp.com/health || exit 1

  notify:
    needs: [deploy-production]
    runs-on: ubuntu-latest
    if: always()

    steps:
      - name: Deployment notification
        run: |
          if [ "${{ needs.deploy-production.result }}" == "success" ]; then
            echo "✅ Production deployment successful"
          else
            echo "❌ Production deployment failed"
            exit 1
          fi
```

## Development Workflow Tools

### Makefile

```makefile
# Rails Docker Development Makefile

.PHONY: help install build up down restart clean logs shell test migrate console

# Default target
help: ## Show this help message
	@echo "Rails Docker Development Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# Development environment management
install: ## Install dependencies and build containers
	@echo "🔧 Installing dependencies..."
	docker-compose build --no-cache
	docker-compose run --rm web bundle install
	docker-compose run --rm web yarn install
	@echo "✅ Installation complete!"

build: ## Build development containers
	@echo "🏗️  Building containers..."
	docker-compose build
	@echo "✅ Build complete!"

up: ## Start development environment
	@echo "🚀 Starting development environment..."
	@echo "📱 App available at: http://localhost:3000"
	docker-compose up

down: ## Stop development environment
	@echo "🛑 Stopping development environment..."
	docker-compose down

restart: ## Restart development environment
	@echo "🔄 Restarting development environment..."
	docker-compose restart

clean: ## Clean up containers and volumes
	@echo "🧹 Cleaning up..."
	docker-compose down -v
	docker system prune -f
	@echo "✅ Cleanup complete!"

# Development tasks
logs: ## Show application logs
	docker-compose logs -f web

shell: ## Open shell in web container
	@echo "🐚 Opening shell..."
	docker-compose run --rm web bash

console: ## Open Rails console
	@echo "🚂 Opening Rails console..."
	docker-compose run --rm web rails console

test: ## Run test suite
	@echo "🧪 Running tests..."
	docker-compose run --rm web bundle exec rspec
	docker-compose run --rm web bundle exec rails test

migrate: ## Run database migrations
	@echo "🗃️  Running migrations..."
	docker-compose run --rm web rails db:migrate

seed: ## Seed database
	@echo "🌱 Seeding database..."
	docker-compose run --rm web rails db:seed

reset: ## Reset database
	@echo "🔄 Resetting database..."
	docker-compose run --rm web rails db:drop db:create db:migrate db:seed

# Asset management
assets-build: ## Build assets
	@echo "🎨 Building assets..."
	docker-compose run --rm web yarn build
	docker-compose run --rm web yarn build:css

assets-precompile: ## Precompile Rails assets
	@echo "🎨 Precompiling assets..."
	docker-compose run --rm web rails assets:precompile

# Production simulation
prod-build: ## Build production image locally
	@echo "🏭 Building production image..."
	docker build -t rails-app:production .

prod-run: ## Run production image locally
	@echo "🏭 Running production image..."
	docker run --rm -p 3000:3000 \
		-e DATABASE_URL=postgresql://postgres:password@host.docker.internal:5432/app_development \
		-e RAILS_ENV=production \
		-e SECRET_KEY_BASE=dummy \
		rails-app:production

# Deployment helpers
deploy-staging: ## Deploy to staging
	@echo "🚀 Deploying to staging..."
	git push origin develop

deploy-production: ## Deploy to production
	@echo "🚀 Deploying to production..."
	git push origin main

# Monitoring and debugging
ps: ## Show container status
	docker-compose ps

top: ## Show container resource usage
	docker stats

health: ## Check application health
	@echo "🏥 Checking application health..."
	curl -f http://localhost:3000/health || echo "❌ Health check failed"

# Maintenance
update: ## Update dependencies
	@echo "⬆️  Updating dependencies..."
	docker-compose run --rm web bundle update
	docker-compose run --rm web yarn upgrade
	@echo "✅ Dependencies updated!"

security-check: ## Run security checks
	@echo "🔒 Running security checks..."
	docker-compose run --rm web bundle exec brakeman
	docker-compose run --rm web bundle exec bundle-audit

# Quick shortcuts
start: up ## Alias for up
stop: down ## Alias for down
```

### .dockerignore

```
# Git
.git
.gitignore

# Documentation
README.md
CHANGELOG.md
LICENSE

# Development files
.env*
.DS_Store
.vscode/
.idea/

# Logs
log/
*.log

# Runtime files
tmp/
storage/
pid/

# Test files
spec/
test/
coverage/

# Build artifacts
node_modules/
.sass-cache/
public/assets/
app/assets/builds/

# Database
*.sqlite3
*.sqlite3-journal

# Dependency directories
vendor/bundle/

# Platform specific
Thumbs.db
.DS_Store
```

## Environment-Specific Configuration

### config/database.yml

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000
  host: <%= ENV.fetch("DB_HOST") { "localhost" } %>
  port: <%= ENV.fetch("DB_PORT") { 5432 } %>

development:
  <<: *default
  database: app_development
  username: postgres
  password: password
  host: postgres  # Docker service name

test:
  <<: *default
  database: app_test
  username: postgres
  password: password

production:
  <<: *default
  url: <%= ENV['DATABASE_URL'] %>
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
```

### config/environments/production.rb (Key Settings)

```ruby
Rails.application.configure do
  # Basic production settings
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Asset configuration for containers
  config.assets.compile = false
  config.assets.digest = true
  config.assets.css_compressor = nil
  config.assets.js_compressor = nil

  # Logging for containers
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    logger = ActiveSupport::Logger.new(STDOUT)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  # SSL and security
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path =~ /health/ } } }

  # Performance optimization
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch("REDIS_URL") { "redis://localhost:6379/1" },
    pool_size: ENV.fetch("RAILS_MAX_THREADS") { 5 }
  }
end
```

## Troubleshooting Reference

### Common Build Issues

**Issue: Base image not found**
```dockerfile
# Error: Error response from daemon: pull access denied for whittakertech/choir-base
# Solution: Ensure base image is built and pushed
docker build -t whittakertech/choir-base:latest -f Dockerfile.base .
docker push whittakertech/choir-base:latest
```

**Issue: Gem compilation failures**
```dockerfile
# Error: Failed to build gem native extension
# Solution: Install development packages
RUN apt-get update && apt-get install -y build-essential libpq-dev python3
```

**Issue: Asset compilation failures**
```bash
# Error: yarn build command not found
# Solution: Check package.json scripts and dependencies
{
  "scripts": {
    "build": "esbuild app/javascript/*.* --bundle --outdir=app/assets/builds"
  },
  "dependencies": {
    "esbuild": "^0.25.0"  # Must be in dependencies, not devDependencies
  }
}
```

### Runtime Issues

**Issue: Database connection failures**
```bash
# Check database URL format
echo $DATABASE_URL
# Should be: postgresql://user:password@host:port/database

# Test connection
heroku run rails runner "puts ActiveRecord::Base.connection.execute('SELECT version()').first" -a your-app
```

**Issue: Memory exhaustion**
```bash
# Monitor memory usage
heroku logs --tail -a your-app | grep "sample#memory_total"

# Check for memory leaks
heroku run rails runner "GC.start; puts `ps -o pid,vsz,rss,pcpu,comm -p #{Process.pid}`" -a your-app
```

**Issue: Asset serving problems**
```bash
# Verify asset compilation
heroku run ls -la public/assets -a your-app

# Check asset configuration
heroku run rails runner "puts Rails.application.config.assets.compile" -a your-app
# Should be false in production
```

### Development Environment Issues

**Issue: Docker Compose connection failures**
```yaml
# Ensure services are on same network
networks:
  - app_network

# Use service names for inter-container communication
DATABASE_URL: postgresql://postgres:password@postgres:5432/app_development
```

**Issue: Volume mount permissions**
```bash
# Fix permission issues
docker-compose run --rm web chown -R $(id -u):$(id -g) .
```

**Issue: Slow bind mounts on macOS**
```yaml
# Use delegated mounting for better performance
volumes:
  - .:/app:delegated
  - gem_cache:/usr/local/bundle
```

### Performance Optimization Checklist

- [ ] **Base image size**: Use slim variants (ruby:3.2.7-slim vs ruby:3.2.7)
- [ ] **Layer caching**: Copy dependency files before application code
- [ ] **Multi-stage builds**: Separate build and runtime stages
- [ ] **Dependency classification**: Build tools in dependencies, dev tools in devDependencies
- [ ] **Asset precompilation**: Compile assets during build, not runtime
- [ ] **File cleanup**: Remove unnecessary files after installation
- [ ] **Process management**: Use proper init system for multi-process containers
- [ ] **Memory monitoring**: Set up alerts for memory usage

## Quick Command Reference

### Docker Operations
```bash
# Build specific image
docker build -t app:tag -f Dockerfile.base .

# Run with environment variables
docker run --rm -e RAILS_ENV=production app:tag

# Inspect container
docker inspect container_name
docker logs container_name
docker exec -it container_name bash
```

### Heroku Container Operations
```bash
# Login and push
heroku container:login
heroku container:push web -a app-name
heroku container:release web -a app-name

# Debug deployment
heroku logs --tail -a app-name
heroku run bash -a app-name
heroku ps -a app-name

# Scale and manage
heroku ps:scale web=2 -a app-name
heroku restart -a app-name
heroku releases -a app-name
heroku rollback v123 -a app-name
```

## Final Thoughts

This comprehensive reference guide contains every configuration file, command, and troubleshooting procedure from our
successful Rails Docker migration. The migration delivered:

- **60% memory reduction** (512MB+ → 200MB baseline)
- **100% deployment reliability** (eliminated package conflicts)
- **50% faster builds** (4-5 minutes vs 8-12 minutes)
- **Better development experience** (one-command environment setup)

**For teams implementing similar migrations:**

1. **Start with the business case** - Performance problems create clear ROI
2. **Use the base image strategy** - Shared foundations reduce complexity
3. **Solve dependencies systematically** - Don't fight package managers
4. **Test thoroughly** - Validate each step before moving forward
5. **Monitor everything** - Measure improvements to justify effort

The complete source code, deployment configurations, and operational procedures are available in our
[GitHub repository](https://github.com/whittakertech/choir-site).

**Need help with your Rails Docker migration?** [Get in touch](/contact/) - we've guided several teams through similar
transformations and would be happy to help you achieve similar results.

---

*This concludes our Rails Docker Migration series. The techniques and configurations in this reference guide have been
battle-tested in production and continue to serve as the foundation for reliable, efficient Rails deployments.*