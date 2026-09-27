FROM ruby:3.2-alpine

# Install dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    gcompat

WORKDIR /app

# Install specific versions to avoid conflicts
RUN gem update --system && \
    gem install jekyll:4.3.3 bundler:2.5.6

# Tailwind CSS and its plugins come from package.json (npm install)

EXPOSE 4000

# CMD ["bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0", "--livereload"]
# Enhanced CMD that builds Tailwind CSS and starts Jekyll
CMD ["sh", "-c", "npm install && npm run build:css-prod && bundle exec jekyll serve --host 0.0.0.0 --livereload --incremental"]
