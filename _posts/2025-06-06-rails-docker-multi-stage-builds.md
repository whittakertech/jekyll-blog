---
layout: post
date: 2025-06-06 09:00:00 -0600
title: "Rails Docker Architecture: Multi-Stage Builds and Base Images"
slug: "rails-docker-multi-stage-builds"
canonical_url: "https://whittakertech.com/blog/rails-docker-multi-stage-builds/"
description: >-
  Learn how to structure Rails Docker builds with multi-stage architecture, base images, and development/production
  parity. Complete examples with PostgreSQL integration.
og_title: "Rails Docker Multi-Stage Builds: Production-Ready Architecture"
headline: >-
  Rails Docker Architecture: How Multi-Stage Builds and Smart Base Images Eliminated Our "Works on My Machine" Problems
categories: ["Ruby on Rails", "DevOps", "Docker"]
tags: ["Rails Docker", "Multi-stage builds", "Docker architecture", "Base images", "Development environment",
       "Docker Compose", "PostgreSQL Docker", "Container networking", "Rails development", "Docker Hub"]
---

*How we designed a multi-stage Docker architecture that provides development/production parity while optimizing for
build speed, image size, and maintainability.*

## The Architecture Challenge

After deciding to migrate our Rails application from Heroku buildpacks to Docker
([see Part 1](/blog/why-migrate-heroku-buildpacks-docker/)), we faced a crucial architectural decision: how to
structure our Dockerfiles to serve both development and production needs effectively.

The naive approach—cramming everything into a single Dockerfile—leads to several problems:
- **Bloated production images** with unnecessary development tools
- **Slow development builds** when production optimizations interfere with quick iteration
- **Maintenance complexity** when trying to balance competing requirements in one file

Instead, we designed a three-tier architecture that maximizes efficiency and maintainability.

## The Three-Tier Docker Architecture

### Tier 1: Dockerfile.base (Foundation)
A shared foundation containing system dependencies and runtime tools that both development and production need.

### Tier 2: Dockerfile.dev (Development)
Development-optimized container with debugging tools, volume mounts, and fast iteration capabilities.

### Tier 3: Dockerfile (Production)
Lean production container optimized for memory usage, security, and deployment efficiency.

This separation allows each environment to optimize for its specific requirements while maintaining consistency in the
core stack.

## Building the Foundation: Dockerfile.base

The base image handles the complex system-level setup that both environments share:

```dockerfile
ARG RUBY_VERSION=3.2.7

FROM ruby:${RUBY_VERSION}-slim

ARG NODE_VERSION=20.18.3

# Install system dependencies shared by all environments
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

# Setup Node.js with specific version
RUN NODE_MAJOR=$(echo ${NODE_VERSION} | cut -d. -f1) && \
    curl -sL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - && \
    apt-get update -qq && \
    apt-get install -y nodejs && \
    npm install -g yarn && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /choir-site
RUN gem install bundler -v "~> 2.4.0"
```

### Key Design Decisions

**ARG Placement Strategy:**
```dockerfile
ARG RUBY_VERSION=3.2.7    # Available for FROM instruction
FROM ruby:${RUBY_VERSION}-slim
ARG NODE_VERSION=20.18.3  # Re-declared for use in RUN commands
```

ARG variables defined before FROM are only available for the FROM instruction itself. To use version variables in RUN
commands, they must be re-declared after FROM.

**Version Management:**
Instead of hardcoding versions, we read them from project files:
```bash
# Build command reads from project files
docker build -t whittakertech/choir-base:latest \
  --build-arg RUBY_VERSION=$(cat .ruby-version) \
  --build-arg NODE_VERSION=$(cat .node-version) \
  -f Dockerfile.base .
```

**Package Installation Strategy:**
```dockerfile
# Install, clean, and remove package lists in single layer
RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends \
        package1 \
        package2 && \
    rm -rf /var/lib/apt/lists/*
```

This pattern minimizes image size by cleaning up package metadata in the same layer as installation.

### Publishing the Base Image

The base image must be published to a container registry before other Dockerfiles can reference it:

```bash
# Build with proper tags
docker build -t whittakertech/choir-base:latest \
  --build-arg RUBY_VERSION=$(cat .ruby-version) \
  --build-arg NODE_VERSION=$(cat .node-version) \
  -f Dockerfile.base .

# Tag with version for reproducibility
docker tag whittakertech/choir-base:latest \
  whittakertech/choir-base:ruby-3.2.7-node-20.18.3

# Push to Docker Hub
docker login
docker push whittakertech/choir-base:latest
docker push whittakertech/choir-base:ruby-3.2.7-node-20.18.3
```

**Critical for Heroku:** Heroku's container registry pulls images during the build process. Without publishing the base
image to an accessible registry, deployments fail with "image not found" errors.

