---
layout: page
title: What People Say About Us
permalink: "/testimonials/"
description: >-
  Client testimonials and recommendations showcasing expertise in Unity development, Rails consulting, and technical 
  leadership.
---

*These testimonials are excerpted from letters of recommendation and client feedback.*

## Testimonials by Topic

{% assign sorted_categories = site.data.testimonial-categories.categories | sort: "order" %}
{% for category in sorted_categories %}
### {{ category.icon}} {{ category.display_name }}
{{ category.description }}

{::nomarkdown}
{% include testimonial-carousel.html topic=category.key %}
{:/nomarkdown}

{% unless forloop.last %}---{% endunless %}

{% endfor %}

## Ready to Work Together?

[Get in touch](/contact/) to discuss how I can help with your Unity development or Rails consulting needs.
