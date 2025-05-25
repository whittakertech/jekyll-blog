---
layout: home
title: Home
description: >
  Unity development, Rails consulting, and custom software solutions for games and web applications
permalink: /
---

# Game Development & Technical Services

I'm a software engineer specializing in **Unity game development** and **Ruby on Rails consulting**. I help indie
developers build better games and growing businesses solve complex technical challenges.

## What I Do

**Game Development**

- Unity plugins and tools for the Asset Store
- Custom game development and prototyping
- Performance optimization and technical consulting
- 3D assets and procedural generation systems

**Technical Services**

- Ruby on Rails application development and upgrades
- Legacy system modernization and migration
- International character encoding solutions
- Custom e-commerce integrations and Shopify development

---

## Recent Blog Posts

{% for post in site.posts limit:3 %}
### [{{ post.headline }}]({{ post.url }})
*{{ post.date | date: "%B %d, %Y" }} | {{ post.categories | join: ", " }}*

{{ post.description | default: post.excerpt | strip_html | truncate: 150 }}

<br>

{% endfor %}

[View all posts →](/blog/)

---

## Let's Work Together

Whether you need Unity development expertise or Rails consulting services, I'm here to help turn your technical
challenges into solutions.

**Ready to start?** [Get in touch](/contact/) to discuss your project.

---

*Building games and solving problems, one line of code at a time.*
