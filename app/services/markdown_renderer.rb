# frozen_string_literal: true

# app/services/markdown_renderer.rb
#
# Renders Markdown to HTML using Redcarpet.
#
# == Usage
#
#   MarkdownRenderer.render("# Hello\nWorld")
#   # => "<h1>Hello</h1>\n<p>World</p>\n"
#
class MarkdownRenderer
  RENDERER = Redcarpet::Render::HTML.new(
    hard_wrap: true,
    filter_html: false,
    link_attributes: { target: '_blank', rel: 'noopener noreferrer' }
  )

  MARKDOWN = Redcarpet::Markdown.new(
    RENDERER,
    autolink: true,
    tables: true,
    fenced_code_blocks: true,
    strikethrough: true,
    superscript: true,
    no_intra_emphasis: true
  )

  def self.render(text)
    return '' if text.blank?

    MARKDOWN.render(text).html_safe
  end
end
