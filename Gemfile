source "https://rubygems.org"

gem "github-pages", group: :jekyll_plugins

gem 'foreman'

# GitHub Pages doesn't allow custom plugins, so these are included:
# jekyll-feed, jekyll-sitemap, jekyll-seo-tag are already included in github-pages

# Windows and JRuby does not include zoneinfo files
platforms :mingw, :x64_mingw, :mswin, :jruby do
  gem "tzinfo", ">= 1", "< 3"
  gem "tzinfo-data"
end

# Performance-booster for watching directories on Windows
gem "wdm", "~> 0.1.1", :platforms => [:mingw, :x64_mingw, :mswin]

# Add webrick for Ruby 3.0+
gem "webrick", "~> 1.7"