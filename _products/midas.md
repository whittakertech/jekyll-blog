---
last_modified_at: 2026-09-30
layout: product
title: "Midas"
tagline: "Unified multi-currency monetary management for Rails"
description: "A Rails engine providing a single source of truth for currency values using a polymorphic Coin ledger."
slug: "midas"
categories:
  - rails
  - engine
  - gem
  - monetization
links:
  github: "https://github.com/whittakertech/midas"
  rubygems: "https://rubygems.org/gems/whittaker_tech-midas"
  docs: "https://midas.whittakertech.com"
card:
  kicker: Financial primitives
  headline: Turn complexity into clarity.
  theme: dark
  wordmark: "https://brand.whittakertech.com/assets/v/0.1.8/logo/midas/wordmark-dark.svg"
sources:
  rubygems: whittaker_tech-midas
  github: whittakertech/midas
features:
  - title: Polymorphic Coin ledger
    text: One `Coin` model stores every monetary value, for any model.
    icon: database
  - title: Multi-currency support
    text: Built on the `money` gem, with conversion between currencies.
    icon: globe
  - title: Declarative DSL
    text: "`has_coin` and `has_coins` attach money to a model in one line."
    icon: code
  - title: Zero schema duplication
    text: No more `price_cents` and currency columns repeated across tables.
    icon: layers
  - title: Headless currency input
    text: A Stimulus-powered input field that leaves the markup to you.
    icon: text-cursor
  - title: Tested and documented
    text: 90%+ test coverage, full API documentation and an architecture overview.
    icon: shield-check
  - title: Additive double-entry ledger
    text: Record balanced, immutable postings when a monetary workflow needs an auditable trail.
    icon: book-open
install:
  - label: Gemfile
    language: ruby
    code: gem "whittaker_tech-midas"
  - label: Install
    language: bash
    code: bundle install
  - label: Install Midas and run the migrations
    language: bash
    code: |
      bin/rails generate whittaker_tech:midas:install
      bin/rails db:migrate
use_cases:
  - Product catalogs and configurable pricing
  - Multi-currency applications
  - Invoices, billing, fees and payments
  - Models with multiple independent monetary values
roadmap:
  - Exchange rate fetching
  - Versioned coin histories
  - ViewComponent integrations
  - Billing integration examples (Stripe and LemonSqueezy)
---

## Overview

Give every model that handles money a consistent interface, without adding another pair of amount and currency columns to its table. Midas stores values in a shared, polymorphic `Coin` ledger:

```ruby
class Product < ApplicationRecord
  include WhittakerTech::Midas::Bankable
  has_coin :price
end
```

Use the same approach for prices, fees, balances, or several independent values on one record. Midas handles currency-aware amounts and conversion, so money behavior can stay consistent as your application grows.

## From monetary values to auditable flows

For everyday model attributes, `Coin` and `Bankable` are the core. When billing or payments also need a clear, auditable explanation of how balances changed, Midas adds a double-entry `Ledger` with balanced, immutable postings. The Ledger complements the simpler value model; it does not replace it. See the [documentation](https://midas.whittakertech.com) for the API and implementation details.