## Development Environment: Dockerfile.dev

The development Dockerfile prioritizes developer experience and debugging capabilities:

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
        curl && \
    rm -rf /var/lib/apt/lists/*

# Configure environment for development
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
    bundle install

# Install yarn packages for development
COPY package.json yarn.lock ./
RUN yarn install

# Copy application code
COPY . .

# Expose ports for Rails server and live reload
EXPOSE 1234 3000
CMD ["bundle", "exec", "rails", "server", "-b", "0.0.0.0"]
```

### Development-Specific Optimizations

**Full Dependency Installation:**
```dockerfile
# Development needs all gem groups
bundle config unset without
bundle config set --local with "development test"
bundle install

# Development needs all npm packages
yarn install
```

Unlike production, development installs testing frameworks, debugging tools, and development servers.

**Debugging Tools:**
```dockerfile
# Essential development packages
python3     # For node-gyp native compilation
g++         # For native gem compilation  
make        # For building native extensions
vim         # For container debugging
htop        # For process monitoring
```

**Port Exposure:**
```dockerfile
EXPOSE 1234 3000  # Live reload and Rails server
```

Development exposes additional ports for asset live-reloading and debugging interfaces.

## Docker Compose: Development Orchestration

Docker Compose orchestrates the complete development environment:

```yaml
services:
  web:
    build:
      context: .
      dockerfile: Dockerfile.dev
    container_name: choir-site-web
    command: foreman start -f Procfile.dev
    environment:
      - DATABASE_URL=postgresql://choir_postgres:password@postgres13:5432/choirsite_dev
      - RAILS_ENV=development
      - REDIS_URL=redis://redis:6379/0
    networks:
      - postgres_network
    ports:
      - "3000:3000"   # Rails server
      - "1234:1234"   # Live reload
    volumes:
      - .:/choir-site              # Live code reloading
      - gem_cache:/usr/local/bundle/gems  # Persistent gem cache
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:13
    container_name: postgres13
    environment:
      POSTGRES_USER: choir_postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: choirsite_dev
    ports:
      - "5432:5432"
    networks:
      - postgres_network
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    container_name: redis_dev
    ports:
      - "6379:6379"
    networks:
      - postgres_network
    volumes:
      - redis_data:/data

networks:
  postgres_network:
    driver: bridge

volumes:
  gem_cache:
  postgres_data:
  redis_data:
```

### Key Compose Features

**Volume Strategy:**
```yaml
volumes:
  - .:/choir-site                     # Live code editing
  - gem_cache:/usr/local/bundle/gems  # Persistent gems across rebuilds
```

Live code mounting enables instant feedback during development, while gem caching prevents re-downloading dependencies
on container rebuilds.

**Database Integration:**
```yaml
environment:
  - DATABASE_URL=postgresql://choir_postgres:password@postgres13:5432/choirsite_dev
depends_on:
  - postgres
```

The web container waits for PostgreSQL to start and connects using container networking.

**Process Management:**
```yaml
command: foreman start -f Procfile.dev
```

Foreman manages multiple processes (Rails server, asset watchers) within the container:

```procfile
# Procfile.dev
web: env RUBY_DEBUG_OPEN=true bin/rails server -b 0.0.0.0 -p 3000
css: yarn watch:css
js: yarn build --watch
```

## Production Optimization: Dockerfile

The production Dockerfile prioritizes efficiency and security:

```dockerfile
FROM whittakertech/choir-base:latest

# Configure production environment
ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_DEPLOYMENT=true

# Install production gems only
COPY Gemfile* .ruby-version ./
RUN bundle config set --local without $BUNDLE_WITHOUT && \
    bundle config set --local deployment true && \
    bundle config set --local path vendor/bundle && \
    bundle install --jobs 4 --retry 3

# Install production npm dependencies
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile --production=false

# Copy application code
COPY . .

# Build assets in production mode
RUN yarn build && yarn build:css && \
    SECRET_KEY_BASE=dummy bundle exec rake assets:precompile

# Remove unnecessary files to reduce image size
RUN rm -rf node_modules/.cache \
           tmp/cache \
           log/* \
           .git

EXPOSE $PORT
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### Production-Specific Optimizations

**Minimal Dependencies:**
```dockerfile
ENV BUNDLE_WITHOUT="development test"
bundle install --jobs 4 --retry 3
```

Production excludes testing frameworks, debugging tools, and development servers.

**Build-Time Asset Compilation:**
```dockerfile
# Build all assets during image creation
yarn build && yarn build:css
SECRET_KEY_BASE=dummy bundle exec rake assets:precompile
```

Assets are compiled once during build rather than at runtime, improving startup speed.

**Image Size Reduction:**
```dockerfile
# Clean up build artifacts
RUN rm -rf node_modules/.cache \
           tmp/cache \
           log/* \
           .git
```

Removing build artifacts and unnecessary files reduces the final image size.

## Development Workflow Integration

### Makefile Commands

```makefile
# Development commands
.PHONY: dev-up dev-down dev-rebuild dev-logs

dev-up:
	docker-compose up -d

dev-down:
	docker-compose down

dev-rebuild:
	docker-compose down
	docker-compose build --no-cache web
	docker-compose up -d

dev-logs:
	docker-compose logs -f web

dev-console:
	docker-compose run --rm web rails console

dev-test:
	docker-compose run --rm web bundle exec rails test

dev-migrate:
	docker-compose run --rm web rails db:migrate
```

### GitHub Actions Integration

```yaml
name: Rails CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_PASSWORD: password
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v4

      - name: Build test image
        run: |
          docker build -t choir-site:test -f Dockerfile.dev .

      - name: Run tests
        run: |
          docker run --rm \
            --network host \
            -e DATABASE_URL=postgresql://postgres:password@localhost:5432/postgres \
            -e RAILS_ENV=test \
            choir-site:test \
            bundle exec rails test

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4

      - name: Build and push base image
        run: |
          docker build -t whittakertech/choir-base:latest -f Dockerfile.base .
          echo ${{ secrets.DOCKER_PASSWORD }} | docker login -u ${{ secrets.DOCKER_USERNAME }} --password-stdin
          docker push whittakertech/choir-base:latest

      - name: Deploy to Heroku
        env:
          HEROKU_API_KEY: ${{ secrets.HEROKU_API_KEY }}
        run: |
          heroku container:login
          heroku container:push web -a ${{ secrets.HEROKU_APP_NAME }}
          heroku container:release web -a ${{ secrets.HEROKU_APP_NAME }}
```

## Results and Benefits

This multi-stage architecture delivered significant improvements:

### Build Performance
- **Development builds:** 2-3 minutes (with cached base image)
- **Production builds:** 4-5 minutes (including asset compilation)
- **Base image updates:** Only when system dependencies change

### Developer Experience
- **Environment setup:** `docker-compose up` (30 seconds)
- **Code changes:** Instant reload with volume mounts
- **Database reset:** `docker-compose down -v && docker-compose up`
- **New developer onboarding:** 15 minutes from zero to running

### Production Efficiency
- **Image size:** 450MB (vs 800MB+ with single-stage approach)
- **Memory usage:** ~200MB baseline (vs 350MB+ with development tools)
- **Build reproducibility:** 100% consistent across environments

### Maintenance Simplicity
- **Base image updates:** Propagate automatically to dev and production
- **Environment-specific changes:** Isolated to appropriate Dockerfiles
- **Version management:** Centralized in project files (.ruby-version, .node-version)

## Common Pitfalls and Solutions

### Pitfall 1: ARG Scope Confusion
```dockerfile
# Wrong - ARG not available after FROM
ARG RUBY_VERSION=3.2.7
FROM ruby:${RUBY_VERSION}-slim
RUN echo "Ruby version: ${RUBY_VERSION}"  # Empty!

# Correct - Re-declare ARG after FROM
ARG RUBY_VERSION=3.2.7
FROM ruby:${RUBY_VERSION}-slim
ARG RUBY_VERSION  # Re-declare for RUN commands
RUN echo "Ruby version: ${RUBY_VERSION}"  # Works!
```

### Pitfall 2: Forgetting Base Image Publication
```bash
# This fails in CI/CD if base image isn't published
FROM whittakertech/choir-base:latest  # Image not found!

# Solution: Ensure base image is built and pushed first
docker build -t whittakertech/choir-base:latest -f Dockerfile.base .
docker push whittakertech/choir-base:latest
```

### Pitfall 3: Development/Production Package Confusion
```dockerfile
# Wrong - production installs development tools
RUN bundle install  # Installs everything!

# Correct - explicit environment control
ENV BUNDLE_WITHOUT="development test"
RUN bundle install  # Production gems only
```

## What's Next

This foundation enables reliable, efficient Docker deployments, but several challenges remain:

- **Asset pipeline configuration** and dependency management
- **System package conflicts** between Node.js and Ruby requirements
- **Production deployment** optimization and monitoring

The [next post in this series](/blog/rails-docker-asset-pipeline-conflicts/) dives into the asset pipeline challenges
and the breakthrough that made compilation work reliably across environments.

---

*This is Part 2 of our Rails Docker Migration series. The complete architecture code is available in our
[GitHub repository](https://github.com/whittakertech/choir-site), and the next post covers the asset pipeline solutions
that made this migration successful.*
