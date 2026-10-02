#!/usr/bin/env ruby
# frozen_string_literal: true

# Validates the built blog in _site against the image and metadata contract:
#   - one <title>, canonical, og:title, og:description and og:image (with size + alt) per post
#   - title contract: <title> and JSON-LD headline use title; OG/Twitter use og_title || title;
#     the breadcrumb's current page is card_title || title
#   - summary_large_image Twitter card, exactly one BlogPosting JSON-LD block
#   - manifest originals are never served (pending images must use the fallback)
#   - no malformed image URLs (e.g. "https://site.comhttps://media...")
#   - local image URLs exist in _site; fallback asset exists
#   - unique OG titles and descriptions across posts
#   - the homepage mission image (resolved by _plugins/site_images.rb) serves only
#     versioned processed URLs, matching its data-image-version, and never an original
#   - series posts render their badge; blog index carries no full-content payload
#
# Usage: ruby scripts/check_blog_output.rb [site_dir]
# Set CHECK_REMOTE=1 to also request every remote image URL (posts + manifest).

require "cgi"
require "json"
require "net/http"
require "uri"
require "yaml"
require "date"

SITE_DIR = ARGV[0] || "_site"
SITE_URL = YAML.safe_load_file("_config.yml", permitted_classes: [Date])["url"]
MALFORMED = %r{https?://[^"'\s<>]*https?://}

errors = []
remote_urls = []

def front_matter(path)
  YAML.safe_load(File.read(path)[/\A---\n(.*?)\n---/m, 1], permitted_classes: [Date, Time])
end

def metas(html, name)
  html.scan(/<meta (?:name|property)="#{Regexp.escape(name)}" content="([^"]*)"/).flatten
end

def unescape(text)
  CGI.unescapeHTML(text.to_s)
end

def local_path(url)
  return unless url.start_with?(SITE_URL) || url.start_with?("/")

  File.join(SITE_DIR, URI(url).path)
end

manifest = YAML.safe_load_file("_data/images.yml")
fallback = manifest.dig("fallback", "og", "url")
if fallback.nil? || !File.exist?(File.join(".", fallback))
  errors << "fallback OG image #{fallback.inspect} is missing from the repository"
end

titles = Hash.new { |h, k| h[k] = [] }
descriptions = Hash.new { |h, k| h[k] = [] }

