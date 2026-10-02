---
layout: post
date: 2026-10-01 07:00:00 -0600
title: "Poly 1.3.0: Lowering the Rails Floor to 6.1 Without Changing the Library"
card_title: "Poly 1.3.0: Rails 6.1 Support"
slug: "poly-1-3-0-rails-6-1-support"
canonical_url: "https://whittakertech.com/blog/poly-1-3-0-rails-6-1-support/"
description: >-
  Poly 1.3.0 lowers the supported ActiveRecord and ActiveSupport floor from 7.1 to 6.1. No library code changed:
  the old floor was a policy choice, not a technical constraint. Here is what moved, what did not, and how it is tested.
og_title: "Poly 1.3.0 Release: ActiveRecord 6.1 Support, No Runtime Changes"
headline: >-
  Poly 1.3.0: What It Took to Support Rails 6.1 Again, and Why the Answer Was Mostly a Gemspec Line
categories: ["Ruby on Rails", "Release Notes"]
tags: ["Poly", "Rails", "ActiveRecord", "Rails 6.1", "Gemspec", "Release", "Compatibility", "Continuous integration"]
---

Most release posts are about something new. This one is about something that stayed the same.

[Poly](/products/poly/) 1.3.0 is a compatibility release. The gemspec floor for `activerecord` and `activesupport`
moved from `>= 7.1` to `>= 6.1`. That is the change. There are no new features, no new API, and nothing under
`lib/poly/` was modified except the version constant.

## The floor was a policy, not a constraint

When I set the original floor at 7.1, I treated it as a statement about which Rails versions I was willing to
maintain. I did not treat it as a statement about what the code needed. Those are different things, and I had let
them blur together.

So before lowering it, I went and checked. The 1.3.0 changelog records the result: a full scan of `lib/poly/*.rb`
found no Rails 7.1+ APIs. The only ActiveRecord internals Poly touches are `arel_table`,
`reflect_on_all_associations`, `reflect_on_association`, and `base_class`, and all four have been stable since well
before 6.1. The changelog says it plainly: the previous floor was "an end-of-life policy choice, not a technical
constraint."

That is a satisfying kind of finding. The diff for the actual change is two lines in `poly.gemspec`:

```ruby
spec.add_dependency 'activerecord', '>= 6.1'
spec.add_dependency 'activesupport', '>= 6.1'
```

What did not change is just as specific. `required_ruby_version` stays at `>= 3.2.0`. Poly 1.3.0 does not claim
support for any Ruby older than 3.2.

## Claiming support means testing it

Lowering a number in a gemspec costs nothing, and that is exactly why it proves nothing. A supported version is one
you run your suite against, so most of the work in this release was in CI and in the specs.

The CI matrix gained a `6.1` cell on both the SQLite lane and the PostgreSQL lane, and both are pinned to Ruby 3.3.
Rails 6.1 predates Ruby 3.4 entirely, so that combination is excluded, and I did not add a 3.2 cell for 6.1 either.
The honest summary is that 6.1 is tested on Ruby 3.3 only, and that is all the release claims. The README says the
same thing. MySQL stays unsupported, for the same reason as before: `Poly::Migration#poly_prime_index` relies on a
partial unique index that MySQL does not honor.

Running the suite on 6.1 turned up a few things, and none of them were in the library.

- **A hardcoded migration version.** `spec/models/poly/migration_spec.rb` used `ActiveRecord::Migration[7.1]`, which
  raises `Unknown migration version` on Rails 6.1. The specs now build their test migrations against a
  `POLY_MIGRATION_VERSION` constant derived from the ActiveRecord actually under test.
- **A table name that was too long.** One spec's generated index name was 67 characters, over Rails 6.1's
  64-character SQLite limit. It was also over PostgreSQL's 63-character limit on every version. The spec's table name
  is shorter now. The README gained a note that on 6.1 with SQLite, long table names may need an explicit
  `index_name:` on the `poly_*_index` helpers.
- **A CI lane that ignored its own matrix.** The PostgreSQL lane's `ruby/setup-ruby` step hardcoded `3.4` instead of
  reading `${{ matrix.ruby }}`, so the Ruby axis on that lane had never actually varied.

The 6.1 bundle also needs two pins in the `Gemfile`: `concurrent-ruby < 1.3.5`, because 1.3.5 dropped an implicit
`require 'logger'` that ActiveSupport 6.1 depends on, and `sqlite3 ~> 1.4`, because Rails 6.1's SQLite adapter
requires it. Both live in the `Gemfile` only. Neither is a runtime requirement of the gem.

## Documentation

The docs also landed between 1.2.0 and 1.3.0. They are published at
[poly.whittakertech.com](https://poly.whittakertech.com), and the repository now carries seven pages under `docs/`:
getting started, an index, and one page each for joins, migrations, owners, roles, and the stack. The README gained a
docs badge pointing at the same site.

## Why bother

The reason is simple. A dependency that refuses to resolve on an older Rails version is a wall, and a wall that
exists only because of a number I picked is not a good wall. Once the scan showed the code never needed it, keeping
the floor at 7.1 would have been defending a decision that had no technical content.

If you are on Rails 6.1 with Ruby 3.3, 1.3.0 is the version that resolves for you. If you are on anything newer,
nothing changes. The full list is in the [changelog](https://github.com/whittakertech/poly/blob/master/CHANGELOG.md),
and the product page is at [/products/poly/](/products/poly/).
