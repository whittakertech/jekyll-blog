---
layout: product
title: "Poly"
tagline: "Structural identity for polymorphic associations in Rails"
description: "A focused Rails toolkit for type-safe polymorphic joins, role and owner identity, and consistent migration patterns."
slug: "poly"
categories:
  - rails
  - gem
  - associations
links:
  github: "https://github.com/whittakertech/poly"
  docs: "https://poly.whittakertech.com"
card:
  kicker: Rails primitives
  headline: Make polymorphism predictable.
sources:
  github: whittakertech/poly
features:
  - title: Type-safe joins
    text: Generate polymorphic `INNER JOIN`s that validate the target's reverse association.
    icon: code
  - title: Semantic roles
    text: Normalize and validate role identity so relationships can express what they mean.
    icon: layers
  - title: Owner stamping
    text: Project a persisted root owner onto a row at write time—without traversing later.
    icon: database
  - title: Consistent migrations
    text: Declare polymorphic resource, role, owner, and index structures with shared helpers.
    icon: shield-check
  - title: Role-based history
    text: Track a current prime entry and its supersession history with `Poly::Stack`.
    icon: history
install:
  - label: Gemfile
    language: ruby
    code: gem "poly"
  - label: Install
    language: bash
    code: bundle install
use_cases:
  - Querying polymorphic associations with type-safe joins
  - Distinguishing relationships by semantic role
  - Filtering polymorphic records by their root owner
  - Keeping polymorphic columns and indexes consistent across migrations
  - Preserving role-discriminated history, such as status changes
---

## Overview

Rails gives polymorphic `belongs_to` associations a type and an ID, but leaves
the surrounding structure to each application. Poly adds small, composable
primitives for joining those associations, giving them semantic roles,
projecting owner identity onto records, and keeping their schema consistent.

The result is clearer identity at the edges of your data model, without
introducing a new domain model or taking control of application behavior.

## What Poly Adds

Use `Poly::Joins` to build type-aware joins, `Poly::Role` to validate and
normalize relationship roles, and `Poly::Owners` to stamp a root owner when a
record is written. `Poly::Migration` provides matching helpers for the columns
and composite indexes those patterns need.

For role-discriminated histories, `Poly::Stack` keeps a current prime entry and
links superseded entries while leaving payload and business meaning to your
application.

## Designed to Stay Out of Your Way

Poly provides structure, not business policy. It does not implement tenancy,
infer or enforce authorization, traverse associations for you, or generate
domain logic. You keep ownership of how your application interprets its data.

Poly requires Ruby 3.2 or newer and ActiveRecord 6.1 or newer. It is tested
against SQLite and PostgreSQL; MySQL is unsupported because its adapter does
not preserve the partial unique index required by `Poly::Stack`.
