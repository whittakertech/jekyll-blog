---
date: 2025-05-22 13:00:00 -0600
title: "Strategic Code Modification: Custom Shopify Requirements"
og_title: "Smart Code Changes Without Breaking Your Shopify Theme"
headline: >-
  When Off-the-Shelf Meets Custom Requirements: How a Simple Prescription Product Request Became an Elegant Conditional
  Checkout Solution
description: >-
  Learn elegant code modification techniques through a real Shopify case study. Handle prescription vs regular products
  with conditional logic while preserving functionality.
slug: "strategic-code-modification"
canonical_url: "https://whittakertech.com/blog/strategic-code-modification/"
categories: ["Software Development", "E-commerce", "Code Architecture"]
tags: ["Shopify development", "Custom theme modification", "Code maintainability", "Conditional logic",
       "E-commerce integration", "Prescription fulfillment", "Legacy code preservation", "Technical debt management",
       "Liquid templating", "Strategic refactoring"]
---

*How a simple request to handle prescription products differently evolved into an elegant solution for conditional
checkout flows in Shopify.*

## The Challenge

Our client, an e-commerce brand expanding into prescription products, faced a seemingly simple request that revealed a
complex technical challenge. They had invested in a premium Shopify theme that worked perfectly for their regular
product catalog. However, their new prescription kit line required customers to complete their purchase through Bask
Health, a specialized prescription fulfillment partner accessible at go.ozio.com.

The initial solution seemed straightforward: modify the theme to redirect prescription product pages to Bask Health's
platform. But here's where it got interesting – after implementing the redirect, they realized they needed both
functionalities. Regular products should use Shopify's native checkout, while prescription products needed the Bask
Health redirect. The theme now needed to intelligently adapt based on product type, not force a one-size-fits-all
solution.

## The Obstacles

The first roadblock was the theme's complexity. Modern Shopify themes aren't simple templates – they're sophisticated
applications with interconnected components. The product page alone involved multiple elements: quantity selectors,
installment payment displays, variant pickers, and buy buttons. Ripping out functionality could break unexpected
features elsewhere.

Many developers would have created duplicate templates – one for regular products, another for prescriptions. This
approach seems logical but creates a maintenance nightmare. Every future theme update would require changes in multiple
places. Worse, it doubles the testing surface and increases the chance of the two templates drifting apart over time.

Another temptation was to completely delete the unused code for prescription products. After all, why keep quantity
selectors if prescription amounts are determined during consultation? But this scorched-earth approach eliminates
flexibility and makes rollbacks nearly impossible.

## Our Approach

Instead of deletion or duplication, we employed a "comment-first" modification strategy. Rather than removing Shopify's
native functionality, we commented it out. This preserved the working code while allowing us to test the Bask Health
redirect. Think of it as keeping your safety net while walking the tightrope.

When the client requested conditional functionality, this approach paid dividends. We introduced a single control
variable at the template level:

{% raw %}

```liquid
{%- assign is_prescription_product = false -%}
{%- if product.type == 'Prescription Kit' or product.tags contains 'prescription' -%}
  {%- assign is_prescription_product = true -%}
{%- endif -%}
```

{% endraw %}

Then, we simply wrapped the commented sections with conditional statements. The commented-out quantity selector became
active for regular products. The installment payment form appeared only for non-prescription items.

For the buy button implementation, we passed this variable through to the buy-buttons snippet:

{% raw %}

```liquid
{%- when 'buy_buttons' -%}
  {%- render 'buy-buttons',
    block: block,
    product: product,
    product_form_id: product_form_id,
    section_id: section.id,
    show_pickup_availability: true,
    is_prescription_product: is_prescription_product
  -%}
```

{% endraw %}

Within the buy-buttons snippet, we implemented a clean conditional structure:

{% raw %}

```liquid
{%- if is_prescription_product -%}
  <a href="https://go.ozio.com/?product={{ product.handle }}" 
     class="button button--full-width button--primary"
     target="_blank"
     rel="noopener">
    Get Your Prescription Kit
  </a>
  <p class="prescription-disclaimer caption">
    You will be redirected to Bask Health's secure site for prescription fulfillment.
  </p>
{%- else -%}
  <!-- Original add to cart button code -->
{%- endif -%}
```

{% endraw %}

This variable was passed through to snippets, maintaining clean separation of concerns. Each component made its own
decisions based on the product type, but the logic remained centralized and maintainable.

## The Results

The implementation delivered exactly what the client needed with minimal code changes. By preserving the original
structure and adding conditional logic, we achieved:

- **Zero functionality loss** – Regular products retained all Shopify features including quantity selection, installment
  payments, and native checkout
- **Seamless prescription handling** – Prescription products displayed streamlined pages with clear calls-to-action
  directing to Bask Health
- **Maintainable codebase** – Theme updates can be applied without rewriting custom logic
- **Flexible expansion** – Adding new product types or conditions requires minimal effort

Most importantly, the client maintained full control. They can easily identify prescription products using Shopify's
built-in features (tags, product types, or collections) without touching code. The solution scales with their business
rather than constraining it.

{::nomarkdown}
{% include testimonial.html person="jennifer" quote="professional" %}
{:/nomarkdown}

## Key Takeaways

This project reinforced several important lessons for strategic code modification:

1. **Comment First, Delete Never**: Preserving existing code through comments provides invaluable flexibility for future
   requirements
2. **Centralized Logic**: A single source of truth for conditional behavior prevents scattered decision-making
   throughout the codebase
3. **Minimal Touch Points**: The fewer files you modify, the easier maintenance becomes
4. **Respect Existing Architecture**: Work with the theme's structure rather than against it

In custom development, the best solution isn't always the most dramatic. Sometimes, the most elegant approach is the
one that respects existing systems while adding just enough intelligence to meet new requirements. By commenting first
and adding logic second, we created a solution that's both powerful and maintainable – exactly what growing businesses
need.
