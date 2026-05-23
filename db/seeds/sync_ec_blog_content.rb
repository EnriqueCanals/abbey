# Idempotent content-sync script for the ec-blog deployment.
#
# Run inside the production container after a successful kamal deploy:
#
#   bin/kamal app exec --interactive --reuse \
#     "bin/rails runner db/seeds/sync_ec_blog_content.rb"
#
# What it does:
#
# 1. Removes legacy titles that no longer belong (the default "Welcome to
#    Abbey" seed and the old framing of the Pebble x Apple post).
# 2. For every published blog post we expect to see in production, checks
#    whether a Post with that exact title already exists. If not, the
#    matching per-post seed file in db/seeds/ is loaded to create it.
# 3. Ensures the Projects page lists the `harness` project at the top of
#    the page body, idempotently.
#
# Safe to re-run. Touches only Post and Page rows; users, sessions and
# Active Storage data are left alone.

require "pathname"

SEED_ROOT = Rails.root.join("db", "seeds")

LEGACY_POST_TITLES = [
  "Welcome to Abbey!",
  "When Apple Reviews Your App Store: Notes from the Pebble Trenches"
].freeze

EXPECTED_POSTS = [
  [ "Using Rack Applications Inside GWT Hosted Mode",                                "21-09-2009-Rack-Applications-Inside-GWT.rb" ],
  [ "Getting Spree on Heroku in a Few Minutes",                                       "24-02-2012-Spree_heroku.rb" ],
  [ "Getting started with RVM, Homebrew, and zSh on OS X Mountain Lion",              "01-08-2012-RVM_OSX.rb" ],
  [ "Looking for the Power of Two",                                                    "27-04-2013-Finding-the-Power-of-2.rb" ],
  [ "Issues Installing Capybara-Webkit on OS X 10.9 (Mavericks)",                     "11-05-2013-Error-with-capybara-webkit-on-os-x-Mavericks.rb" ],
  [ "Building the Pebble App Store with Ember.js and Rails",                          "15-06-2014-Building-the-Pebble-App-Store.rb" ],
  [ "Shipping a Watchface Store Inside an iOS Companion App",                         "12-02-2015-When-Apple-Reviews-Your-App-Store.rb" ],
  [ "Driving a Robot Ball with JavaScript: Shipping Sphero.js",                       "22-04-2015-Driving-a-Robot-Ball-with-JavaScript.rb" ],
  [ "Telemedicine on WebRTC, HealthKit, and a Hybrid App",                            "03-02-2016-Telemedicine-on-WebRTC.rb" ],
  [ "DNS Filtering at Lambda Scale (and the OpenVPN IPv6 Problem)",                   "18-09-2017-DNS-Filtering-at-Lambda-Scale.rb" ],
  [ "Smart Contracts for Music Royalties: A Year of Vezt",                            "04-11-2018-Smart-Contracts-for-Music-Royalties.rb" ],
  [ "Replatforming from Angular.js to React + Next.js Without Going Dark",            "26-08-2020-Replatforming-from-Angular-to-Next.rb" ],
  [ "Migrating to Aurora MySQL and Rebuilding Environments with Step Functions",      "14-06-2021-Aurora-Migration-with-Step-Functions.rb" ],
  [ "Sandboxed Coding Agents and a Telegram Claw on a Veterinary Monorepo",           "12-04-2026-Sandboxed-Agents-and-a-Telegram-Claw.rb" ]
].freeze

HARNESS_ENTRY = <<~MD.strip
  [harness](https://github.com/capotej/harness)
  Easy containerized agent environments. A CLI that wraps Docker around three open-source coding agents (pi, opencode, hermes) so you can point one at a directory without giving it access to your entire machine. Sandboxed by default, signed images with cosign + SLSA provenance, 7-day dependency cooldown, local-first via LM Studio with optional cloud providers (Anthropic, OpenRouter, OpenAI, Gemini, and more).
MD

def banner(msg)
  bar = "=" * msg.length
  puts ""
  puts bar
  puts msg
  puts bar
end

banner "ec-blog content sync — starting"
puts "Posts in DB before sync: #{Post.count}"
puts "Pages in DB before sync: #{Page.count}"

banner "1. Removing legacy post titles"
LEGACY_POST_TITLES.each do |title|
  Post.where(title: title).find_each do |p|
    puts "  - destroying ##{p.id} #{p.title.inspect}"
    p.destroy
  end
end

banner "2. Loading missing per-post seeds"
EXPECTED_POSTS.each do |(title, file)|
  if Post.exists?(title: title)
    puts "  ok   #{title}"
    next
  end

  path = SEED_ROOT.join(file)
  unless path.exist?
    warn "  SKIP #{title} — seed file not found at #{path}"
    next
  end

  puts "  load #{file} -> #{title}"
  load path.to_s
end

banner "3. Ensuring Projects page has harness entry"
projects = Page.find_by(title: "Projects")
if projects.nil?
  warn "  Projects page not found — skipping"
else
  body = projects.markdown_body.to_s
  if body.include?("github.com/capotej/harness")
    puts "  ok   harness already linked on Projects page"
  else
    new_body = "#{HARNESS_ENTRY}\n\n#{body.lstrip}"
    projects.update!(markdown_body: new_body)
    puts "  prepended harness entry (Projects body now #{new_body.length} chars)"
  end
end

banner "ec-blog content sync — done"
puts "Posts in DB after  sync: #{Post.count}"
puts "Pages in DB after  sync: #{Page.count}"
puts ""
puts "Published posts:"
Post.where(draft: [ nil, false ]).order(:created_at).each do |p|
  puts "  #{p.created_at.to_date}  ##{p.id}  #{p.title}"
end
