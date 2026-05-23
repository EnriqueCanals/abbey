require "redcarpet"
require "rouge"
require "rouge/plugins/redcarpet"

module Redcarpet
  module Render
    # Output minimal, semantic HTML and let `.prose-retro` styles
    # in app/assets/stylesheets/application.tailwind.css do the heavy lifting.
    class TailwindHTML < ::Redcarpet::Render::HTML
      def normal_text(text)
        text
      end

      def block_code(code, language)
        <<~HTML
          <pre class="highlight #{language}"><code>#{code}</code></pre>
        HTML
      end

      def header(title, level)
        "<h#{level}>#{title}</h#{level}>"
      end

      def paragraph(text)
        "<p>#{text}</p>"
      end

      def list(content, list_type)
        tag = list_type == :ordered ? "ol" : "ul"
        "<#{tag}>#{content}</#{tag}>"
      end

      def list_item(content, list_type)
        "<li>#{content}</li>"
      end

      def link(link, title, content)
        "<a href=\"#{link}\"#{title ? " title=\"#{title}\"" : ""}>#{content}</a>"
      end

      def emphasis(text)
        "<em>#{text}</em>"
      end

      def double_emphasis(text)
        "<strong>#{text}</strong>"
      end

      def block_quote(quote)
        "<blockquote>#{quote}</blockquote>"
      end

      def hrule
        "<hr/>"
      end

      def image(link, title, alt_text)
        "<img src=\"#{link}\" alt=\"#{alt_text}\"#{title ? " title=\"#{title}\"" : ""}/>"
      end
    end
  end
end

class MarkdownRender < Redcarpet::Render::TailwindHTML
  include Rouge::Plugins::Redcarpet
end
