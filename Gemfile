source "https://rubygems.org"

# Built and deployed by our own workflow (.github/workflows/deploy.yml), not the
# github-pages gem, so we control the Jekyll version and can use any plugin.
gem "jekyll", "~> 4.4"

gem 'foreman'

group :jekyll_plugins do
  gem 'jekyll-feed'
  gem 'jekyll-paginate'
  gem 'jekyll-seo-tag'
  gem 'jekyll-sitemap'
end

# Windows and JRuby does not include zoneinfo files
platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem "tzinfo", ">= 1", "< 3"
  gem "tzinfo-data"
end

# Performance-booster for watching directories on Windows
gem "wdm", "~> 0.1.1", :platforms => [:mingw, :x64_mingw, :mswin]

# Add webrick for Ruby 3.0+
gem "webrick", "~> 1.7"
