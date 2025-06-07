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

# Install Tailwind CSS and dependencies
RUN npm install -g @tailwindcss/cli@latest \
    @tailwindcss/typography@latest \
    @tailwindcss/forms@latest \
    @tailwindcss/aspect-ratio@latest \
    @tailwindcss/language-server


EXPOSE 4000

# CMD ["bundle", "exec", "jekyll", "serve", "--host", "0.0.0.0", "--livereload"]
# Enhanced CMD that builds Tailwind CSS and starts Jekyll
CMD ["sh", "-c", "npm run build:css && bundle exec jekyll serve --host 0.0.0.0 --livereload --incremental"]
