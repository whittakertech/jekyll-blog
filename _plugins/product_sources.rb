# Fetches live RubyGems and GitHub data for products at build time.
#
# A product declares its sources in front matter:
#
#   sources:
#     rubygems: whittaker_tech-midas
#     github: whittakertech/midas
#
# and templates read the results from site.data.products[<slug>].
#
# Templates should use the provider-independent `stats` hash, so a product
# backed by a different registry renders with the same markup:
#
#   stats.version            - current release number
#   stats.downloads          - total downloads
#   stats.latest_release_at  - when the current release was published
#   stats.first_release_at   - when the first release was published
#   stats.release_count      - number of (non-yanked) releases
#   stats.stars              - GitHub stargazers
#   stats.last_push_at       - last push to the GitHub repository
#
# The raw API payloads are kept alongside for anything stats doesn't cover:
#
#   rubygems           - https://rubygems.org/api/v1/gems/<gem>.json
#   rubygems_versions  - https://rubygems.org/api/v1/versions/<gem>.json
#   github             - https://api.github.com/repos/<owner>/<repo>
#
# Homepage orderings (newest, latest_update, top_downloads) are published to
# site.data.product_rankings; see #rankings.
#
# A failed fetch logs a warning and leaves that value nil, so an API outage
# never blocks publishing. Set GITHUB_TOKEN to avoid GitHub's anonymous
# rate limit.
require "json"
require "net/http"
require "time"
require "uri"

module WhittakerTech
  class ProductSources < Jekyll::Generator
    safe true
    priority :highest

    RUBYGEMS_API = "https://rubygems.org/api/v1".freeze
    GITHUB_API = "https://api.github.com".freeze

    # Memoized per process, failures included, so `jekyll serve` regenerations
    # don't re-hit the APIs. Restart the server to refetch.
    CACHE = {}

    def generate(site)
      products = site.collections["products"]
      return unless products

      site.data["products"] ||= {}
      entries = []

      products.docs.each do |doc|
        sources = doc.data["sources"]
        next unless sources.is_a?(Hash)

        slug = doc.data["slug"] || doc.basename_without_ext
        data = fetch_sources(sources)
        site.data["products"][slug] = data

        entries << {
          "slug" => slug,
          "title" => doc.data["title"],
          "tagline" => doc.data["tagline"],
          "url" => doc.url,
          "stats" => data["stats"]
        }
      end

      site.data["product_rankings"] = rankings(entries)
    end

    private

    # Homepage orderings, computed from stats. Products missing the relevant
    # stat are left out; ties break by slug so builds are deterministic.
    #
    #   newest         - latest first_release_at
    #   latest_update  - latest latest_release_at
    #   top_downloads  - up to TOP_DOWNLOADS entries, most downloads first
    TOP_DOWNLOADS = 5

    def rankings(entries)
      {
        "newest" => latest_by(entries, "first_release_at"),
        "latest_update" => latest_by(entries, "latest_release_at"),
        "top_downloads" => entries
          .select { |entry| entry["stats"]["downloads"] }
          .sort_by { |entry| [-entry["stats"]["downloads"], entry["slug"]] }
          .first(TOP_DOWNLOADS)
      }
    end

    def latest_by(entries, stat)
      entries
        .select { |entry| entry["stats"][stat] }
        .min_by { |entry| [-Time.parse(entry["stats"][stat]).to_f, entry["slug"]] }
    end

    def fetch_sources(sources)
      data = {}

      if (gem = sources["rubygems"])
        name = URI.encode_www_form_component(gem)
        data["rubygems"] = fetch("#{RUBYGEMS_API}/gems/#{name}.json")
        data["rubygems_versions"] = fetch("#{RUBYGEMS_API}/versions/#{name}.json")
      end

      if (repo = sources["github"])
        data["github"] = fetch("#{GITHUB_API}/repos/#{repo}", github_headers)
      end

      data["stats"] = stats(data)
      data
    end

    def stats(data)
      gem = data["rubygems"] || {}
      github = data["github"] || {}
      releases = Array(data["rubygems_versions"]).reject { |version| version["yanked"] }

      {
        "version" => gem["version"],
        "downloads" => gem["downloads"],
        "latest_release_at" => gem["version_created_at"],
        "first_release_at" => releases.min_by { |version| Time.parse(version["created_at"]) }&.dig("created_at"),
        "release_count" => data["rubygems_versions"] && releases.length,
        "stars" => github["stargazers_count"],
        "last_push_at" => github["pushed_at"]
      }
    end

    def fetch(url, headers = {})
      # Authenticated and anonymous responses are cached separately; the key
      # records only whether a token was sent, never the token itself.
      key = headers.key?("Authorization") ? "#{url} (authenticated)" : url
      return CACHE[key] if CACHE.key?(key)

      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/json"
      request["User-Agent"] = "whittakertech-jekyll"
      headers.each { |name, value| request[name] = value }

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Jekyll.logger.warn "ProductSources:", "#{response.code} fetching #{url}"
        return CACHE[key] = nil
      end

      CACHE[key] = JSON.parse(response.body)
    rescue StandardError => e
      Jekyll.logger.warn "ProductSources:", "#{e.class} fetching #{url}: #{e.message}"
      CACHE[key] = nil
    end

    def github_headers
      token = ENV["GITHUB_TOKEN"].to_s
      token.empty? ? {} : { "Authorization" => "Bearer #{token}" }
    end
  end
end
