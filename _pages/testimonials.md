---
layout: page
title: What Clients Say
permalink: "/testimonials/"
description: >-
  Client testimonials and recommendations showcasing expertise in Unity game development, Rails consulting, and 
  technical leadership.
tabs:
  - name: "By Topic"
    include: "testimonials-topics.html"
  - name: "By Person"
    include: "testimonials-people.html"
---
{% assign sorted_categories = site.data.testimonial-categories.categories | sort: "order" %}

*These testimonials are excerpted from letters of recommendation and client feedback.*

{::nomarkdown}
{% include tabs.html tabs=page.tabs %}
{:/nomarkdown}

## Ready to Work Together?

[Get in touch](/contact/) to discuss how I can help with your Unity development or Rails consulting needs.
