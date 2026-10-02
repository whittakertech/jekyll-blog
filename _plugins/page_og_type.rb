# frozen_string_literal: true

# jekyll-seo-tag emits og:type=article (and article:published_time) for anything with a
# `date`, and Jekyll gives every collection document one. Only posts are articles, so
# rewrite the rest as plain website pages after rendering. Posts use _includes/meta/post.html.
Jekyll::Hooks.register :documents, :post_render do |document|
  next if document.collection.label == "posts" || document.output.nil?

  document.output = document.output
                            .sub('<meta property="og:type" content="article" />', '<meta property="og:type" content="website" />')
                            .sub(%r{\s*<meta property="article:published_time"[^>]*/>}, "")
                            .sub(/"datePublished":"[^"]*",/, "")
end
