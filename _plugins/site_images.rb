# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module WhittakerTech
  # Resolves site-only imagery (_data/site_images.yml) against the media bucket's
  # mutable manifest pointers at build time, so a newly published version renders
  # without hand-editing the snapshot.
  #
  # _data/site_image_sources.yml lists the keys to resolve (key => options, only
  # `pin: <N>` is accepted). For each listed key the build fetches
  #   https://media.whittakertech.com/whittakertech/site/manifests/<key>/current.json
  # (or .../v<pin>.json when pinned), validates it, and replaces
  # site.data["site_images"][<key>]. Every URL in a manifest is immutable and
  # versioned, so a new version is a new URL and can never be served stale.
  #
  # Unlike WorkshopSources/ProductSources this FAILS OPEN: on any fetch or
  # validation failure the committed snapshot entry is kept and a warning is
  # logged, because an image must never disappear from the page.
  #
  # Resolved entries carry two extra keys for templates and logs:
  #   "version"  Integer (or nil when unparseable from a snapshot)
  #   "source"   "live", "pinned" or "snapshot"
  #
  # SITE_IMAGES_FIXTURE=<dir> reads <dir>/<key>/current.json and
  # <dir>/<key>/v<N>.json instead of the network (tests); a missing file is a
  # fetch failure.
  class SiteImages < Jekyll::Generator
    safe true
    priority :high

    HOST = "media.whittakertech.com"
    PREFIX = "https://#{HOST}/whittakertech/site/".freeze
    MANIFESTS = "#{PREFIX}manifests/".freeze
    URL = %r{\A(?:https://[^/\s"'<>]+|/(?!/))[^\s"'<>]*\z}
    FORMATS = %w[webp jpeg png].freeze
    RATIO_TOLERANCE = 0.01
    MAX_BYTES = 64 * 1024
    TIMEOUT = 5
    OPTIONS = %w[pin].freeze
    DROPPED_ORIGINAL = %w[sha256].freeze
    KEPT = %w[alt focal credit].freeze

    CACHE = {}

    class FetchError < StandardError; end

    def generate(site)
      sources = site.data["site_image_sources"]
      return if sources.nil?

      fail!("_data/site_image_sources.yml must be a mapping of image key to options") unless sources.is_a?(Hash)
      options = sources.to_h { |key, opts| [key.to_s, validate_options(key.to_s, opts)] }
      images = (site.data["site_images"] ||= {})

      options.each do |key, opts|
        entry = CACHE[[key, opts["pin"], ENV["SITE_IMAGES_FIXTURE"]]] ||= resolve(key, opts, images[key])
        images[key] = entry
        Jekyll.logger.info "SiteImages:", "#{key} v#{entry['version'] || '?'} (#{entry['source']})"
      end
    end

    private

    # --- Options ------------------------------------------------------------

    def validate_options(key, opts)
      return {} if opts.nil?

      fail!("#{key}: options must be a mapping, got #{opts.inspect}") unless opts.is_a?(Hash)
      unknown = opts.keys.map(&:to_s) - OPTIONS
      fail!("#{key}: unknown option(s) #{unknown.join(', ')} (allowed: #{OPTIONS.join(', ')})") if unknown.any?
      pin = opts["pin"]
      if opts.key?("pin") && !(pin.is_a?(Integer) && pin.positive?)
        fail!("#{key}: pin must be a positive integer, got #{pin.inspect}")
      end
      { "pin" => pin }
    end

    # --- Resolution ---------------------------------------------------------

    def resolve(key, opts, snapshot)
      pin = opts["pin"]
      path = "#{key}/#{pin ? "v#{pin}" : 'current'}.json"
      manifest = parse(fetch(path), path)
      validate(key, manifest, pin)
      map(manifest, pin ? "pinned" : "live")
    rescue FetchError, ValidationError => e
      Jekyll.logger.warn "SiteImages:", "#{key}: #{MANIFESTS}#{path} unusable (#{e.message}); keeping committed snapshot"
      fallback(key, snapshot, e)
    end

    def fallback(key, snapshot, error)
      unless snapshot.is_a?(Hash)
        fail!("#{key}: no snapshot in _data/site_images.yml and the manifest could not be resolved (#{error.message})")
      end
      entry = Marshal.load(Marshal.dump(snapshot))
      entry["version"] = snapshot.to_s[%r{/processed/#{Regexp.escape(key)}/v(\d+)/}, 1]&.to_i
      entry["source"] = "snapshot"
      entry
    end

    def map(manifest, source)
      entry = {}
      entry["original"] = manifest["original"].reject { |k, _| DROPPED_ORIGINAL.include?(k) }
                                              .slice("url", "width", "height")
      entry["variants"] = manifest["variants"]
      KEPT.each { |field| entry[field] = manifest[field] if manifest.key?(field) }
      entry["version"] = manifest["version"]
      entry["source"] = source
      entry
    end

    # --- Fetch --------------------------------------------------------------

    def fetch(path)
      fixture = ENV["SITE_IMAGES_FIXTURE"]
      return read_fixture(File.join(fixture, path)) if fixture && !fixture.empty?

      uri = URI("#{MANIFESTS}#{path}")
      raise FetchError, "refusing non-media URL" unless uri.scheme == "https" && uri.host == HOST

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = http.read_timeout = TIMEOUT
      request = Net::HTTP::Get.new(uri.request_uri, "Accept" => "application/json", "User-Agent" => "whittakertech-site-build")
      body = +""
      http.request(request) do |response|
        raise FetchError, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        response.read_body do |chunk|
          body << chunk
          raise FetchError, "body exceeds #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
        end
      end
      body
    rescue SystemCallError, SocketError, Timeout::Error, IOError, OpenSSL::SSL::SSLError, Net::ProtocolError => e
      raise FetchError, "#{e.class}: #{e.message}"
    end

    def read_fixture(file)
      raise FetchError, "fixture #{file} not found" unless File.file?(file)
      raise FetchError, "body exceeds #{MAX_BYTES} bytes" if File.size(file) > MAX_BYTES

      File.read(file)
    end

    def parse(body, path)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise FetchError, "invalid JSON in #{path} (#{e.message[0, 60]})"
    end

    # --- Validation ---------------------------------------------------------

    class ValidationError < StandardError; end

    def validate(key, manifest, pin)
      bad("manifest must be a mapping") unless manifest.is_a?(Hash)
      bad("manifest key #{manifest['key'].inspect} != #{key}") unless manifest["key"] == key
      version = manifest["version"]
      bad("version must be a positive integer, got #{version.inspect}") unless version.is_a?(Integer) && version.positive?
      bad("version #{version} != pin #{pin}") if pin && version != pin

      original = manifest["original"]
      validate_image("original", original, "#{PREFIX}originals/")
      variants = manifest["variants"]
      bad("variants must be a non-empty mapping") unless variants.is_a?(Hash) && variants.any?
      root = "#{PREFIX}processed/#{key}/v#{version}/"
      variants.each { |name, formats| validate_set(name, formats, root) }
    end

    def validate_set(name, formats, root)
      where = "variants.#{name}"
      bad("#{where} must map formats to lists") unless formats.is_a?(Hash) && formats.any?
      ratio = nil
      formats.each do |format, list|
        bad("#{where}: unsupported format '#{format}'") unless FORMATS.include?(format)
        bad("#{where}.#{format} must be a non-empty list") unless list.is_a?(Array) && list.any?
        list.each_with_index { |image, i| validate_image("#{where}.#{format}[#{i}]", image, root) }
        widths = list.map { |image| image["width"] }
        bad("#{where}.#{format} widths must ascend: #{widths.inspect}") unless widths == widths.sort.uniq

        list.each do |image|
          r = image["width"].to_f / image["height"]
          ratio ||= r
          next if (r - ratio).abs / ratio <= RATIO_TOLERANCE

          bad("#{where}: #{image['url']} is #{image['width']}x#{image['height']}, inconsistent aspect ratio")
        end
      end
    end

    def validate_image(where, image, root)
      bad("#{where} must be a mapping with url, width and height") unless image.is_a?(Hash)
      url = image["url"]
      bad("#{where} has an unusable url #{url.inspect}") unless url.is_a?(String) && url.match?(URL)
      bad("#{where} url #{url} must start with #{PREFIX}") unless url.start_with?(PREFIX)
      bad("#{where} url #{url} must be under #{root}") unless url.start_with?(root)
      %w[width height].each do |dim|
        value = image[dim]
        bad("#{where} needs a positive integer #{dim}, got #{value.inspect}") unless value.is_a?(Integer) && value.positive?
      end
    end

    def bad(message)
      raise ValidationError, message
    end

    def fail!(message)
      raise Jekyll::Errors::FatalException, "site_images: #{message}"
    end
  end
end
