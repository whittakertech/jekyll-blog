---
layout: page
title: What People Say About Us
permalink: "/testimonials/"
description: >-
  Client testimonials and recommendations showcasing expertise in Unity development, Rails consulting, and technical 
  leadership.
---
{% assign sorted_categories = site.data.testimonial-categories.categories | sort: "order" %}

*These testimonials are excerpted from letters of recommendation and client feedback.*

## Testimonials by Topic

{% for category in sorted_categories %}
### {{ category.icon}} {{ category.display_name }}
{{ category.description }}

{::nomarkdown}
{% include testimonial-carousel.html topic=category.key %}
{:/nomarkdown}

{% unless forloop.last %}---{% endunless %}

{% endfor %}

## Testimonials by Person

{% for person in site.data.testimonials %}
### {{ person.name }}
*{{ person.title }}, {{ person.company }}* • {{ person.relationship }}

{% for quote in person.quotes %}
{% assign quote_key = quote[0] %}
{% assign quote_text = quote[1] %}

{% assign category = null %}
{% for cat in sorted_categories %}
  {% if cat.key == quote_key %}
    {% assign category = cat %}
    {% break %}
  {% endif %}
{% endfor %}

{% if category %}

{% capture header %}
{{ category.icon }} {{ category.display_name }}
{% endcapture %}

{::nomarkdown}
{% include accordion.html header=header content=quote_text %}
{:/nomarkdown}

{% endif %}

{% endfor %}

---

{% endfor %}

## Ready to Work Together?

[Get in touch](/contact/) to discuss how I can help with your Unity development or Rails consulting needs.
