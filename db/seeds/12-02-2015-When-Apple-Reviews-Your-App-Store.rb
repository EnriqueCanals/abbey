body = <<~MARKDOWN
  #__February 12, 2015__

  **_Notes on architecting a third-party watchface catalog when the install surface is rendered inside someone else's iOS app._**

  This is a follow-up to the [Pebble App Store post](/blog/2014/06/15/building-the-pebble-app-store-with-ember-js-and-rails) from last summer, focused on the part of that project I spent the most time thinking about and the least time talking about publicly: the architectural problem of running a software distribution channel for a wearable device through a mandatory iOS companion app. We hit it head-on shipping the new store, and it shaped a surprising amount of our engineering — both the things we built and the things we decided not to ship.

  ## The install path

  Here is how a user installs a watchface on Pebble in 2015:

  1. They open the Pebble companion app on their iPhone.
  2. The companion app renders our store, served by the Rails API I wrote about last summer.
  3. They tap "Add" on a watchface.
  4. The companion app pushes the `.pbw` to the watch over Bluetooth.

  Step 2 is the interesting one. The store lives inside an iOS app that has to clear App Store Review for every release. That is a property of the install surface, not of the store itself, and it has consequences.

  The clauses from the App Store Review Guidelines that mattered to us, paraphrased:

  * Any digital content or functionality consumed inside an iOS app must use In-App Purchase, which carries a 30% platform fee.
  * You cannot link out to a website to buy the same content.
  * Executable code that runs inside the iOS app must have been reviewed at the time the app was reviewed.

  That last clause is where things got architecturally interesting.

  ## Why JS-in-companion-app is the hard part

  Pebble.js and the PebbleKit JS framework let watchface developers run JavaScript that talks to web services — fetching weather, scores, transit times, anything network-related. The watch hardware itself doesn't run JS. The JS executes in a sandboxed runtime inside the iOS companion app, and the results get pushed to the watch over Bluetooth.

  This is a sensible architecture for a constrained device. The watch stays small and the heavy lifting happens on a phone that already has a network stack, a JS engine, and a battery you can recharge daily. It is also where the review tension lives. From the host platform's point of view, every `.pbw` with a JS payload is code that has not been individually reviewed shipping into an app that has. From our point of view, the JS is content for the watch and the iOS app is a transport.

  When we relaunched the catalog inside the iOS companion, the JS-in-companion pattern became newly visible. The old "locker" was a hidden install path; the new store is a browsable, beautifully-rendered catalog. The shift in surface area is what changed the conversation. Resolving review notes started showing up on the path to every companion-app release.

  ## The decision tree

  Once it was clear the JS-in-companion model was the surface that mattered, we wrote out the design space. The four options we modeled:

  **A. Submit every watchface through Apple Review.** We have thousands of watchfaces with JS components in the catalog, and hundreds of updates a week from independent developers. App Review turnaround is 7–10 days. The arithmetic does not close, even before you ask developers to give up direct publishing.

  **B. Strip JS entirely.** Remove PebbleKit JS, remove Pebble.js, tell the community the feature they have built two years of work on is gone. Beyond the trust cost, this removes the only meaningful escape hatch developers have for network functionality. Not viable.

  **C. Move JS execution to the watch.** The watch does not have a JS runtime today. Adding one is a firmware project plus a hardware refresh: more RAM, a bigger battery budget, probably a chip change. Maybe a future generation, definitely not 2015.

  **D. Ship paid apps via In-App Purchase.** The catalog supports paid apps. The developer portal has half a pricing UI behind a feature flag. We modeled the unit economics three different ways with a 30% IAP cut. At the price points where most of our developers would land — $0.99–$2.99 — the flat margin eats the long tail. We deferred it.

  ## The mitigations we shipped

  We didn't escape the constraint, but we softened its surface area. A few of the technical investments that came out of it:

  **Per-app JS sandboxing with explicit limits.** Each watchface's JS runs in its own context with bounded memory, bounded execution time, and an explicit allowlist of bridged APIs. The companion app's JS host makes the boundary inspectable, which turned out to matter when we needed to describe what code is allowed to do.

  **Server-side static analysis at upload.** Every `.pbw` upload triggers a Sidekiq job that scans the bundled JS for patterns we have learned cause problems: `eval` of remote strings, dynamic script injection, attempts to monkey-patch the bridge layer, network calls to non-declared origins. Failures reject the upload in the developer portal with actionable error messages, so the developer sees the issue immediately rather than discovering it three weeks later when a companion-app release is held up.

  ```ruby
  class JsPayloadScanner
    REJECT_PATTERNS = {
      /\\beval\\s*\\(/                       => "eval() of dynamic strings is not allowed",
      /\\bnew\\s+Function\\s*\\(/            => "Function constructor not allowed",
      /document\\.write\\s*\\(/              => "document.write() not allowed",
      /\\b(?:XMLHttpRequest|fetch)\\s*\\(/   => "use Pebble.request() instead"
    }

    def call(source)
      REJECT_PATTERNS.each do |pattern, reason|
        if (match = source.match(pattern))
          return Rejected.new(reason: reason, position: match.begin(0))
        end
      end
      Accepted
    end
  end
  ```

  **Catalog redesigned around curation.** The store surface in both the web app and the companion app leans heavily on editorial: editor's picks, themed collections, featured developers. This was a product decision before it was a review consideration, but the side effect is a surface that reads as discovery rather than as a transactional storefront, which simplified a lot of conversations.

  **Versioned manifests, recoverable updates.** Because every `.pbw` upload becomes a `Version` record server-side (with the binary held in S3 and the metadata in Postgres), we can roll back the latest published version of any application with a single API call. That meant we could push aggressive validation rules without breaking developers — a bad upload doesn't reach a user's watch, and a regression can be undone without anyone needing to push another build.

  ## What stayed deferred

  The paid store stayed in the drawer for 2015. The catalog ships free-only, with the existing tip-jar pattern as the monetization path. That is fine for the moment — the community is enormous and is shipping for reasons other than money — but it is clearly leaving value on the table for the people doing the most ambitious work. We will keep modeling alternatives.

  ## What I would tell the next person

  A few architectural takeaways I wrote down to refer to later:

  1. **The install surface is the constraint, not the catalog.** Anywhere you are shipping software through someone else's app, design as if the host's rules are inputs to your roadmap, because they are.
  2. **Async validation pushes the conversation upstream.** Catching review-risky patterns at upload time, in the developer portal, costs vastly less than catching them at companion-app release time. Build that layer early — the day you ship a developer portal is the day to ship the scanner behind it.
  3. **A versioned catalog with rollback turns review risk into a recoverable failure mode.** The combination of "every upload is a Version" + "the API serves a single published Version" is more powerful than it sounds. It lets you experiment without paying compounding distribution debt.
  4. **Curation is an architectural decision.** What is promoted, what is discoverable, what is transactional — these shape the review surface as much as they shape the product. We changed the answer to all three and the conversation around the store changed with it.

  More posts coming as we keep shipping. If you are a Pebble developer hitting any of the upload-time validation rules and the message is not useful, send me a note — we will either fix the wording or relax the rule.
MARKDOWN

begin
  Post.create!(
    title: "Shipping a Watchface Store Inside an iOS Companion App",
    created_at: "February 12, 2015",
    markdown_body: body,
    markdown_excerpt: "Notes on architecting a third-party app catalog when the install surface is rendered inside someone else's iOS app, and the engineering tradeoffs that come with it.",
    post_tags: "pebble,app-store,wearables,javascript,ios,architecture"
  )
  puts "Imported Shipping a Watchface Store Inside an iOS Companion App"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 12-02-2015-When-Apple-Reviews-Your-App-Store: #{e.message}"
rescue => e
  puts "Unexpected error importing 12-02-2015-When-Apple-Reviews-Your-App-Store: #{e.message}"
end
