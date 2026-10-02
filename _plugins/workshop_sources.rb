# Builds the About page's workshop roster from the organization's public
# GitHub repositories at build time.
#
# The rubric for what WhittakerTech names publicly is simple: a project
# appears only if its GitHub repository is public. Rather than trusting a
# hand-kept list, this generator asks GitHub which repositories are public
# and builds the roster from that answer. A repository that goes public shows
# up on the next build; one that goes private or is archived disappears.
#
# _data/workshop.yml adds presentation for repositories that are already
# public (display name, family, tagline) and lists repositories to leave out
# (site infrastructure). Never name a private repository in that file: this
# site's source is public too.
#
# Results land in site.data.workshop_entries, newest activity first:
#
#   name, repo, url, tagline, family, released, version, latest_release_at,
#   product_url, last_push_at
#
# "Released" means the repository has a product page whose stats report a
# published version (see ProductSources).
#
# The roster fails closed: if GitHub can't be reached, the list is empty and
# the section hides itself, so nothing unverified is ever published.
#
# For local development without network access, point WORKSHOP_FIXTURE at a
# JSON file shaped like GitHub's repository list.
require "json"
require "net/http"
require "time"
require "uri"

module WhittakerTech
  class WorkshopSources < Jekyll::Generator
    safe true
    # Runs after ProductSources (:highest), which it reads release data from.
    priority :high

    GITHUB_API = "https://api.github.com".freeze
    CACHE = {}

    def generate(site)
      config = site.data["workshop"] || {}
      org = config["organization"] || "whittakertech"
      excluded = Array(config["exclude"])
      projects = config["projects"] || {}
      products = site.data["products"] || {}

      repos = public_repos(org).reject do |repo|
        repo["private"] || repo["archived"] || repo["fork"] || excluded.include?(repo["name"])
      end

      site.data["workshop_entries"] = repos.map do |repo|
        entry(repo, projects[repo["name"]] || {}, products, site)
      end.sort_by { |e| [-(e["last_push_at"] ? Time.parse(e["last_push_at"]).to_f : 0), e["name"]] }
    end

    private

    def entry(repo, project, products, site)
      slug = project["product"] || repo["name"]
      stats = products.dig(slug, "stats") || {}
      product_doc = site.collections["products"]&.docs&.find do |doc|
        (doc.data["slug"] || doc.basename_without_ext) == slug
      end

      {
        "name" => project["name"] || repo["name"],
        "repo" => repo["full_name"],
        "url" => repo["html_url"],
        "tagline" => project["tagline"] || repo["description"],
        "family" => project["family"],
        "released" => !stats["version"].nil?,
        "version" => stats["version"],
        "latest_release_at" => stats["latest_release_at"],
        "product_url" => product_doc&.url,
        "last_push_at" => repo["pushed_at"]
      }
    end

    def public_repos(org)
      if (fixture = ENV["WORKSHOP_FIXTURE"])
        return JSON.parse(File.read(fixture))
      end

      url = "#{GITHUB_API}/orgs/#{URI.encode_www_form_component(org)}/repos?type=public&per_page=100"
      return CACHE[url] if CACHE.key?(url)

      CACHE[url] = fetch(url)
    end

    def fetch(url)
      uri = URI(url)
      request = Net::HTTP::Get.new(uri)
      request["Accept"] = "application/vnd.github+json"
      request["User-Agent"] = "whittakertech-jekyll"
      token = ENV["GITHUB_TOKEN"]
      request["Authorization"] = "Bearer #{token}" if token && !token.empty?

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
        http.request(request)
      end

      unless response.is_a?(Net::HTTPSuccess)
        Jekyll.logger.warn "WorkshopSources:", "#{url} returned #{response.code}; hiding the workshop roster"
        return []
      end

      data = JSON.parse(response.body)
      data.is_a?(Array) ? data : []
    rescue StandardError => e
      Jekyll.logger.warn "WorkshopSources:", "#{url} failed (#{e.class}: #{e.message}); hiding the workshop roster"
      []
    end
  end
end
