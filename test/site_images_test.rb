# frozen_string_literal: true

# Offline tests for _plugins/site_images.rb. No network, no extra gems: a tiny stdlib-only
# harness is used so the file runs exactly as CI runs it, `bundle exec ruby test/site_images_test.rb`.
require "jekyll"
require "json"
require "tmpdir"
require "fileutils"
require "yaml"
require "timeout"
require_relative "../_plugins/site_images"

# --- Minimal harness ----------------------------------------------------------------------

class Failure < StandardError; end

module Asserts
  def assert(cond, msg = "assertion failed") = (raise Failure, msg unless cond)
  def refute(cond, msg = "refutation failed") = assert(!cond, msg)
  def assert_equal(exp, act, msg = nil) = assert(exp == act, msg || "expected #{exp.inspect}, got #{act.inspect}")
  def assert_includes(coll, item) = assert(coll.include?(item), "#{coll.inspect} does not include #{item.inspect}")
  def assert_match(re, str) = assert(re.match?(str.to_s), "#{str.inspect} !~ #{re.inspect}")
  def assert_empty(coll) = assert(coll.empty?, "expected empty, got #{coll.inspect}")

  def assert_raises(klass)
    yield
  rescue klass => e
    e
  else
    raise Failure, "expected #{klass} to be raised"
  end
end

class TestCase
  include Asserts
  TESTS = []

  def self.test(name, &block)
    TESTS << [name, block]
  end

  def self.each_case(name, cases, &block)
    cases.each { |label, value| test("#{name} (#{label})") { instance_exec(value, label, &block) } }
  end
end

# --- Test doubles ---------------------------------------------------------------------------

class Recorder
  attr_reader :warns, :infos

  def initialize = (@warns = []; @infos = [])
  def warn(topic, message = nil) = @warns << "#{topic} #{message}"
  def info(topic, message = nil) = @infos << "#{topic} #{message}"
  def method_missing(*) = nil
  def respond_to_missing?(*) = true
end

# Net::HTTP stand-in: records the request, hands a scripted response to the block.
class FakeHttp
  attr_accessor :use_ssl, :open_timeout, :read_timeout
  attr_reader :requests

  def initialize(&responder)
    @responder = responder
    @requests = []
  end

  def request(req, &block)
    @requests << req
    block.call(@responder.call(req))
  end
end

def fake_response(klass, code, chunks: [], &each_chunk)
  res = klass.new("1.1", code, "x")
  res.define_singleton_method(:read_body) do |&blk|
    chunks.each { |c| blk.call(c) }
    each_chunk&.call(blk)
  end
  res
end

