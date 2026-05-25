module ApplicationHelper
  # Override Propshaft's `:app` bulk inclusion so the per-theme assets
  # (tailwind-<name>.css and every file from app/themes/<name>/assets/)
  # are NOT auto-included with the rest of the app bundle. They belong
  # to optional themes and are loaded separately via #theme_stylesheets
  # only when their theme is active. This keeps the default theme bundle
  # byte-for-byte unchanged regardless of how many themes ship.
  def app_stylesheets_paths
    excluded = theme_excluded_logical_paths
    super.reject do |path|
      slug = path.to_s.delete_suffix(".css")
      slug.start_with?("themes/") || excluded.include?(slug)
    end
  end

  # Emit a block of <meta> + <link rel="canonical"> tags suitable for
  # link previews on Slack, iMessage, Telegram, LinkedIn, X/Twitter,
  # Facebook, Discord, etc.
  #
  # Called once from each layout's <head>; individual show templates can
  # override per-page values by wrapping their own call in
  #   <% content_for :meta do %><%= meta_tags(title:, description:, …) %><% end %>
  #
  # Options (all optional, fall back to site_settings.rb defaults):
  #   title:          page title (without site_name suffix)
  #   description:    short one-or-two-sentence summary
  #   image:          absolute URL or /public path for og:image
  #   url:            canonical URL (defaults to request.path on current host)
  #   type:           OG type: "website" (default), "article", "profile", …
  #   author:         override site_author (article author byline)
  #   published_time: ISO 8601 timestamp for article:published_time
  #   updated_time:   ISO 8601 timestamp for article:modified_time
  #   tags:           Array<String> of article:tag values
  def meta_tags(opts = {})
    cfg = Rails.application.config
    page_title  = opts[:title].presence
    description = sanitize_meta_description(opts[:description].presence || cfg.try(:site_description))
    image_src   = opts[:image].presence || cfg.try(:site_image).presence
    image_url   = image_src && absolute_meta_url(image_src)
    canonical   = opts[:url].presence || default_canonical_url
    og_type     = opts[:type].presence || "website"
    site_name   = cfg.site_name
    author      = opts[:author].presence || cfg.try(:site_author).presence
    twitter_h   = cfg.try(:site_twitter).presence
    og_title    = page_title || site_name
    twitter_card = image_url ? "summary_large_image" : "summary"

    parts = []

    # Standard
    parts << tag.meta(name: "description", content: description) if description
    parts << tag.meta(name: "author",      content: author)      if author
    parts << tag.link(rel:  "canonical",   href: canonical)      if canonical

    # Open Graph (Facebook, LinkedIn, Slack, iMessage, Telegram, Discord)
    parts << tag.meta(property: "og:site_name", content: site_name)
    parts << tag.meta(property: "og:title",     content: og_title)
    parts << tag.meta(property: "og:type",      content: og_type)
    parts << tag.meta(property: "og:url",       content: canonical)   if canonical
    parts << tag.meta(property: "og:description", content: description) if description
    parts << tag.meta(property: "og:locale",    content: cfg.try(:site_locale) || "en_US")
    if image_url
      parts << tag.meta(property: "og:image",        content: image_url)
      parts << tag.meta(property: "og:image:alt",    content: og_title)
    end

    # Article-specific OG
    if og_type == "article"
      parts << tag.meta(property: "article:published_time", content: opts[:published_time]) if opts[:published_time].present?
      parts << tag.meta(property: "article:modified_time",  content: opts[:updated_time])   if opts[:updated_time].present?
      parts << tag.meta(property: "article:author",         content: author)                 if author
      Array(opts[:tags]).each do |tag_name|
        parts << tag.meta(property: "article:tag", content: tag_name.to_s)
      end
    end

    # Twitter Card
    parts << tag.meta(name: "twitter:card",        content: twitter_card)
    parts << tag.meta(name: "twitter:title",       content: og_title)
    parts << tag.meta(name: "twitter:description", content: description) if description
    parts << tag.meta(name: "twitter:image",       content: image_url)   if image_url
    parts << tag.meta(name: "twitter:image:alt",   content: og_title)    if image_url
    parts << tag.meta(name: "twitter:site",        content: twitter_h)   if twitter_h
    parts << tag.meta(name: "twitter:creator",     content: twitter_h)   if twitter_h

    safe_join(parts, "\n")
  end

  # Returns the logical names of every stylesheet the active theme ships,
  # suitable for `stylesheet_link_tag`. Always includes the per-theme
  # Tailwind bundle first (`tailwind-<name>`), then any extra CSS files
  # the theme contributes from its `assets/` folder. The default theme
  # contributes nothing extra.
  #
  # Resolution order:
  #   1. `tailwind-<active>` (compiled by `themes:tailwind:build`) so
  #      theme tokens land before component CSS that references them.
  #   2. Manifest-declared stylesheets (filesystem scan of assets/, with
  #      tailwind.css excluded since it's the compiler input, not output).
  #   3. Legacy `themes/<name>` / `themes/<name>-highlight` fallback for
  #      code paths that haven't moved to the consolidated folder.
  def theme_stylesheets
    theme = Abbey::Theme.active
    return [] if theme.default?

    sheets = []
    sheets << "tailwind-#{theme.name}" if theme_stylesheet_exists?("tailwind-#{theme.name}")

    candidates = theme.stylesheets
    candidates = [
      "themes/#{theme.name}",
      "themes/#{theme.name}-highlight"
    ] if candidates.empty?

    sheets.concat(candidates.select { |name| theme_stylesheet_exists?(name) })
  end

  # Whether dark mode is currently active on the request. The chrome
  # partial uses this to pick between the active theme's dark_html_class
  # and light_html_class.
  def dark_mode?
    cookies[:dark_mode] == "true"
  end

  # Build the `class="..."` value for the chrome partial's <html> element
  # by combining the active theme's always-on classes with its
  # dark/light variants based on the request's dark mode state.
  def chrome_html_class(theme = Abbey::Theme.active)
    parts = [
      theme.html_class,
      dark_mode? ? theme.dark_html_class : theme.light_html_class
    ]
    parts.compact.reject(&:blank?).join(" ").presence
  end

  private

  # Strip light markdown markers (headings, emphasis, code fences, links,
  # blockquotes), inline HTML tags, collapse whitespace, and truncate.
  # Post excerpts and page bodies often contain raw markdown / inline
  # HTML that looks awful in a link preview ("__Aug 1__ ## Step 1: ..."
  # → "Aug 1 Step 1: ..."). Truncates to 155 chars (optimal for iMessage/OG preview tester,
  # Slack, Telegram, X all handle up to 200 but 155 is the safe cross-platform max).
  def sanitize_meta_description(text)
    return nil if text.blank?
    # Decode entities first so any escaped HTML (e.g. `&lt;br/&gt;`
    # stored verbatim in a page body) becomes real `<...>` and gets
    # stripped by the tag regex below.
    cleaned = CGI.unescapeHTML(text.to_s)
                 .gsub(/```.*?```/m, "")                        # fenced code blocks
                 .gsub(/<[^>]+>/, " ")                          # inline HTML tags
                 .gsub(/`[^`]+`/, "")                           # inline code
                 .gsub(/!\[([^\]]*)\]\([^)]+\)/, '\1')          # ![alt](url) -> alt
                 .gsub(/\[([^\]]+)\]\([^)]+\)/, '\1')           # [text](url) -> text
                 .gsub(/^[>\s]+/, "")                           # blockquote markers
                 .gsub(/[#*_~]+/, "")                           # heading/emphasis chars
                 .squish
    cleaned.length > 155 ? cleaned[0, 152] + "..." : cleaned.presence
  end

  # Resolve `path` to an absolute URL. Pass-through if already absolute.
  # Used for og:image so previews work when the page is fetched by a
  # remote scraper (which can't follow `/og.png` style relative paths).
  def absolute_meta_url(path)
    return path if path =~ %r{\Ahttps?://}i
    return path unless request

    base = "#{request.protocol}#{request.host_with_port}"
    "#{base}#{path.to_s.start_with?("/") ? path : "/#{path}"}"
  end

  # Canonical URL for the current request, query string stripped (so
  # ?ref=… utm_*=… don't pollute the canonical / og:url).
  def default_canonical_url
    return nil unless request
    "#{request.protocol}#{request.host_with_port}#{request.path}"
  end

  def theme_stylesheet_exists?(logical_name)
    Rails.application.assets&.load_path&.find("#{logical_name}.css").present? ||
      Rails.root.join("app/assets/stylesheets/#{logical_name}.css").exist?
  rescue StandardError
    Rails.root.join("app/assets/stylesheets/#{logical_name}.css").exist?
  end

  # Every logical asset path contributed by any registered theme. Used
  # by `app_stylesheets_paths` to exclude theme assets from the default
  # bundle without hard-coding any theme name.
  def theme_excluded_logical_paths
    @_theme_excluded_logical_paths ||= Abbey::Theme.registry.flat_map do |name, theme|
      ["tailwind-#{name}"] + theme.stylesheets
    end.to_set
  end
end
