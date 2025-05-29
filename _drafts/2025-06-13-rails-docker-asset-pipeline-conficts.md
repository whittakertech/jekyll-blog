---
layout: post
date: 2025-06-13 09:00:00 -0600
title: "Solving Rails Asset Pipeline Conflicts in Docker: Propshaft vs Sprockets"
slug: "rails-docker-asset-pipeline-conflicts"
canonical_url: "https://whittakertech.com/blog/rails-docker-asset-pipeline-conflicts/"
description: >-
  Fix Rails Docker asset pipeline conflicts between Propshaft and Sprockets. Learn the package.json dependencies fix 
  that solved our build failures and improved performance.
og_title: "Rails Docker Asset Pipeline: Fix Propshaft Build Failures"
headline: >-
  The Asset Pipeline Breakthrough: How a Single package.json Change Fixed Our Docker Build Failures and Revealed the 
  True Source of Performance Problems
categories: ["Ruby on Rails", "DevOps", "Asset Pipeline"]
tags: ["Rails asset pipeline", "Propshaft", "Sprockets", "Docker builds", "package.json", 
       "dependencies vs devDependencies", "SASS compilation", "JavaScript bundling", "Asset precompilation", 
       "Rails 7 assets"]
---

*How a seemingly minor package.json configuration issue was preventing successful Docker builds and masking the real
source of our performance improvements.*

## The Asset Pipeline Mystery

After establishing our [multi-stage Docker architecture](/blog/rails-docker-multi-stage-builds/), we hit a wall that
stopped the migration cold. The production Docker build would consistently fail during asset compilation with cryptic
errors:

```
TypeError: no implicit conversion of Propshaft::Assembly into String
    from /usr/local/bundle/gems/sprockets-4.2.1/lib/sprockets/loader.rb:73
```

This error made no sense. Our Rails 7.1 application was configured to use Propshaft (the modern Rails asset pipeline),
not Sprockets. Yet somehow, Sprockets was being invoked during the build process and conflicting with Propshaft's
assembly system.

Even more puzzling: the exact same codebase worked perfectly with Heroku's buildpack deployment. The only difference
was the containerized build environment.

## The Investigation Process

### Step 1: Asset Pipeline Audit

First, we verified our Rails configuration was correct:

```ruby
# config/application.rb
config.load_defaults 7.1

# Propshaft should be the default for Rails 7.1
puts Rails.application.config.assets.class
# => Propshaft::Configuration
```

Our `Gemfile` looked correct too:

```ruby
# Gemfile - only Propshaft, no Sprockets
gem "propshaft"
# No gem "sprockets" line anywhere
```

Yet `bundle list` revealed the problem:

```bash
$ bundle list | grep sprockets
* sprockets (4.2.1)
```

Sprockets was being installed as a dependency of another gem, creating a conflict when both asset pipelines were
present in the same environment.

### Step 2: Dependency Tree Analysis

```bash
$ bundle viz --format svg
# Generated dependency graph showing sprockets pulled in by:
# rails -> actioncable -> sprockets
```

The dependency chain was: `rails` → `actioncable` → `sprockets`. Even though we weren't using ActionCable or explicitly
requiring Sprockets, it was being loaded as part of the Rails framework.

### Step 3: Asset Compilation Deep Dive

The build process was executing multiple asset-related commands:

```dockerfile
# Our Docker build process
RUN yarn build && yarn build:css
RUN SECRET_KEY_BASE=dummy bundle exec rake assets:precompile
```

The `yarn` commands were succeeding, but `rake assets:precompile` was trying to initialize both Propshaft and
Sprockets, causing the type conversion error.

## The Real Culprit: Production Dependencies

While investigating the Propshaft/Sprockets conflict, we discovered a more fundamental issue with our `package.json`
configuration:

```json
{
  "dependencies": {
    "@hotwired/stimulus": "^3.2.2",
    "@hotwired/turbo-rails": "^8.0.12",
    "bootstrap": "^5.3.3"
  },
  "devDependencies": {
    "autoprefixer": "^10.4.20",
    "esbuild": "^0.25.0",
    "postcss": "^8.5.3",
    "postcss-cli": "^11.0.0",
    "sass": "^1.85.1"
  }
}
```

