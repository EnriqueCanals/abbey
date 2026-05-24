require "test_helper"

class ThemesTest < ActionDispatch::IntegrationTest
  # The theme is read from Rails.application.config.theme at boot time, so we
  # exercise theme switching by toggling it in place around each request.
  setup do
    @original_theme = Rails.application.config.theme
  end

  teardown do
    Rails.application.config.theme = @original_theme
  end

  test "default theme renders the original layout" do
    Rails.application.config.theme = "default"

    get root_path
    assert_response :success
    assert_no_match(/class="theme-retro/, response.body)
    assert_no_match(/class="theme-grimoire/, response.body)
    assert_no_match(%r{/assets/retro[-/]},     response.body, "default theme should not load retro CSS")
    assert_no_match(%r{/assets/grimoire[-/]},  response.body, "default theme should not load grimoire CSS")
    assert_select "header h1"
    assert_select "footer"
  end

  test "retro theme prepends its view path and loads theme stylesheets" do
    Rails.application.config.theme = "retro"

    get root_path
    assert_response :success
    assert_match(/class="theme-retro/, response.body)
    assert_match(%r{/assets/tailwind-retro[-.]}, response.body, "retro theme should load its Tailwind bundle")
    assert_match(%r{/assets/retro[-.]},           response.body, "retro theme should load retro.css")
    assert_match(%r{/assets/retro-highlight[-.]}, response.body, "retro theme should load retro-highlight.css")
    # System test contract: header still has h1, footer still present.
    assert_select "header h1"
    assert_select "footer"
    # Required nav links remain after retheming.
    %w[Home About Projects Presentations Links Papers].each do |label|
      assert_match(/>#{label}</, response.body, "retro nav should contain link: #{label}")
    end
  end

  test "grimoire theme prepends its view path and loads theme stylesheets" do
    Rails.application.config.theme = "grimoire"

    get root_path
    assert_response :success
    assert_match(/class="theme-grimoire/, response.body)
    assert_match(%r{/assets/tailwind-grimoire[-.]}, response.body, "grimoire theme should load its Tailwind bundle")
    assert_match(%r{/assets/grimoire[-.]},           response.body, "grimoire theme should load grimoire.css")
    assert_match(%r{/assets/grimoire-highlight[-.]}, response.body, "grimoire theme should load grimoire-highlight.css")
    # System test contract: header still has h1, footer still present.
    assert_select "header h1"
    assert_select "footer"
    # Required nav links remain after retheming.
    %w[Home About Projects Presentations Links Papers].each do |label|
      assert_match(/>#{label}</, response.body, "grimoire nav should contain link: #{label}")
    end
  end

  test "renderer follows theme configuration" do
    Rails.application.config.theme = "default"
    assert_equal MarkdownRender, Post.markdown_renderer,
                 "default theme should use the original utility-class renderer"

    Rails.application.config.theme = "retro"
    assert_equal MinimalMarkdownRender, Post.markdown_renderer,
                 "retro theme should switch to the minimal renderer"

    Rails.application.config.theme = "grimoire"
    assert_equal MinimalMarkdownRender, Post.markdown_renderer,
                 "grimoire theme should switch to the minimal renderer"
  end

  test "meta_tags renders site defaults on the index" do
    get root_path
    assert_response :success
    body = response.body

    assert_match %r{<meta property="og:site_name" content="Enrique Canals"}, body
    assert_match %r{<meta property="og:title" content="Enrique Canals"},     body
    assert_match %r{<meta property="og:type" content="website"},             body
    assert_match %r{<meta property="og:url" content="http://},               body
    assert_match %r{<meta property="og:description" content="Field notes from over 20 years on the web\.}, body
    assert_match %r{<meta name="twitter:card" content="summary"},            body
    assert_match %r{<link rel="canonical" href="http://},                    body
    assert_no_match %r{<meta property="article:},                             body, "index should not emit article:* tags"
  end

  test "meta_tags renders article-specific tags on a blog post" do
    post_record = posts(:hello_world)
    get dated_post_path(year: post_record.year, month: post_record.month, day: post_record.day, id: post_record.slug)
    assert_response :success
    body = response.body

    assert_match %r{<meta property="og:type" content="article"},                       body
    assert_match %r{<meta property="og:title" content="Hello World"},                  body
    assert_match %r{<meta property="og:description" content="Welcome to the blog\."},  body
    assert_match %r{<meta property="article:published_time" content="\d{4}-\d{2}-\d{2}T}, body
    assert_match %r{<meta property="article:author" content="Enrique Canals"},          body
    assert_match %r{<meta name="twitter:title" content="Hello World"},                  body
    canonical_url = "/blog/#{post_record.year}/#{format('%02d', post_record.month)}/#{format('%02d', post_record.day)}/#{post_record.slug}"
    assert_match %r{<meta property="og:url" content="http://[^"]+#{Regexp.escape(canonical_url)}"}, body
  end

  test "meta_tags strips markdown markers from page bodies for description" do
    # Page#before_create assigns slug from title; pass title only.
    page = Page.create!(
      title: "Mixed Markdown Page",
      markdown_body: "## Heading\n\nThis page has __bold__, `inline code`, [a link](https://example.com), <br/> and an entity &lt;br/&gt;."
    )
    get "/p/#{page.slug}"
    assert_response :success
    body = response.body

    desc_match = body.match(/<meta name="description" content="([^"]+)"/)
    assert desc_match, "expected a description meta tag"
    desc = desc_match[1]

    refute_match %r{[#*_~`]}, desc, "description should have no leftover markdown markers"
    refute_match %r{<[^>]+>}, desc, "description should have no raw HTML tags"
    refute_match %r{&lt;|&gt;}, desc, "description should have no leftover escaped HTML entities"
    assert_includes desc, "Heading"
    assert_includes desc, "bold"
    assert_includes desc, "a link"
  end

  test "meta_tags emits twitter:card summary when no site_image is configured" do
    get root_path
    assert_response :success
    assert_match %r{<meta name="twitter:card" content="summary">}, response.body
    assert_no_match %r{<meta property="og:image"},                 response.body
  end

  test "theme_stylesheets helper is empty for default and populated for named themes" do
    helper = Class.new { include ApplicationHelper }.new

    Rails.application.config.theme = "default"
    assert_empty helper.theme_stylesheets

    Rails.application.config.theme = "retro"
    sheets = helper.theme_stylesheets
    assert_includes sheets, "retro"
    assert_includes sheets, "retro-highlight"

    Rails.application.config.theme = "grimoire"
    sheets = helper.theme_stylesheets
    assert_includes sheets, "grimoire"
    assert_includes sheets, "grimoire-highlight"
  end
end
