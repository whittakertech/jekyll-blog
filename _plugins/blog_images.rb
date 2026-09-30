# frozen_string_literal: true

module WhittakerTech
  # Resolves each post's image against _data/images.yml and its series against
  # _data/series.yml before rendering. Templates read:
  #
  #   post.data["image_asset"]  manifest entry plus "key", "fallback" and "pending"
  #   post.data["image"]        { path, width, height, alt } for OG, Twitter and JSON-LD
  #   post.data["series_info"]  { title, role, part, total, previous, next, reference, parts }
  #
  # Entries without processed variants are "pending": they render the fallback
  # artwork, because originals are full-size sources and never served directly.
  # A malformed manifest, an unknown image_key or a broken series fails the build.
  class BlogImages < Jekyll::Generator
    safe true
    priority :normal

    URL = %r{\A(?:https://[^/\s"'<>]+|/(?!/))[^\s"'<>]*\z}
    OG_FORMAT = /\.(?:jpe?g|png)\z/i
    VARIANT_FORMATS = %w[jpeg webp png].freeze
    RATIO_TOLERANCE = 0.01

    def generate(site)
      images = site.data.fetch("images", {})
      validate_manifest(images)
      fallback = images["fallback"]

      site.posts.docs.each { |post| resolve_image(post, images, fallback) }
      resolve_series(site)
    end

    private

    # --- Manifest -----------------------------------------------------------

    def validate_manifest(images)
      fallback = images["fallback"] || fail!("_data/images.yml has no 'fallback' entry")
      fail!("fallback has no og image") unless fallback["og"]

      images.each do |key, entry|
        fail!("#{key}: entry must be a mapping") unless entry.is_a?(Hash)
        validate_image(key, "og", entry["og"], format: OG_FORMAT) if entry["og"]
        next if key == "fallback"

        fail!("#{key}: needs an original or processed variants") unless entry["original"] || entry["variants"]
        validate_image(key, "original", entry["original"]) if entry["original"]
        (entry["variants"] || {}).each { |variant, formats| validate_variant(key, variant, formats) }
      end
    end

    def validate_variant(key, variant, formats)
      where = "#{key}: variants.#{variant}"
      fail!("#{where} must map formats to lists") unless formats.is_a?(Hash)
      fail!("#{where} needs a jpeg list as the <img> fallback") unless formats["jpeg"].is_a?(Array) && formats["jpeg"].any?

      ratio = nil
      formats.each do |format, list|
        fail!("#{where}: unsupported format '#{format}'") unless VARIANT_FORMATS.include?(format)
        fail!("#{where}.#{format} must be a non-empty list") unless list.is_a?(Array) && list.any?

        list.each_with_index { |image, i| validate_image(key, "variants.#{variant}.#{format}[#{i}]", image) }
        widths = list.map { |image| image["width"] }
        fail!("#{where}.#{format} widths must ascend: #{widths.inspect}") unless widths == widths.sort.uniq

        list.each do |image|
          r = image["width"].to_f / image["height"]
          ratio ||= r
          next if (r - ratio).abs / ratio <= RATIO_TOLERANCE

          fail!("#{where}: #{image['url']} is #{image['width']}x#{image['height']}, " \
                "inconsistent with the set's #{ratio.round(3)} aspect ratio")
        end
      end
    end

    def validate_image(key, field, image, format: nil)
      where = "#{key}: #{field}"
      fail!("#{where} must be a mapping with url, width and height") unless image.is_a?(Hash)
      url = image["url"]
      fail!("#{where} has an unusable url #{url.inspect}") unless url.is_a?(String) && url.match?(URL)
      fail!("#{where} must be JPEG or PNG (#{url})") if format && !URI(url).path.match?(format)
      %w[width height].each do |dim|
        value = image[dim]
        fail!("#{where} needs a positive integer #{dim}, got #{value.inspect}") unless value.is_a?(Integer) && value.positive?
      end
    end

    # --- Posts --------------------------------------------------------------

    def resolve_image(post, images, fallback)
      key = post.data["image_key"]
      entry =
        if key
          images[key] || fail!("#{post.relative_path}: image_key '#{key}' is not in _data/images.yml")
        elsif post.data["hero_image"]
          # Legacy path: a pre-sized image referenced directly from front matter.
          { "original" => { "url" => post.data["hero_image"] }, "variants" => {}, "alt" => post.data["hero_image_alt"] }
        end

      legacy = entry && key.nil?
      processed = entry && entry["variants"].is_a?(Hash) && entry["variants"].any?
      usable = legacy || processed
      asset =
        if usable
          entry.merge("key" => key, "fallback" => false)
        else
          fallback.merge("key" => "fallback", "fallback" => true, "pending" => key)
        end
      post.data["image_asset"] = asset
      post.data["image"] ||= social_image(usable ? entry : nil, fallback)
    end

    def social_image(entry, fallback)
      source = entry&.dig("og") ? entry : fallback
      og = source["og"]
      { "path" => og["url"], "width" => og["width"], "height" => og["height"], "alt" => source["alt"].to_s }
    end

    # --- Series -------------------------------------------------------------

    def resolve_series(site)
      site.posts.docs.select { |p| p.data["series"] }.group_by { |p| p.data["series"] }.each do |slug, members|
        meta = site.data.dig("series", slug) || fail!("series '#{slug}' is not in _data/series.yml")
        references, parts = members.partition { |p| p.data["series_role"] == "reference" }
        parts.each { |p| validate_part(p) }
        parts.sort_by! { |p| p.data["series_part"] }
        check_sequence(slug, parts, meta["total"])
        fail!("series '#{slug}' has more than one reference post") if references.size > 1

        base = { "slug" => slug, "title" => meta["title"], "total" => parts.size,
                 "parts" => parts.map { |p| link(p) }, "reference" => references.first && link(references.first) }
        parts.each_with_index do |post, i|
          post.data["series_info"] = base.merge(
            "role" => "part", "part" => i + 1,
            "previous" => i.positive? ? link(parts[i - 1]) : nil,
            "next" => parts[i + 1] && link(parts[i + 1])
          )
        end
        references.first&.data&.[]=("series_info", base.merge("role" => "reference"))
      end
    end

    def validate_part(post)
      role = post.data["series_role"]
      fail!("#{post.relative_path}: unknown series_role #{role.inspect}") if role
      part = post.data["series_part"]
      return if part.is_a?(Integer) && part.positive?

      fail!("#{post.relative_path}: series_part must be a positive integer, got #{part.inspect}")
    end

    def check_sequence(slug, parts, total)
      fail!("series '#{slug}' needs an integer total in _data/series.yml") unless total.is_a?(Integer)
      found = parts.map { |p| p.data["series_part"] }
      return if found == (1..total).to_a

      fail!("series '#{slug}' parts are #{found.inspect}; expected 1..#{total}")
    end

    def link(post)
      { "url" => post.url, "title" => post.data["title"], "card_title" => post.data["card_title"],
        "part" => post.data["series_part"] }
    end

    def fail!(message)
      raise Jekyll::Errors::FatalException, "blog_images: #{message}"
    end
  end
end
