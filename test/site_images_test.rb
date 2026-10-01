# frozen_string_literal: true

# Offline tests for _plugins/site_images.rb (no network: SITE_IMAGES_FIXTURE).
# Run: ruby -Itest test/site_images_test.rb
require "minitest/autorun"
require "jekyll"
require "yaml"

require_relative "../_plugins/site_images"

class SiteImagesTest < Minitest::Test
  FIXTURES = File.expand_path("fixtures/site_images", __dir__)
  SNAPSHOT = YAML.safe_load_file(File.expand_path("../_data/site_images.yml", __dir__))["mission-hero"]
  Site = Struct.new(:data)

  class Recorder
    attr_reader :warns, :infos

    def initialize = (@warns = []; @infos = [])
    def warn(topic, message = nil) = @warns << "#{topic} #{message}"
    def info(topic, message = nil) = @infos << "#{topic} #{message}"
    def method_missing(*) = nil
    def respond_to_missing?(*) = true
  end

  def setup
    WhittakerTech::SiteImages::CACHE.clear
    @logger = Recorder.new
    @old_logger = Jekyll.logger
    Jekyll.instance_variable_set(:@logger, @logger)
    @old_env = ENV["SITE_IMAGES_FIXTURE"]
    ENV["SITE_IMAGES_FIXTURE"] = FIXTURES
  end

  def teardown
    Jekyll.instance_variable_set(:@logger, @old_logger)
    ENV["SITE_IMAGES_FIXTURE"] = @old_env
  end

  # Snapshot for +key+, with its processed/ paths rewritten to that key.
  def snapshot_for(key)
    Marshal.load(Marshal.dump(SNAPSHOT)).then do |entry|
      YAML.safe_load(entry.to_yaml.gsub("processed/mission-hero/", "processed/#{key}/"))
    end
  end

  def run_generator(sources, snapshots = {})
    site = Site.new({ "site_image_sources" => sources, "site_images" => snapshots })
    WhittakerTech::SiteImages.new({}).generate(site)
    site.data["site_images"]
  end

  def resolve(key, options = nil)
    run_generator({ key => options }, { key => snapshot_for(key) })[key]
  end

  def urls(entry)
    entry["variants"].values.flat_map(&:values).flatten.map { |v| v["url"] }
  end

  def test_version_two_pointer_replaces_snapshot
    entry = run_generator({ "mission-hero" => nil }, { "mission-hero" => SNAPSHOT })["mission-hero"]
    assert_equal 2, entry["version"]
    assert_equal "live", entry["source"]
    assert_equal 4, urls(entry).size
    assert(urls(entry).all? { |u| u.include?("/processed/mission-hero/v2/") })
    assert_empty urls(SNAPSHOT) & urls(entry)
    assert_empty @logger.warns
    assert_includes @logger.infos, "SiteImages: mission-hero v2 (live)"
  end

  def test_pin_selects_versioned_manifest_even_when_pointer_is_newer
    entry = resolve("mission-hero", { "pin" => 1 })
    assert_equal 1, entry["version"]
    assert_equal "pinned", entry["source"]
    assert(urls(entry).all? { |u| u.include?("/v1/") })
    assert_includes @logger.infos, "SiteImages: mission-hero v1 (pinned)"
  end

  def test_pin_mismatch_falls_back
    entry = resolve("pin-mismatch", { "pin" => 1 })
    assert_equal "snapshot", entry["source"]
    assert_match(/version 2 != pin 1/, @logger.warns.join)
  end

  def test_resolved_entry_matches_snapshot_shape_and_drops_fields
    entry = resolve("mission-hero", { "pin" => 1 })
    assert_equal SNAPSHOT, entry.reject { |k, _| %w[version source].include?(k) }
    %w[key profile workbench processed_at].each { |k| refute entry.key?(k), k }
    refute entry["original"].key?("sha256")
    assert_equal %w[url width height].sort, entry["original"].keys.sort
    assert_equal %w[alt credit focal original source variants version], entry.keys.sort
  end

  def test_rendered_urls_have_no_query_or_rewrite
    entry = resolve("mission-hero")
    assert(urls(entry).none? { |u| u.include?("?") })
  end

  %w[bad-host bad-prefix bad-widths bad-ratio bad-size bad-version-path bad-original bad-format
     key-mismatch bad-version invalid-json oversized].each do |key|
    define_method("test_invalid_#{key.tr('-', '_')}_falls_back_with_warning") do
      entry = resolve(key)
      assert_equal "snapshot", entry["source"]
      assert_equal 1, entry["version"]
      assert_equal urls(snapshot_for(key)), urls(entry)
      assert_equal 1, @logger.warns.size
      assert_match(/\ASiteImages: #{key}: .*#{key}\/current\.json unusable/, @logger.warns.first)
      assert_includes @logger.infos, "SiteImages: #{key} v1 (snapshot)"
    end
  end

  def test_missing_fixture_falls_back
    entry = resolve("no-such-key")
    assert_equal "snapshot", entry["source"]
    assert_match(/not found/, @logger.warns.first)
  end

  def test_listed_key_without_snapshot_and_failing_fetch_raises
    error = assert_raises(Jekyll::Errors::FatalException) { run_generator({ "no-such-key" => nil }) }
    assert_match(/\Asite_images: no-such-key/, error.message)
  end

  def test_listed_key_without_snapshot_resolves_when_fetch_works
    entry = run_generator({ "mission-hero" => nil })["mission-hero"]
    assert_equal "live", entry["source"]
  end

  def test_malformed_options_raise
    [{ "pin" => 0 }, { "pin" => -1 }, { "pin" => "1" }, { "pin" => 1.5 }, { "pin" => nil }, { "bogus" => 1 }, "pin: 1", [1]].each do |opts|
      error = assert_raises(Jekyll::Errors::FatalException, opts.inspect) { run_generator({ "mission-hero" => opts }) }
      assert_match(/\Asite_images: mission-hero/, error.message)
    end
  end

  def test_unlisted_snapshot_key_is_untouched
    other = { "original" => { "url" => "https://media.whittakertech.com/whittakertech/site/originals/x.png" } }
    images = run_generator({ "mission-hero" => nil }, { "mission-hero" => SNAPSHOT, "other" => other })
    assert_same other, images["other"]
    assert_equal "live", images["mission-hero"]["source"]
  end

  def test_absent_sources_data_is_a_no_op
    site = Site.new({ "site_images" => { "a" => 1 } })
    WhittakerTech::SiteImages.new({}).generate(site)
    assert_equal({ "a" => 1 }, site.data["site_images"])
  end

  def test_results_are_memoized
    run_generator({ "mission-hero" => nil })
    ENV["SITE_IMAGES_FIXTURE"] = "/nonexistent"
    # Cache is keyed on the fixture dir too, so a different source is re-resolved.
    entry = run_generator({ "mission-hero" => nil }, { "mission-hero" => SNAPSHOT })["mission-hero"]
    assert_equal "snapshot", entry["source"]
    ENV["SITE_IMAGES_FIXTURE"] = FIXTURES
    assert_equal "live", run_generator({ "mission-hero" => nil })["mission-hero"]["source"]
    assert_equal 2, WhittakerTech::SiteImages::CACHE.size
  end
end
