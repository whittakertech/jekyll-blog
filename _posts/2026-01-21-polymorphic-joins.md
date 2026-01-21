---
layout: post
date: 2026-01-21 09:00:00 -0600
title: "Polymorphic Joins in Rails: Automatic Query Optimization Without Raw SQL"
slug: "polymorphic-joins"
canonical_url: "https://whittakertech.com/blog/polymorphic-joins/"
description: >-
  Rails avoids polymorphic joins by design—but real systems often have deterministic cases.
  Here’s how reflection, Arel, and explicit opt-in can make polymorphic joins safe, auditable,
  and production-ready without injecting SQL.
og_title: "Polymorphic Joins in Rails"
headline: >-
  Finishing the Sentence Rails Starts: How to Build Safe, Explicit Polymorphic Joins
  Without Raw SQL or Framework Monkey-Patching
categories: ["Ruby on Rails", "Software Architecture"]
tags: ["Rails", "Polymorphic associations", "Arel", "ActiveRecord", "Security", "Brakeman",
       "Query optimization", "Architecture", "Technical debt"]
---

For most of my career, I treated polymorphic associations as a brilliant way to handle many-to-one relationships with a plurality of possible target models.

They’re incredibly powerful. They reduce schema churn. They model real-world relationships cleanly.
And sooner or later, they push you directly into one of Rails’ hardest boundaries:

**You can’t `joins` a polymorphic association.**

If you’ve worked in Rails long enough, you’ve hit this moment.

You have something like:

```ruby
belongs_to :notable, polymorphic: true
```

And a perfectly reasonable requirement:

> “Give me all notes where the associated record has `customer_id = X`.”

You try:

```ruby
joins(:notable)
```

Rails says no.

So you reach for raw SQL.

```ruby
joins("INNER JOIN calls ON notes.notable_id = calls.id")
```

It works.  
But it's not DRY.  
It’s fragile.  
It requires knowing table names and column names.

So you try.

```ruby
joins("INNER JOIN #{Call.table_name} ON #{Note.table_name}.notable_id = #{Call.table_name}.id")
```

And that's better, but not DRY enough.

```ruby
scope :joins_notable, ->(klass) { 
  joins("INNER JOIN #{klass.table_name} 
         ON #{Note.table_name}.notable_id = #{klass.table_name}.id")
  .where(notable_type: klass.name)
}
```

Now you can use it everywhere.
Then Brakeman warns you about SQL injection.

This post is about what’s actually going on there — and how to fix it **without fighting Rails, trusting raw SQL, or turning polymorphism into an escape hatch.**

---

## Why Rails Refuses Polymorphic Joins (and Why It’s Right)

This part matters, because Rails is not being lazy here.

Polymorphic associations resolve **at runtime**:

```ruby
note.notable_type # => "Call"
note.notable_id   # => 123
```

SQL joins must resolve **at query compile time**.

Rails cannot know which table to join without guessing — and guessing would be unsafe.

Should it generate:

```sql
JOIN calls
JOIN invoices
JOIN users
```

&hellip;based on every possible polymorphic target?

That’s not a missing feature. That’s a deliberate boundary.

Rails gives us a powerful modeling tool; then draws a hard line at query generation and says:

> “If you cross this, you’re responsible.”

That boundary is reasonable.  
But it leaves a gap in real systems.

---

## The Problem With the Usual Workarounds

In every long-lived Rails codebase I’ve worked in, the same workaround appears eventually:

- Hand-written `JOIN` strings
- Interpolated table names
- Comments explaining “this is safe”
- Copy-paste variations elsewhere

Even when *you* know the join is deterministic, the system doesn’t.

Static analysis tools can’t verify it.  
Future developers can’t audit it.  
Refactors become dangerous.  
Security reviews become noisy.

This is how technical debt quietly accumulates — not because the code is wrong, but because **the intent isn’t encoded anywhere the system can see.**

---

## The Missing Idea: Consent

The breakthrough for me wasn’t technical. It was conceptual.

I stopped asking:

> “How do I join a polymorphic association safely?”

And started asking:

> “When *should* a polymorphic join be allowed at all?”

In most real systems, polymorphism isn’t open-ended.

There are usually **very specific, intentional relationships**, like:

```ruby
# On the polymorphic owner
belongs_to :notable, polymorphic: true

# On the target model
has_many :notes, as: :notable, class_name: "Note"
```

That second line is doing more work than people realize.

It’s saying:

> “This model explicitly consents to being joined as a notable.”

That’s policy.

And policy is enforceable.

---

## Using Reflection to Verify Opt-In

ActiveRecord already tracks everything we need.

We can ask a class:

- Does it declare a `has_many` or `has_one` association?
- Does that association use `as: :notable`?
- Does it actually point back to *this* polymorphic model?

If the answer is yes, the join is not a guess.  
It’s a verified relationship.

A simplified version of the check looks like this:

```ruby
klass.reflect_on_all_associations.any? do |assoc|
  assoc.options[:as] == :notable &&
    [:has_many, :has_one].include?(assoc.macro) &&
    assoc.klass == self
end
```

No string enums.  
No hard-coded table names.  
No assumptions.

The models themselves declare what’s allowed.

---

## Building the Join Safely With Arel

> Arel is a SQL AST builder for Ruby. Read more about it [here](https://api.rubyonrails.org/classes/Arel.html).

Once the relationship is verified, the join itself should still be safe, auditable, and tool-friendly.

This is where Arel earns its keep.

Instead of interpolating identifiers into raw SQL, we construct the join explicitly:

```ruby
source = arel_table
target = klass.arel_table

joins(
  source.join(target)
        .on(source["#{name}_id"].eq(target[:id]))
        .join_sources
).where(source["#{name}_type"].eq(klass.name))
```

What this buys you:

- No raw SQL strings
- No interpolated identifiers
- Brakeman can reason about it
- Refactors are safer
- The database planner still gets clean SQL

This isn’t about being clever.  
It’s about making intent machine-verifiable.

---

## Making It Reusable

Once I had this working in one place, the next question was obvious:

Why am I rewriting this logic every time?

The answer was a small concern that:

- Detects `belongs_to :X, polymorphic: true`
- Defines `joins_X(klass)`
- Enforces opt-in via reflection
- Fails loudly when misused

The resulting API reads cleanly:

```ruby
Note.joins_notable(Call)
```

No SQL.  
No guessing.  
No comments explaining why it’s safe.

Just policy, encoded in code.

---

## Why This Isn’t in Rails Core

Rails can’t ship this.

Not because it doesn’t work — but because it encodes **policy**.

Rails gives us primitives:
- polymorphic associations
- reflection
- Arel

What I’ve described here finishes the sentence Rails intentionally leaves incomplete.

That belongs at the application or library layer, not the framework.

---

## The Payoff

The benefit isn’t just cleaner queries.

It’s:

- Fewer N+1s without unsafe SQL
- Less tribal knowledge trapped in comments
- Easier security reviews
- Safer refactors
- Clearer intent for the next developer

Polymorphism doesn’t have to mean “escape hatch.”

With explicit consent and a little reflection, it can be just another well-behaved part of your query layer.

And once it’s encoded, it keeps paying dividends long after you’ve forgotten why you needed it in the first place.
