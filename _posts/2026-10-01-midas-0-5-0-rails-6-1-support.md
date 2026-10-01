---
layout: post
date: 2026-10-01 06:00:00 -0600
title: "Midas 0.5.0: Lowering the Rails Floor to 6.1 Without Loosening the Ledger"
card_title: "Midas 0.5.0 Release"
slug: "midas-0-5-0-rails-6-1-support"
canonical_url: "https://whittakertech.com/blog/midas-0-5-0-rails-6-1-support/"
description: >-
  Midas 0.5.0 lowers its supported Rails floor from 7.1.5.2 to 6.1. Here is what changed in the
  Poly dependency, the version-conditional enums, the bundled migrations, and the CI matrix.
og_title: "Midas 0.5.0: Rails 6.1 Support for the Ledger Engine"
headline: >-
  Midas 0.5.0: How I Lowered the Supported Rails Floor to 6.1 With Version-Conditional Enums
  and a Wider CI Matrix
categories: ["Ruby on Rails", "Software Architecture"]
tags: ["Midas", "Rails", "Ruby gems", "ActiveRecord", "Enums", "Migrations", "Continuous integration"]
---

Midas 0.5.0 is tagged, and it does one main thing: it lowers the supported Rails floor from `>= 7.1.5.2` to `>= 6.1`.

I want to be plain about why. The changelog calls the old floor an end-of-life policy choice, not a technical constraint. Then I had a real application on Rails 6.1.7.10 and Ruby 3.3.11 that wanted to adopt `Coin`, and a policy line is a poor reason to turn that away.

Lowering the number was not the whole job, though. The ledger models used enum syntax that only exists in Rails 7.1, and those files load on boot, so Rails 6.1 could not even require the engine. The sections below cover what had to change to fix that.

What follows are the changes that matter for Rails compatibility, and the one place where behavior differs.

## The dependency floors

Two lines in the gemspec moved:

- `rails` from `>= 7.1.5.2` to `>= 6.1`
- `poly` from `~> 1.0` to `~> 1.3`

According to the changelog, Poly 1.3 is the release that lowered Poly's own ActiveRecord floor. At the tag, the gemspec reads `rails >= 6.1`, `poly ~> 1.3`, `money ~> 6.19.0`, and `required_ruby_version >= 3.2.0`.

## Enums that depend on the Rails version

The part that needed real thought was `Ledger::Account#kind` and `Ledger::Posting#direction`. Rails 7.1 introduced two things I was using: the positional form `enum :kind, values`, and the `validate: true` option, which turns an unknown value into a validation error. Rails 6.1 has neither.

So each model now declares its enum conditionally on `ActiveRecord::VERSION::STRING`:

```ruby
if ActiveRecord::VERSION::STRING >= '7.1'
  enum :kind, KINDS, validate: true
else
  enum kind: KINDS
end
```

On Rails 7.1 and later, behavior is exactly what it was. On 6.1 there is one difference you should know about. Assigning an unknown value raises `ArgumentError` at assignment time rather than producing a validation error.

I accepted that because the direction of the difference matters. It is stricter on 6.1, never looser. For a double-entry ledger, a bad `kind` or `direction` being rejected earlier is a tolerable trade. A bad value slipping through would not be. ActiveRecord 6.1 offers no way to defer that check to validation, so there was no way to make the two behave identically.

To make the allowed values easy to reach, the value maps are now exposed as constants: `Account::KINDS` and `Posting::DIRECTIONS`.

## Migrations that Rails 6.1 can parse

Every bundled migration used to declare `ActiveRecord::Migration[8.0]`. Rails 6.1 cannot parse a newer compatibility version, so they now declare `ActiveRecord::Migration[6.1]`.

I looked at whether that changes the resulting schema. For the adapters Midas supports, it does not in any way that matters. The only difference between 6.1 and 7.0 that would reach these tables is `datetime` precision. PostgreSQL's plain `timestamp` is already microsecond-precision, and SQLite treats precision as advisory.

Existing installations are unaffected, because their migrations have already run.

## Proving it in CI

Declaring a floor you never test is a promise you cannot keep. CI now has a Rails version axis, `RAILS_VERSION`, covering 7.1, 7.2, and 8.x, plus a 6.1 cell. Rails 6.1 predates Ruby 3.4, so that cell is pinned to Ruby 3.3, the Ruby the real consumer runs. RuboCop was split into its own job, since lint does not vary with the Rails version.

Making that matrix work meant fixing the test app and a few development dependencies too:

- `spec/dummy` could only boot on Rails 7.1 and later. Settings such as `config.autoload_lib`, `config.enable_reloading`, and `primary_abstract_class` are now version-guarded, as are the `show_exceptions` value type and `raise_on_missing_callback_actions`.
- `spec/rails_helper.rb` falls back from `fixture_paths` to `fixture_path` on older ActiveRecord.
- The `rspec-rails` development dependency went from `~> 7.0` to `>= 6.1`, because 7.x cannot resolve against Rails 6.1.
- The 6.1 bundle lane pins `concurrent-ruby < 1.3.5` and `sqlite3 ~> 1.4`. Both live in the Gemfile only; neither is a runtime requirement of the gem.

## Where it stands

The 0.5.0 section of the changelog and the repository at the `v0.5.0` tag are the sources for everything above, apart from the enum motivation, which comes from the commit message of 5e88d07 on the integration branch.

The product page is at [/products/midas/](/products/midas/), and the project site is at [midas.whittakertech.com](https://midas.whittakertech.com).