class SiteImagesTest < TestCase
  FIXTURES = File.expand_path("fixtures/site_images", __dir__)
  SNAPSHOT = YAML.safe_load_file(File.expand_path("../_data/site_images.yml", __dir__))["mission-hero"]
  Site = Struct.new(:data)
  SI = WhittakerTech::SiteImages
  PREFIX = SI::PREFIX

  def setup
    SI::CACHE.clear
    SI.reset_seams!
    @logger = Recorder.new
    @old_logger = Jekyll.logger
    Jekyll.instance_variable_set(:@logger, @logger)
    @old_env = ENV["SITE_IMAGES_FIXTURE"]
    ENV["SITE_IMAGES_FIXTURE"] = FIXTURES
  end

  def teardown
    Jekyll.instance_variable_set(:@logger, @old_logger)
    ENV["SITE_IMAGES_FIXTURE"] = @old_env
    SI.reset_seams!
  end

  def snapshot_for(key)
    YAML.safe_load(SNAPSHOT.to_yaml.gsub("processed/mission-hero/", "processed/#{key}/"))
  end

  def run_generator(sources, snapshots = {})
    site = Site.new({ "site_image_sources" => sources, "site_images" => snapshots })
    SI.new({}).generate(site)
    site.data["site_images"]
  end

  def resolve(key, options = nil)
    run_generator({ key => options }, { key => snapshot_for(key) })[key]
  end

  def urls(entry)
    entry["variants"].values.flat_map(&:values).flatten.map { |v| v["url"] }
  end

  def valid_manifest(version = 2)
    JSON.parse(File.read(File.join(FIXTURES, "mission-hero", "current.json"))).tap do |m|
      m["version"] = version
    end
  end

  # Resolves mission-hero against a manifest written to a temp fixture directory.
  def resolve_manifest(manifest)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "mission-hero"))
      File.write(File.join(dir, "mission-hero", "current.json"), JSON.generate(manifest))
      ENV["SITE_IMAGES_FIXTURE"] = dir
      SI::CACHE.clear
      resolve("mission-hero")
    end
  ensure
    ENV["SITE_IMAGES_FIXTURE"] = FIXTURES
  end

  def assert_snapshot_fallback(entry)
    assert_equal "snapshot", entry["source"]
    assert_equal 1, entry["version"]
    assert_equal 1, @logger.warns.size, @logger.warns.inspect
  end

  # --- Resolution ---

  test "version two pointer replaces snapshot" do
    entry = run_generator({ "mission-hero" => nil }, { "mission-hero" => SNAPSHOT })["mission-hero"]
    assert_equal 2, entry["version"]
    assert_equal "live", entry["source"]
    assert_equal 4, urls(entry).size
    assert urls(entry).all? { |u| u.include?("/processed/mission-hero/v2/") }
    assert_empty(urls(SNAPSHOT) & urls(entry))
    assert_empty @logger.warns
    assert_includes @logger.infos, "SiteImages: mission-hero v2 (live)"
  end

  test "pin selects the versioned manifest even when the pointer is newer" do
    entry = resolve("mission-hero", { "pin" => 1 })
    assert_equal [1, "pinned"], [entry["version"], entry["source"]]
    assert urls(entry).all? { |u| u.include?("/v1/") }
    assert_includes @logger.infos, "SiteImages: mission-hero v1 (pinned)"
  end

  test "pin mismatch falls back" do
    entry = resolve("pin-mismatch", { "pin" => 1 })
    assert_equal "snapshot", entry["source"]
    assert_match(/version 2 != pin 1/, @logger.warns.join)
  end

  test "resolved entry matches snapshot shape and drops fields" do
    entry = resolve("mission-hero", { "pin" => 1 })
    assert_equal SNAPSHOT, entry.reject { |k, _| %w[version source].include?(k) }
    %w[key profile workbench processed_at].each { |k| refute entry.key?(k), k }
    refute entry["original"].key?("sha256")
    assert_equal %w[alt credit focal original source variants version], entry.keys.sort
  end

  test "rendered urls carry no query" do
    assert resolve("mission-hero")["variants"].to_s.match?(/\?/) == false
  end

  each_case("invalid manifest falls back with one warning",
            %w[bad-host bad-prefix bad-widths bad-ratio bad-size bad-version-path bad-original bad-format
               key-mismatch bad-version invalid-json oversized bad-no-output bad-no-format bad-empty-list].to_h { |k| [k, k] }) do |key|
    entry = resolve(key)
    assert_snapshot_fallback(entry)
    assert_equal urls(snapshot_for(key)), urls(entry)
    assert_match(/\ASiteImages: #{key}: .*#{key}\/current\.json unusable/, @logger.warns.first)
    assert_includes @logger.infos, "SiteImages: #{key} v1 (snapshot)"
  end

  test "missing fixture falls back" do
    entry = resolve("no-such-key")
    assert_equal "snapshot", entry["source"]
    assert_match(/not found/, @logger.warns.first)
  end

  test "listed key without snapshot and failing fetch raises" do
    error = assert_raises(Jekyll::Errors::FatalException) { run_generator({ "no-such-key" => nil }) }
    assert_match(/\Asite_images: no-such-key/, error.message)
  end

  test "listed key without snapshot resolves when fetch works" do
    assert_equal "live", run_generator({ "mission-hero" => nil })["mission-hero"]["source"]
  end

  # --- C2: coverage of what the snapshot provides ---

  test "a manifest may add formats and outputs beyond the snapshot" do
    m = valid_manifest
    m["variants"]["mission"]["jpeg"] = m["variants"]["mission"]["webp"].map { |v| v.merge("url" => v["url"].sub(".webp", ".jpg")) }
    m["variants"]["extra"] = { "webp" => m["variants"]["mission"]["webp"] }
    assert_equal "live", resolve_manifest(m)["source"]
  end

  test "a manifest with only a different output is rejected" do
    m = valid_manifest
    m["variants"] = { "other" => m["variants"]["mission"] }
    assert_snapshot_fallback(resolve_manifest(m))
    assert_match(/variants.mission is missing/, @logger.warns.first)
  end

  test "a manifest whose mission set has only jpeg is rejected" do
    m = valid_manifest
    m["variants"]["mission"] = { "jpeg" => m["variants"]["mission"]["webp"].map { |v| v.merge("url" => v["url"].sub(".webp", ".jpg")) } }
    assert_snapshot_fallback(resolve_manifest(m))
    assert_match(/variants.mission.webp is missing/, @logger.warns.first)
  end

  test "an empty format list is rejected" do
    m = valid_manifest
    m["variants"]["mission"]["webp"] = []
    assert_snapshot_fallback(resolve_manifest(m))
  end

  test "the template filter refuses empty image data" do
    filter = Object.new.extend(WhittakerTech::SiteImageFilter)
    [nil, [], [{ "url" => "", "width" => 1, "height" => 1 }], [{ "url" => "x", "width" => nil, "height" => 1 }]].each do |bad|
      error = assert_raises(Jekyll::Errors::FatalException) { filter.site_image_set(bad, "k.v") }
      assert_match(/\Asite_images: k\.v/, error.message)
    end
    ok = [{ "url" => "x", "width" => 1, "height" => 1 }]
    assert_equal ok, filter.site_image_set(ok, "k.v")
  end

  # --- K1: URL hygiene ---

  each_case("unsafe image url is rejected",
            { "dot-dot" => "processed/mission-hero/v2/../v1/a.webp", "dot" => "processed/mission-hero/v2/./a.webp",
              "pct-dots" => "processed/mission-hero/v2/%2e%2e/a.webp", "pct-slash" => "processed/mission-hero/v2/a%2fb.webp",
              "query" => "processed/mission-hero/v2/a.webp?x=1", "fragment" => "processed/mission-hero/v2/a.webp#f",
              "backslash" => "processed/mission-hero/v2/a\\b.webp", "space" => "processed/mission-hero/v2/a b.webp",
              "newline" => "processed/mission-hero/v2/a\nb.webp", "tab" => "processed/mission-hero/v2/a\tb.webp",
              "nul" => "processed/mission-hero/v2/a\u0000b.webp", "double-slash" => "processed/mission-hero/v2//a.webp",
              "quote" => "processed/mission-hero/v2/a\".webp" }) do |tail|
    m = valid_manifest
    m["variants"]["mission"]["webp"][0]["url"] = PREFIX + tail
    assert_snapshot_fallback(resolve_manifest(m))
  end

  # --- Options / keys ---

  each_case("malformed options raise",
            { "zero" => { "pin" => 0 }, "negative" => { "pin" => -1 }, "string" => { "pin" => "1" },
              "float" => { "pin" => 1.5 }, "nil-pin" => { "pin" => nil }, "unknown" => { "bogus" => 1 },
              "scalar" => "pin: 1", "array" => [1] }) do |opts|
    error = assert_raises(Jekyll::Errors::FatalException) { run_generator({ "mission-hero" => opts }) }
    assert_match(/\Asite_images: mission-hero/, error.message)
  end

  each_case("invalid key raises a site_images error",
            { "space" => "a b", "accent" => "é", "newline" => "a\nb", "upper" => "Mission", "slash" => "a/b",
              "dots" => "..", "leading-dash" => "-a", "empty" => "", "too-long" => "a" * 42, "integer" => 5 }) do |key|
    error = assert_raises(Jekyll::Errors::FatalException) { run_generator({ key => nil }) }
    assert_match(/\Asite_images: key /, error.message)
  end

  test "unlisted snapshot key is untouched" do
    other = { "original" => { "url" => "#{PREFIX}originals/x.png" } }
    images = run_generator({ "mission-hero" => nil }, { "mission-hero" => SNAPSHOT, "other" => other })
    assert images["other"].equal?(other)
    assert_equal "live", images["mission-hero"]["source"]
  end

  test "absent sources data is a no-op" do
    site = Site.new({ "site_images" => { "a" => 1 } })
    SI.new({}).generate(site)
    assert_equal({ "a" => 1 }, site.data["site_images"])
  end

  test "results are memoized, failures included" do
    resolve("pin-mismatch", { "pin" => 1 })
    first = @logger.warns.size
    SI::CACHE.each_key { |k| assert_equal 3, k.size }
    resolve("pin-mismatch", { "pin" => 1 })
    assert_equal first, @logger.warns.size, "second run must not re-resolve"
  end

  # --- K4: the real fetch path through the injectable http seam ---

  def with_http(&responder)
    ENV["SITE_IMAGES_FIXTURE"] = nil
    @http = FakeHttp.new(&responder)
    @factory_args = []
    SI.http_factory = ->(host, port) { @factory_args << [host, port]; @http }
    SI::CACHE.clear
  end

  def fetch(url = "#{SI::MANIFESTS}mission-hero/current.json")
    SI.new({}).send(:fetch_url, url)
  end

  def ok_body(text)
    fake_response(Net::HTTPOK, "200", chunks: [text])
  end

  test "fetch returns the body, connects to the media host over TLS and sends no Authorization" do
    with_http { |_| ok_body('{"a":1}') }
    assert_equal '{"a":1}', fetch
    assert_equal [["media.whittakertech.com", 443]], @factory_args
    assert_equal true, @http.use_ssl
    assert_equal [5, 5], [@http.open_timeout, @http.read_timeout]
    req = @http.requests.first
    assert_equal "/whittakertech/site/manifests/mission-hero/current.json", req.path
    refute req.key?("authorization"), "Authorization header must never be sent"
  end

  each_case("non-2xx is a failure (redirects are not followed)",
            { "301" => [Net::HTTPMovedPermanently, "301"], "302" => [Net::HTTPFound, "302"],
              "307" => [Net::HTTPTemporaryRedirect, "307"], "404" => [Net::HTTPNotFound, "404"],
              "500" => [Net::HTTPInternalServerError, "500"] }) do |(klass, code)|
    with_http { |_| fake_response(klass, code, chunks: ['{"ok":1}']) }
    error = assert_raises(SI::FetchError) { fetch }
    assert_equal "HTTP #{code}", error.message
    assert_equal 1, @http.requests.size, "must not follow redirects"
  end

  test "a body over 64 KB is aborted while streaming" do
    delivered = 0
    with_http do |_|
      res = Net::HTTPOK.new("1.1", "200", "OK")
      res.define_singleton_method(:read_body) do |&blk|
        200.times { delivered += 1; blk.call("x" * 1024) }
      end
      res
    end
    error = assert_raises(SI::FetchError) { fetch }
    assert_match(/exceeds 65536 bytes/, error.message)
    assert delivered <= 66, "kept reading after the cap (#{delivered} chunks)"
  end

  test "a body of exactly 64 KB is accepted" do
    with_http { |_| ok_body("x" * SI::MAX_BYTES) }
    assert_equal SI::MAX_BYTES, fetch.bytesize
  end

  test "a stalled body is abandoned at the total deadline" do
    SI.deadline = 0.3
    with_http do |_|
      res = Net::HTTPOK.new("1.1", "200", "OK")
      res.define_singleton_method(:read_body) do |&blk|
        loop { blk.call("x"); sleep 0.1 } # slow drip stays under any per-read timeout
      end
      res
    end
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    error = assert_raises(SI::FetchError) { fetch }
    assert_match(/Timeout::Error.*total deadline/, error.message)
    assert Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 2, "deadline not enforced"
  end

  test "a slow connect or DNS lookup is covered by the deadline" do
    SI.deadline = 0.3
    ENV["SITE_IMAGES_FIXTURE"] = nil
    SI.http_factory = ->(_h, _p) { sleep 5 }
    error = assert_raises(SI::FetchError) { fetch }
    assert_match(/total deadline/, error.message)
  end

  each_case("non-media urls are refused before any connection",
            { "http" => "http://media.whittakertech.com/whittakertech/site/manifests/k/current.json",
              "other-host" => "https://example.com/whittakertech/site/manifests/k/current.json",
              "subdomain" => "https://evil.media.whittakertech.com/whittakertech/site/manifests/k/current.json",
              "userinfo" => "https://user:pw@media.whittakertech.com/whittakertech/site/manifests/k/current.json",
              "port" => "https://media.whittakertech.com:8443/whittakertech/site/manifests/k/current.json",
              "query" => "https://media.whittakertech.com/whittakertech/site/manifests/k/current.json?a=1",
              "outside-manifests" => "https://media.whittakertech.com/whittakertech/site/originals/x.png",
              "garbage" => "https://media.whittakertech.com/ba d" }) do |url|
    with_http { |_| ok_body("{}") }
    assert_raises(SI::FetchError) { fetch(url) }
    assert_empty @factory_args
  end

  test "network errors become fetch failures that fall back to the snapshot" do
    with_http { |_| raise Errno::ECONNREFUSED }
    entry = resolve("mission-hero")
    assert_equal "snapshot", entry["source"]
    assert_match(/ECONNREFUSED/, @logger.warns.first)
  end

  test "end to end over the seam: a live v2 manifest is resolved without fixtures" do
    body = File.read(File.join(FIXTURES, "mission-hero", "current.json"))
    with_http { |_| ok_body(body) }
    entry = run_generator({ "mission-hero" => nil }, { "mission-hero" => SNAPSHOT })["mission-hero"]
    assert_equal ["live", 2], [entry["source"], entry["version"]]
  end
end

# --- Runner ---------------------------------------------------------------------------------

failures = []
SiteImagesTest::TESTS.each do |name, block|
  t = SiteImagesTest.new
  begin
    t.setup
    t.instance_exec(&block)
    print "."
  rescue Failure, StandardError => e
    print "F"
    failures << "#{name}\n    #{e.class}: #{e.message}\n    #{e.backtrace.grep(/site_images_test/).first(2).join("\n    ")}"
  ensure
    t.teardown
  end
end
puts
puts failures
puts "#{SiteImagesTest::TESTS.size} tests, #{failures.size} failures"
exit(failures.empty? ? 0 : 1)