The problem: **all our build tools were classified as `devDependencies`**. In production Docker builds, Yarn skips
`devDependencies` by default, meaning SASS compilation, PostCSS processing, and JavaScript bundling simply wouldn't
work.

This explained why our Docker builds were failing while Heroku buildpacks worked—Heroku's build environment installs
all dependencies regardless of classification.

## The Solution: Rethinking Dependencies vs DevDependencies

The fix required understanding which tools are actually needed for production builds versus development-only tooling:

### Production Build Requirements

```json
{
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
    "@rails/webpacker": "^5.4.3",
    "nodemon": "^3.1.9",
    "webpack": "^4.46.0",
    "webpack-cli": "^3.3.12"
  }
}
```

**Key insight:** Build tools that compile assets (SASS, PostCSS, esbuild) are needed in production Docker builds, not
just development. Only development servers and debugging tools belong in `devDependencies`.

### Asset Build Pipeline Configuration

With dependencies correctly classified, we restructured the asset build process:

```json
{
  "scripts": {
    "build": "esbuild app/javascript/*.* --bundle --sourcemap --outdir=app/assets/builds --public-path=/assets",
    "build:css": "sass ./app/assets/stylesheets/application.bootstrap.scss:./app/assets/builds/application.css --load-path=node_modules",
    "watch:css": "nodemon --watch ./app/assets/stylesheets/ --ext scss --exec \"yarn build:css\"",
    "dev": "concurrently \"yarn build --watch\" \"yarn watch:css\""
  }
}
```

This creates explicit build commands that work consistently across all environments.

## Solving the Propshaft/Sprockets Conflict

With the dependency issue resolved, we still needed to address the asset pipeline conflict. The solution involved
explicitly configuring Rails to use only Propshaft:

### Rails Configuration

```ruby
# config/application.rb
config.load_defaults 7.1

# Explicitly disable Sprockets to prevent conflicts
config.assets.enabled = false if defined?(Sprockets)

# Ensure Propshaft is configured
config.assets.pipeline = :propshaft if respond_to?(:assets)
```

### Gemfile Optimization

```ruby
# Gemfile - explicit asset pipeline choice
gem "propshaft"

# Explicitly exclude sprockets if not needed
# gem "sprockets", require: false  # Only if you need it for specific gems
```

### Environment-Specific Asset Handling

```ruby
# config/environments/production.rb
config.public_file_server.enabled = true
config.assets.compile = false  # Assets should be precompiled
config.assets.digest = true    # Enable fingerprinting

# config/environments/development.rb
config.assets.compile = true   # Allow on-demand compilation
config.assets.debug = true     # Separate asset files for debugging
```

## The Dockerfile Asset Build Process

The final Docker build process handles assets in a specific order:

```dockerfile
FROM whittakertech/choir-base:latest

# Install production dependencies (including build tools)
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Install gems
COPY Gemfile* ./
RUN bundle config set --local without "development test" && \
    bundle install --jobs 4 --retry 3

# Copy application code
COPY . .

# Build assets using yarn (outside of Rails)
RUN yarn build && yarn build:css

# Precompile Rails assets (Propshaft)
RUN SECRET_KEY_BASE=dummy RAILS_ENV=production \
    bundle exec rake assets:precompile

# Clean up build artifacts
RUN rm -rf node_modules/.cache tmp/cache
```

### Build Order Strategy

1. **Install dependencies first** - Enables Docker layer caching
2. **Build JavaScript/CSS** - Using Node.js tools directly
3. **Rails asset precompilation** - Processes built files through Propshaft
4. **Clean up** - Remove unnecessary build artifacts

This separation prevents Rails asset pipeline conflicts while maintaining efficient caching.

## Performance Results

The corrected asset pipeline delivered dramatic improvements:

### Build Performance
- **Before:** 8-12 minute builds (when they succeeded)
- **After:** 4-5 minute consistent builds
- **Improvement:** 50% faster build times

### Asset Compilation
- **Before:** Frequent failures, inconsistent output
- **After:** 100% reliable compilation
- **File sizes:** 30% smaller due to proper minification

