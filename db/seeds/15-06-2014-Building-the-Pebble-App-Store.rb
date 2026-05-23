body = <<~MARKDOWN
  #__June 15, 2014__

  **_How we built a watchface marketplace on Ember.js and Rails for a wrist-sized computer._**

  For the past several months I've had my head buried in what is easily the most fun project I've worked on in a while: the new Pebble App Store. When the Hybrid Group took on the contract to help Pebble ship a proper marketplace for watchfaces and apps, I jumped at the chance to work on it. Smartwatches are still very much an open question in 2014, and watching a small team in Palo Alto try to define an entire developer ecosystem from scratch is the kind of problem that doesn't come along often.

  This post is about the web side of that project: the public-facing app store and the developer portal that backs it, both built on Ember.js with a Rails API behind them.

  ## The brief

  Pebble already had a "locker" inside its mobile companion apps where users could install watchfaces. What they didn't have was a real storefront. They needed:

  * A browsable, searchable catalog of every watchface and watchapp ever published
  * Categories, collections, and an editorial surface so the curation team could promote things
  * A developer portal where someone could upload a `.pbw` bundle, write a description, manage screenshots, and ship a new version
  * An API the mobile apps (iOS and Android) could consume to render the same store inside the companion app
  * Search that didn't fall over the first time someone typed "fuubu"

  The constraint that shaped everything: the store inside the iPhone and Android app had to feel native, but it had to be served from the web. That meant the API needed to be the source of truth and the web client needed to be fast enough that the same JSON payloads could power the in-app experience.

  ## Why Ember

  We went back and forth on this for about a week. Backbone was the obvious safe choice and Angular was on everyone's mind, but neither of them felt right for the shape of the problem. The store is, fundamentally, a deeply nested CRUD app sitting on top of a REST API: applications have versions, versions have assets, applications belong to developers, developers belong to companies, applications have categories, categories have collections, and so on. Routes nest. URLs matter. The browser back button has to do the right thing.

  Ember's router and the conventions around `ember-data` map onto that shape really cleanly. Once you accept the framework's opinions, you stop arguing with yourself about where things go. We picked Ember 1.5 (the post-1.0, pre-HTMLBars era), `ember-data` 1.0.0-beta.7, and Handlebars for templates.

  ```javascript
  App.Router.map(function() {
    this.resource('applications', function() {
      this.resource('application', { path: '/:application_id' }, function() {
        this.route('versions');
        this.route('reviews');
      });
      this.route('category', { path: '/category/:slug' });
      this.route('collection', { path: '/collection/:slug' });
    });
    this.resource('developers', function() {
      this.resource('developer', { path: '/:developer_id' });
    });
  });
  ```

  The whole site reads off this map. New surface area is almost always a new route, and the URL falls out of the design instead of being bolted on later. That sounds obvious until you've spent a year in a Backbone app where every view ends up reinventing its own routing.

  ## The Rails side

  The API is Rails 4.1 in API-only mode (`rails-api` gem, since `--api` didn't land until Rails 5). PostgreSQL on the bottom, Sidekiq for background jobs, Redis for caching and for the search index queue. ActiveModel::Serializers for the response envelope so the Ember side could feed responses straight into `ember-data` without a translation layer.

  A few things that made life nicer:

  **Versioned resources.** Every `.pbw` upload creates a new `Version` record attached to the parent `Application`. The store always serves the latest published version, but old ones stick around so we can roll back, diff manifests, and run analytics on adoption curves. The mobile apps pin to a version when they install, so a user's locker survives a developer pushing a broken update.

  **Manifest parsing on upload.** A `.pbw` is just a zip. We unpack it in a Sidekiq job, validate the `appinfo.json`, extract the icon and any JS file, and reject the upload with a useful error message if anything is off. Doing it async meant the upload endpoint just enqueues and returns, which kept the developer portal feeling snappy even when someone uploaded a 2MB bundle over hotel wifi.

  **Sluggable everything.** Every public resource has a slug column populated from its title (`friendly_id` gem). The Ember router uses those slugs, so URLs read like `/applications/timely` instead of `/applications/41873`. Developers care about this more than you'd think; a clean URL is the closest thing they have to a brand on the store.

  ## Talking to a Rails API from Ember

  The cleanest version of this is to make `ember-data` and `ActiveModel::Serializers` agree on a JSON shape and then get out of their way. We used the default `RESTAdapter` with a custom serializer that flattened a couple of nested associations we didn't want to round-trip every time:

  ```javascript
  App.ApplicationSerializer = DS.RESTSerializer.extend({
    normalizePayload: function(payload) {
      if (payload.applications) {
        payload.applications.forEach(function(app) {
          if (app.latest_version && typeof app.latest_version === 'object') {
            payload.versions = payload.versions || [];
            payload.versions.push(app.latest_version);
            app.latest_version = app.latest_version.id;
          }
        });
      }
      return payload;
    }
  });
  ```

  On the Rails side, the matching serializer:

  ```ruby
  class ApplicationSerializer < ActiveModel::Serializer
    attributes :id, :title, :slug, :description, :category_id,
               :icon_url, :screenshot_urls, :hearts, :downloads

    has_one :developer
    has_one :latest_version, serializer: VersionSerializer

    def screenshot_urls
      object.screenshots.map(&:url)
    end
  end
  ```

  The thing I keep coming back to with `ember-data` is that the moment you stop fighting its normalization model, your codebase shrinks by 30%. Sideloaded records, polymorphic relationships, even optimistic updates start to feel like features instead of obstacles.

  ## The developer portal

  This is the part I'm proudest of. The portal is its own Ember app served from the same Rails backend behind an auth wall. A developer logs in, sees their list of applications, drills into one, and gets a single screen where they can:

  * Edit metadata (title, description, category, tags)
  * Upload screenshots by dragging them into the page
  * Upload a new `.pbw`, which kicks off a server-side validation job and shows progress
  * See review status, including any automated rejections (icon too small, missing manifest fields, JS exceeding the heap)
  * Promote a draft version to "published"

  We obsessed over the upload UX. The first version made you fill out a form and hit submit. The version that shipped lets you drag a `.pbw` onto the page and have it validate, parse, and show you what the store will look like before you commit anything. The difference in support tickets between those two versions was dramatic.

  ## Search

  Search is `elasticsearch-rails` against an index that gets rebuilt incrementally as versions get published. Two things were non-obvious:

  1. **Tokenize the title with an ngram analyzer.** Watchface names are short, often made-up words ("Tickr", "Pebbloid", "Timely"). Standard stemming destroys them. An edge-ngram analyzer over titles plus a standard analyzer over descriptions gave us "starts with what I typed" behavior that feels right in a store.
  2. **Boost by recent downloads, not all-time downloads.** When you sort purely by lifetime popularity, the same five watchfaces win forever and the store ossifies. We added a decay function so the past 30 days of installs weighed roughly five times the prior history. Discovery got dramatically better, and developers stopped emailing us about it.

  ## What I learned

  Ember in 2014 is not a framework you adopt lightly. The upgrade treadmill is real, the docs lag the codebase, and the community is still working out idioms. But the moment your app fits into the router-plus-data-store mental model, it pays for itself ten times over. I would not want to build the developer portal in anything else.

  The other thing I learned, which has nothing to do with Ember: a store is a product. The catalog is the product, not the apps in it. Every decision we made about ranking, search, categories, and the developer portal was actually a decision about what the catalog should reward. That's the part I want to keep thinking about as Pebble figures out what comes next.

  More posts coming as we get further into the project. If you're a Pebble developer reading this, please send me feedback — every weird edge case you've hit with our API is something I want to fix.
MARKDOWN

begin
  Post.create!(
    title: "Building the Pebble App Store with Ember.js and Rails",
    created_at: "June 15, 2014",
    markdown_body: body,
    markdown_excerpt: "How we built a watchface marketplace on Ember.js and Rails for a wrist-sized computer, and what I learned about routers, ember-data, and treating a catalog like a product.",
    post_tags: "pebble,ember,rails,javascript,api,wearables"
  )
  puts "Imported Building the Pebble App Store with Ember.js and Rails"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 15-06-2014-Building-the-Pebble-App-Store: #{e.message}"
rescue => e
  puts "Unexpected error importing 15-06-2014-Building-the-Pebble-App-Store: #{e.message}"
end
