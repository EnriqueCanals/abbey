Rails.application.config.site_name = "Enrique Canals"

# Default site-level metadata used by ApplicationHelper#meta_tags to build
# Open Graph / Twitter Card / standard <meta> tags for link previews
# (Slack, iMessage, Telegram, LinkedIn, Twitter/X, Facebook, Discord, etc).
# Individual views can override any of these per-page via
#   <% content_for :meta do %><%= meta_tags(title:, description:, …) %><% end %>

# One-sentence default description — matches the site tagline.
Rails.application.config.site_description = "Field notes from over 20 years on the web."

# Byline shown as `author` + `article:author`.
Rails.application.config.site_author = "Enrique Canals"

# Page locale (BCP 47 → underscored for OG).
Rails.application.config.site_locale = "en_US"

# Optional Twitter/X handle including the leading "@" (e.g. "@enriquec").
# Leave nil to omit twitter:site / twitter:creator.
Rails.application.config.site_twitter = nil

# Default Open Graph image. Should be an absolute URL or a path under
# /public (resolved to absolute by the helper). Leave nil to fall back to
# Twitter `summary` (text-only) card. 1200x630 PNG/JPG recommended.
#
# og-default.png is a 1200x630 branding card used whenever a page or post
# does not supply its own image. Required by iMessage LinkPresentation and
# most other link-unfurl scrapers (Slack, Telegram, LinkedIn, Discord).
Rails.application.config.site_image = "/og-default.png"