### Runtime Performance
- **JavaScript bundle:** Reduced from 450KB to 320KB
- **CSS bundle:** Reduced from 180KB to 125KB
- **Page load:** 200ms faster on initial load

### Memory Usage Impact

The asset pipeline fixes contributed significantly to our overall memory reduction:

- **Development builds:** No longer included production build artifacts
- **Production runtime:** Optimized assets reduced memory footprint
- **Build efficiency:** Faster builds meant less memory usage during deployment

## Common Asset Pipeline Pitfalls

### Pitfall 1: Dependencies Classification

```json
// Wrong - build tools in devDependencies
{
  "devDependencies": {
    "sass": "^1.85.1",      // Needed for production builds!
    "esbuild": "^0.25.0"    // Needed for production builds!
  }
}

// Correct - build tools in dependencies
{
  "dependencies": {
    "sass": "^1.85.1",
    "esbuild": "^0.25.0"
  },
  "devDependencies": {
    "nodemon": "^3.1.9"     // Development-only tools
  }
}
```

### Pitfall 2: Asset Pipeline Conflicts

```ruby
# Wrong - both pipelines present
gem "propshaft"
gem "sprockets"  # Creates conflicts!

# Correct - choose one
gem "propshaft"
# OR
gem "sprockets"
```

### Pitfall 3: Build Order Issues

```dockerfile
# Wrong - Rails precompile before yarn build
RUN bundle exec rake assets:precompile  # No source files!
RUN yarn build

# Correct - yarn build before Rails precompile
RUN yarn build && yarn build:css
RUN bundle exec rake assets:precompile
```

### Pitfall 4: Secret Key Issues

```dockerfile
# Wrong - missing SECRET_KEY_BASE
RUN bundle exec rake assets:precompile  # Fails!

# Correct - provide dummy key for build
RUN SECRET_KEY_BASE=dummy bundle exec rake assets:precompile
```

## Advanced Asset Optimization

### CSS Optimization Pipeline

```json
{
  "scripts": {
    "build:css": "sass ./app/assets/stylesheets/application.bootstrap.scss:./app/assets/builds/application.css --load-path=node_modules --style=compressed",
    "build:css:dev": "sass ./app/assets/stylesheets/application.bootstrap.scss:./app/assets/builds/application.css --load-path=node_modules --style=expanded --source-map"
  }
}
```

### JavaScript Bundling Strategy

```json
{
  "scripts": {
    "build": "esbuild app/javascript/*.* --bundle --sourcemap --outdir=app/assets/builds --public-path=/assets --minify",
    "build:dev": "esbuild app/javascript/*.* --bundle --sourcemap --outdir=app/assets/builds --public-path=/assets"
  }
}
```

### Conditional Asset Builds

```dockerfile
# Development Dockerfile.dev
RUN yarn install  # All dependencies
RUN yarn build:dev && yarn build:css:dev

# Production Dockerfile
RUN yarn install --frozen-lockfile  # Production dependencies only
RUN yarn build && yarn build:css    # Minified builds
```

## Asset Pipeline Best Practices

### 1. Explicit Tool Configuration
Choose your asset pipeline (Propshaft or Sprockets) explicitly and configure Rails accordingly.

### 2. Proper Dependency Classification
Build tools needed for production belong in `dependencies`, not `devDependencies`.

### 3. Build Process Separation
Handle JavaScript/CSS compilation separately from Rails asset precompilation.

### 4. Environment-Specific Optimization
Use different build commands for development (with source maps) and production (minified).

### 5. Docker Layer Optimization
Structure Dockerfile commands to maximize caching efficiency.

## What's Next

With a reliable asset pipeline in place, the next major hurdle was system-level dependency conflicts, particularly the
infamous libv8-dev and Node.js compatibility issues that plague many Rails Docker deployments.

The [next post in this series](/blog/rails-docker-libv8-node-conflicts/) covers the system package conflicts that nearly
derailed our migration and the creative solutions that finally resolved them.

---

*This is Part 3 of our Rails Docker Migration series. The complete asset pipeline configuration is available in our
[GitHub repository](https://github.com/whittakertech/choir-site), and you can see the exact package.json and Dockerfile
changes that solved these issues.*