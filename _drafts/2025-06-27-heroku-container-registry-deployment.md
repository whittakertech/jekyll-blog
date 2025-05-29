---
layout: post
date: 2025-06-27 09:00:00 -0600
title: "Production Docker Deployment: Heroku Container Registry Guide"
slug: "heroku-container-registry-deployment"
canonical_url: "https://whittakertech.com/blog/heroku-container-registry-deployment/"
description: >-
  Complete guide to deploying Rails Docker containers on Heroku. Includes heroku.yml config, GitHub Actions CI/CD,
  monitoring setup, and performance optimization results.
og_title: "Rails Docker on Heroku: Complete Deployment Guide"
headline: >-
  From Container to Production: How Heroku Container Registry Deployment Delivered Our 60% Memory Reduction and
  Bulletproof CI/CD Pipeline
categories: ["Ruby on Rails", "DevOps", "Deployment"]
tags: ["Heroku container registry", "Docker deployment", "heroku.yml", "GitHub Actions", "CI/CD pipeline",
       "Container monitoring", "Rails production", "Performance monitoring", "Memory optimization",
       "Production deployment"]
---

*The final piece of our Docker migration: deploying containerized Rails applications to Heroku with bulletproof CI/CD,
comprehensive monitoring, and the performance results that justified the entire effort.*

## The Deployment Challenge

After solving our [system dependency conflicts](/blog/rails-docker-libv8-node-conflicts/), we had a working Docker
container that built reliably and performed well locally. But getting it deployed to production on Heroku's Container
Registry presented new challenges:

- **Configuration management** for containerized applications
- **CI/CD pipeline** integration with GitHub Actions
- **Environment variable** handling in Docker contexts
- **Database migrations** in containerized deployments
- **Performance monitoring** to validate our optimization goals

The stakes were high: our entire migration effort would be judged by production performance, and we needed to
demonstrate the promised 60% memory reduction while maintaining reliability.

## Heroku Container Registry Architecture

Heroku's Container Registry allows deploying custom Docker images instead of using buildpacks, but it requires specific
configuration and deployment patterns.

### Understanding the Container Registry Flow

```mermaid
graph LR
    A[Local Development] --> B[GitHub Push]
    B --> C[GitHub Actions CI]
    C --> D[Build Docker Image]
    D --> E[Push to Registry]
    E --> F[Heroku Release]
    F --> G[Production Runtime]
```

The key difference from buildpack deployments: **you control the entire runtime environment**, not just the application
code.

## heroku.yml Configuration

The `heroku.yml` file replaces buildpack configuration and defines how Heroku builds and runs your container:

```yaml
# heroku.yml
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
```

### Key Configuration Elements

**Build Arguments:**
```yaml
build:
  args:
    RUBY_VERSION: "3.2.7"  # Passed to Dockerfile ARG instructions
    NODE_VERSION: "20.18.3"
```

These values are available in your Dockerfile as `ARG` variables, enabling version management through configuration.

**Process Types:**
```yaml
run:
  web: bundle exec puma -C config/puma.rb     # Main web process
  release: bundle exec rake db:migrate        # Pre-release tasks
```

The `release` process runs before each deployment, perfect for database migrations.

**Environment Configuration:**
```yaml
setup:
  config:
    RAILS_LOG_TO_STDOUT: true        # Container-friendly logging
    RAILS_SERVE_STATIC_FILES: true   # Serve assets from container
```

## Production Dockerfile Optimization

The production Dockerfile builds on our multi-stage architecture with deployment-specific optimizations:

```dockerfile
# Production Dockerfile
FROM whittakertech/choir-base:latest

# Configure production environment
ENV RAILS_ENV=production \
    NODE_ENV=production \
    BUNDLE_WITHOUT="development test" \
    BUNDLE_DEPLOYMENT=true \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

# Install production gems with deployment flag
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

# Remove build artifacts to reduce image size
RUN rm -rf node_modules/.cache \
           tmp/cache \
           log/* \
           .git \
           spec/ \
           test/

# Configure container runtime
EXPOSE $PORT
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### Production-Specific Optimizations

**Bundle Configuration:**
```dockerfile
ENV BUNDLE_DEPLOYMENT=true
bundle config set --local deployment true
```

Deployment mode ensures gems are installed exactly as specified in `Gemfile.lock`, preventing version drift.

**Asset Precompilation:**
```dockerfile
RUN SECRET_KEY_BASE=temporarykey bundle exec rake assets:precompile
```

Assets are compiled during the build process, not at runtime, improving startup performance.

**Image Size Reduction:**
```dockerfile
RUN rm -rf node_modules/.cache tmp/cache log/* .git spec/ test/
```

Removing development files and build artifacts reduces the final image size by 20-30%.

## GitHub Actions CI/CD Pipeline

The complete CI/CD pipeline handles testing, building, and deployment:

```yaml
# .github/workflows/deploy.yml
name: Rails CI/CD Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  HEROKU_APP_NAME: choir-site-production

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

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build test image
        run: |
          docker build -t choir-site:test -f Dockerfile.dev .

      - name: Run tests
        run: |
          docker run --rm \
            --network host \
            -e DATABASE_URL=postgresql://postgres:password@localhost:5432/test_db \
            -e RAILS_ENV=test \
            choir-site:test \
            bash -c "bundle exec rails db:create db:migrate && bundle exec rails test"

  build-and-deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build and push base image
        env:
          DOCKER_USERNAME: ${{ secrets.DOCKER_USERNAME }}
          DOCKER_PASSWORD: ${{ secrets.DOCKER_PASSWORD }}
        run: |
          # Build base image if Dockerfile.base changed
          if git diff --name-only HEAD~1 | grep -q "Dockerfile.base"; then
            docker build -t whittakertech/choir-base:latest -f Dockerfile.base .
            echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin
            docker push whittakertech/choir-base:latest
          fi

      - name: Deploy to Heroku
        env:
          HEROKU_API_KEY: ${{ secrets.HEROKU_API_KEY }}
        run: |
          # Install Heroku CLI
          curl https://cli-assets.heroku.com/install.sh | sh
          
          # Login to Heroku Container Registry
          heroku container:login
          
          # Build and push container
          heroku container:push web -a $HEROKU_APP_NAME
          
          # Release container
          heroku container:release web -a $HEROKU_APP_NAME

  notify:
    needs: build-and-deploy
    runs-on: ubuntu-latest
    if: always()
    steps:
      - name: Deployment notification
        run: |
          if [ "${{ needs.build-and-deploy.result }}" == "success" ]; then
            echo "✅ Deployment successful"
          else
            echo "❌ Deployment failed"
          fi
```

### Pipeline Features

**Conditional Base Image Builds:**
```yaml
if git diff --name-only HEAD~1 | grep -q "Dockerfile.base"; then
  docker build -t whittakertech/choir-base:latest -f Dockerfile.base .
  docker push whittakertech/choir-base:latest
fi
```

The base image is only rebuilt when `Dockerfile.base` changes, saving build time.

**Database Integration Testing:**
```yaml
services:
  postgres:
    image: postgres:13
    # ... health checks and configuration
```

Tests run against a real PostgreSQL instance, catching database-specific issues.

**Heroku CLI Integration:**
```bash
heroku container:login
heroku container:push web -a $HEROKU_APP_NAME
heroku container:release web -a $HEROKU_APP_NAME
```

Direct integration with Heroku's container registry for seamless deployments.

## Environment Variable Management

Container deployments require careful environment variable handling:

### Heroku Configuration

```bash
# Essential production environment variables
heroku config:set RAILS_ENV=production \
                  NODE_ENV=production \
                  RAILS_LOG_TO_STDOUT=true \
                  RAILS_SERVE_STATIC_FILES=true \
                  -a choir-site-production

# Application secrets
heroku config:set RAILS_MASTER_KEY=$(cat config/master.key) \
                  SECRET_KEY_BASE=$(rails secret) \
                  -a choir-site-production
```

### Runtime Environment Setup

```ruby
# config/application.rb
config.force_ssl = true if Rails.env.production?
config.log_level = :info
config.logger = Logger.new(STDOUT) if ENV['RAILS_LOG_TO_STDOUT'].present?

# config/environments/production.rb
config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
config.assets.compile = false
config.assets.digest = true
```

**Container-Specific Configuration:**
- `RAILS_LOG_TO_STDOUT`: Enables container-friendly logging
- `RAILS_SERVE_STATIC_FILES`: Allows serving assets from the container
- `RAILS_MASTER_KEY`: Encrypts credentials for container deployment

## Database Migration Strategy

Container deployments require a different approach to database migrations:

### Release Phase Migrations

```yaml
# heroku.yml
run:
  release: bundle exec rake db:migrate
```

The `release` process runs migrations before the new container starts, ensuring database schema updates complete before
code deployment.

### Migration Safety

```ruby
# Strong migrations configuration
StrongMigrations.auto_analyze = true
StrongMigrations.lock_timeout = 10.seconds
StrongMigrations.statement_timeout = 1.hour

# Safe migration patterns
class AddIndexToUsersEmail < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!  # Required for concurrent indexes
  
  def change
    add_index :users, :email, algorithm: :concurrently
  end
end
```

### Rollback Strategy

```bash
# Manual rollback if needed
heroku releases -a choir-site-production
heroku rollback v123 -a choir-site-production

# Database rollback (if necessary)
heroku run rails db:rollback -a choir-site-production
```

## Performance Monitoring and Validation

The deployment included comprehensive monitoring to validate our performance improvements:

### Memory Usage Monitoring

```bash
# Heroku metrics
heroku logs --tail -a choir-site-production | grep "sample#memory_total"

# Example output showing memory reduction:
# 2025-06-02T15:30:12.345678+00:00 heroku[web.1]: sample#memory_total=201.2MB
# Previous buildpack deployment: sample#memory_total=512.8MB
```

### Application Performance Monitoring

```ruby
# config/environments/production.rb
# Enable detailed performance metrics
config.rails_semantic_logger.add_file_appender = false
config.rails_semantic_logger.add_console_appender = true

# Custom metrics for memory tracking
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe "process_action.action_controller" do |name, started, finished, unique_id, data|
    if data[:status] == 200
      memory_usage = `ps -o pid,vsz,rss,pcpu,comm -p #{Process.pid}`.split("\n")[1]
      Rails.logger.info "Memory usage: #{memory_usage}"
    end
  end
end
```

### Build Performance Tracking

```yaml
# GitHub Actions build time monitoring
- name: Build performance tracking
  run: |
    echo "Build started: $(date)"
    start_time=$(date +%s)
    
    heroku container:push web -a $HEROKU_APP_NAME
    
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    echo "Build completed in ${duration} seconds"
```

## The Final Results

After completing the full deployment pipeline, we achieved our performance goals and more:

### Memory Usage Results

**Before (Heroku Buildpack):**
- Baseline memory: 512MB+ (exceeding dyno limits)
- Peak memory: 650MB+ (frequent R14 errors)
- Memory efficiency: Poor (40% of usage was buildpack overhead)

**After (Docker Container):**
- Baseline memory: 200MB (within 512MB dyno comfortably)
- Peak memory: 320MB (significant headroom)
- Memory efficiency: Excellent (90% application code, 10% container overhead)

**Result: 60% memory reduction as promised**

### Build and Deployment Performance

**Build Times:**
- Development builds: 2-3 minutes (with layer caching)
- Production builds: 4-5 minutes (including asset compilation)
- Base image updates: 6-8 minutes (only when dependencies change)

**Deployment Reliability:**
- Buildpack deployment success rate: 85% (package conflicts, timeouts)
- Container deployment success rate: 100% (reproducible builds)
- Average deployment time: 3-4 minutes (vs 8-12 minutes with buildpacks)

### Application Performance

**Response Times:**
- Average response time: 180ms (vs 280ms with buildpacks)
- 95th percentile: 450ms (vs 800ms with buildpacks)
- Asset serving: 45ms (vs 120ms with buildpacks)

**Startup Performance:**
- Container startup: 8-12 seconds (vs 25-35 seconds with buildpacks)
- Asset loading: Precompiled (vs runtime compilation)
- Database connections: Faster (optimized connection pooling)

## Production Operations Guide

### Deployment Commands

```bash
# Standard deployment (via CI/CD)
git push origin main  # Triggers automatic deployment

# Manual deployment (emergency use)
heroku container:login
heroku container:push web -a choir-site-production
heroku container:release web -a choir-site-production

# Database operations
heroku run rails db:migrate -a choir-site-production
heroku run rails console -a choir-site-production

# Monitoring
heroku logs --tail -a choir-site-production
heroku ps -a choir-site-production
```

### Troubleshooting Common Issues

**Container Build Failures:**
```bash
# Local testing
docker build -t test-build .
docker run --rm test-build bundle exec rails --version

# Check Heroku build logs
heroku logs --source build -a choir-site-production
```

**Memory Issues:**
```bash
# Monitor memory usage
heroku logs --tail -a choir-site-production | grep memory

# Scale if needed
heroku ps:scale web=1:standard-1x -a choir-site-production
```

**Asset Problems:**
```bash
# Verify asset compilation
heroku run ls -la public/assets -a choir-site-production
heroku run rails assets:clobber assets:precompile -a choir-site-production
```

## Best Practices and Lessons Learned

### 1. Base Image Strategy
- Publish base images to Docker Hub for reliable CI/CD
- Version base images to enable rollbacks
- Minimize base image rebuilds to improve build times

### 2. Environment Parity
- Use identical container images across staging and production
- Test migrations in staging before production deployment
- Monitor performance metrics in all environments

### 3. Security Considerations
```dockerfile
# Use specific versions, not latest
FROM ruby:3.2.7-slim  # Not ruby:latest

# Remove unnecessary packages
RUN apt-get autoremove -y && apt-get clean
```

### 4. Monitoring and Alerting
- Set up memory usage alerts below dyno limits
- Monitor build success rates and duration
- Track application performance metrics continuously

### 5. Rollback Preparedness
```bash
# Always test rollback procedures
heroku releases -a choir-site-production
heroku rollback v$(( $(heroku releases -a choir-site-production | head -n2 | tail -n1 | cut -d'v' -f2) - 1 )) -a choir-site-production
```

## What This Means for Your Rails Application

The Docker migration delivered measurable improvements across every metric we cared about:

- **60% memory reduction** - enabling growth without infrastructure costs
- **100% deployment reliability** - eliminating deployment-related outages
- **50% faster builds** - improving developer productivity
- **35% better response times** - enhancing user experience

**For teams considering similar migrations:**

1. **Start with the business case** - performance problems create clear ROI
2. **Invest in proper architecture** - multi-stage builds and base images pay dividends
3. **Solve dependency conflicts systematically** - don't fight the package manager
4. **Implement comprehensive monitoring** - measure everything to validate improvements
5. **Plan for operations** - deployment and monitoring are as important as development

The containerized Rails application now runs efficiently, deploys reliably, and provides a foundation for future
scaling. The migration effort was substantial, but the operational improvements and cost savings justify the investment.

---

*This concludes our Rails Docker Migration series. The complete deployment configuration, monitoring setup, and
operational procedures are available in our [GitHub repository](https://github.com/whittakertech/choir-site). For
questions about implementing similar migrations, [get in touch](/contact/) - we'd be happy to help other teams achieve
similar results.*
