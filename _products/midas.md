---
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
install:
  - label: Gemfile
    language: ruby
    code: gem "whittaker_tech-midas"
  - label: Install and run the migrations
    language: bash
    code: |
      bin/rails railties:install:migrations FROM=whittaker_tech_midas
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

Midas centralizes monetary values in a polymorphic `Coin` ledger. Instead of repeating price and currency columns on each model, attach one or more values to any model:

```ruby
# Product has price_cents and price_currency columns
product.price_cents
product.price_currency

# Midas: one shared ledger, attached through the model
class Product < ApplicationRecord
  has_coin :price
end
```

The `has_coin` declaration gives the model a consistent money interface while Midas stores the value in the shared ledger. This helps prevent rounding bugs, supports multi-currency conversion, and keeps financial logic predictable as your application grows.

## Why Midas Exists

As systems scale, currency logic becomes one of the most fragile parts of an application.  
Teams often duplicate conversion, rounding, and formatting logic in dozens of places.

Midas eliminates this entirely.
