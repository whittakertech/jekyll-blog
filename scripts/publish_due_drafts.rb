#!/usr/bin/env ruby
# Promote dated drafts before the same workflow builds and deploys the site.
require "date"
require "fileutils"
require "time"
require "yaml"

published = 0

Dir.glob("_drafts/*.{md,markdown}").sort.each do |draft|
  content = File.read(draft)
  match = content.match(/\A---\s*\r?\n(.*?)\r?\n---\s*\r?\n/m)
  raise "Missing YAML front matter: #{draft}" unless match

  metadata = YAML.safe_load(match[1], permitted_classes: [Date, Time, DateTime]) || {}
  date = metadata.fetch("date") { raise "Missing date: #{draft}" }.to_s
  unless date.match?(/(?:Z|[+-]\d{2}:?\d{2})\z/i)
    raise "Date must include a UTC offset: #{draft} (#{date})"
  end

  release_time = Time.parse(date)
  next if release_time > Time.now

  name = File.basename(draft).sub(/\.(?:md|markdown)\z/, "")
  destination = "_posts/#{release_time.strftime('%Y-%m-%d')}-#{name}.md"
  raise "Destination already exists: #{destination}" if File.exist?(destination)

  content = content.sub(/^(published:[ \t]*)false[ \t]*$/i, '\1true')
  FileUtils.mkdir_p("_posts")
  File.write(destination, content)
  File.delete(draft)
  warn "Published #{draft} as #{destination}"
  published += 1
end

puts published
