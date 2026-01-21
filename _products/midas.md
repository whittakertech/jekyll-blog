---
layout: products
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
---

## Overview

Midas centralizes all monetary behavior in Rails applications using a polymorphic `Coin` ledger.  
Instead of duplicating `price_cents` and currency columns across dozens of models, Midas stores every monetary value in a single, consistent system.

This prevents rounding bugs, supports multi-currency conversion, and ensures financial logic remains predictable as your application grows.

## Why Midas Exists

As systems scale, currency logic becomes one of the most fragile parts of an application.  
Teams often duplicate conversion, rounding, and formatting logic in dozens of places.

Midas eliminates this entirely.

## Key Features

- Single polymorphic `Coin` model for all monetary values
- Multi-currency support using the `money` gem
- Declarative `has_coin` and `has_coins` DSL
- Automatic conversion for integers, floats, and `Money` objects
- Headless Stimulus-powered currency input field
- Zero schema duplication
- 90%+ test coverage
- Full API documentation and architecture overview

## Documentation

Full documentation is available at:

[{{ page.links.docs }}]({{ page.links.docs }})

## Installation

```ruby
gem "whittaker_tech-midas"
```

Run migrations:

```bash
bin/rails railties:install:migrations FROM=whittaker_tech_midas
bin/rails db:migrate
```

## Links

- GitHub: [{{ page.links.github }}]({{ page.links.github }})
- RubyGems: [{{ page.links.rubygems }}]({{ page.links.rubygems }})
- Documentation: [{{ page.links.docs }}]({{ page.links.docs }})

## Roadmap

- Exchange rate fetching
- Versioned coin histories
- ViewComponent integrations
- Billing integration examples (Stripe and LemonSqueezy)

## License

MIT License, © WhittakerTech.