Dir["_posts/*.md"].sort.each do |source|
  fm = front_matter(source)
  page = File.join(SITE_DIR, "blog", fm["slug"], "index.html")
  unless File.exist?(page)
    errors << "#{source}: built page #{page} not found"
    next
  end
  html = File.read(page)
  label = fm["slug"]

  canonicals = html.scan(/<link rel="canonical" href="([^"]*)"/).flatten
  errors << "#{label}: #{canonicals.size} canonical links" unless canonicals.size == 1
  errors << "#{label}: canonical #{canonicals.first} != #{fm['canonical_url']}" if canonicals.first != fm["canonical_url"]

  %w[og:title og:description og:image og:image:width og:image:height og:image:alt
     twitter:card twitter:title twitter:image].each do |name|
    found = metas(html, name).size
    errors << "#{label}: #{found} #{name} tags (expected 1)" unless found == 1
  end

  page_titles = html.scan(%r{<title>([^<]*)</title>}).flatten
  errors << "#{label}: #{page_titles.size} <title> tags" unless page_titles.size == 1
  unless unescape(page_titles.first).start_with?(fm["title"])
    errors << "#{label}: <title> #{page_titles.first.inspect} does not use title"
  end
  social = fm["og_title"] || fm["title"]
  %w[og:title twitter:title].each do |name|
    value = unescape(metas(html, name).first)
    errors << "#{label}: #{name} #{value.inspect} != og_title/title #{social.inspect}" unless value == social
  end
  crumb = html[%r{<nav aria-label="Breadcrumb".*?</nav>}m].to_s[%r{aria-current="page">([^<]*)<}, 1]
  expected_crumb = fm["card_title"] || fm["title"]
  errors << "#{label}: breadcrumb current #{crumb.inspect} != #{expected_crumb.inspect}" unless unescape(crumb) == expected_crumb

  card = metas(html, "twitter:card")
  errors << "#{label}: twitter:card is #{card.inspect}" unless card == ["summary_large_image"]

  og_image = metas(html, "og:image").first.to_s
  width, height = %w[og:image:width og:image:height].map { |n| metas(html, n).first.to_i }
  errors << "#{label}: og:image is #{width}x#{height}, expected 1200x630" unless [width, height] == [1200, 630]
  if (path = local_path(og_image))
    errors << "#{label}: og:image #{og_image} not found at #{path}" unless File.exist?(path)
  else
    remote_urls << og_image
  end

  html.scan(MALFORMED).each { |bad| errors << "#{label}: malformed URL near #{bad.inspect}" }

  blocks = html.scan(%r{<script type="application/ld\+json">(.*?)</script>}m).flatten
  parsed = blocks.filter_map do |raw|
    JSON.parse(raw)
  rescue JSON::ParserError => e
    errors << "#{label}: invalid JSON-LD (#{e.message[0, 80]})"
    nil
  end
  articles = parsed.select { |b| b["@type"] == "BlogPosting" }
  errors << "#{label}: #{articles.size} BlogPosting schemas (expected 1)" unless articles.size == 1
  if (article = articles.first)
    image = article["image"].is_a?(Hash) ? article["image"]["url"] : article["image"]
    errors << "#{label}: JSON-LD image #{image.inspect} != og:image" unless image == og_image
    errors << "#{label}: JSON-LD headline #{article['headline'].inspect} != title" unless article["headline"] == fm["title"]
  end

  titles[metas(html, "og:title").first] << label
  descriptions[metas(html, "og:description").first] << label

  if fm["series"]
    expected = fm["series_role"] == "reference" ? "Companion reference" : "Part #{fm['series_part']} of"
    errors << "#{label}: series fields incomplete" unless fm["series_part"] || fm["series_role"] == "reference"
    errors << "#{label}: missing series badge '#{expected}'" unless html.include?(%(series-badge">#{expected}))
    errors << "#{label}: missing series navigation" unless html.include?('class="series-nav"')
  end

  hero = html[%r{<figure class="article-hero.*?</figure>}m]
  errors << "#{label}: hero image lacks intrinsic dimensions" if hero && hero !~ /<img[^>]+width="\d+"[^>]+height="\d+"/m
end

titles.each { |t, pages| errors << "duplicate og:title #{t.inspect}: #{pages.join(', ')}" if pages.size > 1 }
descriptions.each { |d, pages| errors << "duplicate og:description on #{pages.join(', ')}" if pages.size > 1 && d }

originals = manifest.values.filter_map { |entry| entry.dig("original", "url") }
Dir[File.join(SITE_DIR, "**", "*.html")].each do |page|
  html = File.read(page)
  originals.each { |url| errors << "#{page}: serves original #{url}" if html.include?(url) }
end

Dir[File.join(SITE_DIR, "blog", "{index.html,page/*/index.html}")].each do |index|
  html = File.read(index)
  errors << "#{index}: contains data-content payload" if html.include?("data-content=")
  html.scan(MALFORMED).each { |bad| errors << "#{index}: malformed URL near #{bad.inspect}" }
end

# --- Site images (homepage mission image) ---------------------------------------
SITE_PROCESSED = "https://media.whittakertech.com/whittakertech/site/processed/"
site_image_urls = []
home = File.join(SITE_DIR, "index.html")
if File.exist?(home)
  home_html = File.read(home)
  mission = home_html[%r{<img\b[^>]*data-image-version[^>]*>}m]
  if mission.nil?
    errors << "index.html: mission <img> with data-image-version not found"
  else
    version = mission[/data-image-version="([^"]*)"/, 1].to_s
    errors << "index.html: data-image-version #{version.inspect} is not a positive integer" unless version.match?(/\A[1-9]\d*\z/)
    srcs = [mission[/\ssrc="([^"]*)"/, 1]] + mission[/\ssrcset="([^"]*)"/, 1].to_s.split(",").map { |c| c.strip.split(/\s+/).first }
    errors << "index.html: mission <img> has no src/srcset" if srcs.compact.empty?
    srcs.each do |url|
      if url.nil? || url.empty?
        errors << "index.html: mission <img> has an empty src/srcset URL"
        next
      end
      site_image_urls << url
      errors << "index.html: mission image #{url} is not under #{SITE_PROCESSED}" unless url.start_with?(SITE_PROCESSED)
      errors << "index.html: mission image #{url} has a query string" if url.include?("?")
      errors << "index.html: malformed mission image URL #{url}" if url.match?(MALFORMED)
      errors << "index.html: mission image #{url} is not under /v#{version}/" unless url.include?("/v#{version}/")
    end
  end
  site_originals = YAML.safe_load_file("_data/site_images.yml").values.filter_map { |entry| entry.dig("original", "url") }
  site_originals.each { |url| errors << "index.html serves original #{url}" if home_html.include?(url) }
  errors << "index.html serves a site-image original (#{home_html[%r{[^"'\s]*/whittakertech/site/originals/[^"'\s]*}]})" if home_html.include?("/whittakertech/site/originals/")
else
  errors << "#{home} not found"
end

if ENV["CHECK_REMOTE"] == "1"
  remote_urls.concat(site_image_urls)
  manifest.each_value do |entry|
    remote_urls << entry.dig("original", "url")
    (entry["variants"] || {}).each_value { |formats| formats.each_value { |list| list.each { |v| remote_urls << v["url"] } } }
    remote_urls << entry.dig("og", "url")
  end
  remote_urls.compact.uniq.grep(%r{\Ahttps?://}).each do |url|
    response = Net::HTTP.start(URI(url).host, use_ssl: url.start_with?("https")) { |h| h.head(URI(url).request_uri) }
    errors << "unreachable image #{url} (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
  rescue StandardError => e
    errors << "unreachable image #{url} (#{e.class})"
  end
end

if errors.empty?
  puts "✅ Blog output checks passed (#{Dir['_posts/*.md'].size} posts)"
else
  puts errors.map { |e| "❌ #{e}" }
  exit 1
end
