body = <<~MARKDOWN
  #__February 12, 2015__

  **_What happens when your watchface marketplace becomes Apple's problem two months before they ship a watch of their own._**

  Two months from now, Apple is going to ship the Apple Watch. I know this because every conversation we've had with Apple in the last six months has had that fact sitting in the middle of the room like a piece of furniture nobody wants to acknowledge.

  This post is about the wall we hit trying to ship a payments story for the Pebble App Store, and what we ended up doing about it. I'm going to leave out the names of specific people and the exact dates of specific phone calls because there's a version of this that ends in a lawsuit and I'd like to avoid being a footnote in it. But the technical and business reality is worth writing down, because I think we're going to look back on early 2015 as the moment a lot of independent hardware ecosystems found out exactly how independent they actually were.

  ## The premise

  Pebble has a developer community that punches enormously above its weight. There are people out there shipping watchfaces that have been installed hundreds of thousands of times, built in their spare time, monetized with exactly zero infrastructure. The new Pebble App Store gives us a real catalog, real distribution, and the foundations to start paying these developers for their work. A paid app tier is the obvious next step. We've been building toward it for months.

  The catalog supports it. The API supports it. The developer portal has half of a pricing UI hidden behind a feature flag. We have a payments provider lined up. The plan was: developers pick a price, users tap "Buy," money moves, Pebble takes a small platform fee, the developer gets the rest, everyone goes home happy.

  Then we sat down and actually read the App Store Review Guidelines all the way through.

  ## The problem nobody wants to talk about

  The Pebble watchface store does not live in a vacuum. The way a user installs a watchface is:

  1. They open the Pebble companion app on their iPhone.
  2. The companion app renders our store (over the API we built).
  3. They tap "Add" on a watchface.
  4. The companion app pushes the `.pbw` to the watch over Bluetooth.

  Step 2 is the trap. The store is rendered inside an iOS app that Apple has to approve. And Apple's rules on what an iOS app is allowed to do with money are, charitably, expansive.

  The relevant clauses, paraphrased:

  * Any digital content or functionality that is consumed inside an iOS app must be purchased through Apple's In-App Purchase system, which means Apple gets 30%.
  * You cannot link out to a website to purchase the same content.
  * You cannot mention that the content is available for purchase elsewhere.
  * A watchface that contains a JavaScript component is treated, for the purposes of review, as software that runs on Apple's platform — because the JavaScript actually executes inside the Pebble companion app's JS runtime, not on the watch itself.

  That last bullet is the one that broke us. Pebble.js apps and watchfaces that use the `PebbleKit JS` framework run their JavaScript inside the iOS companion app to fetch weather, talk to web services, do anything network-related. From Apple's point of view, every one of those is a piece of executable code that they did not review being shipped into an app that they did review.

  ## What that means in practice

  Pretty soon after the new app store rolled out in the iOS companion, Apple's reviewers started flagging companion app updates for "executable code being downloaded after review." We had been doing this for years — every watchface install does it — but the new store made it visible in a way the old locker didn't. The catalog is browsable, beautiful, and obviously a store. That visibility changed how it got reviewed.

  We have spent the last several weeks negotiating, redesigning, and revising. Here is what we have learned:

  **Option A: Version every watchface with a JS component through Apple.** The math here is breathtaking. We have thousands of watchfaces with JS components in the catalog. Each update to each one would need to be bundled into a Pebble companion app update and sent through Apple Review. The current companion app review cycle is 7 to 10 days. The Pebble developer community ships, on a busy week, a few hundred updates. There is no version of this universe where we can play.

  **Option B: Strip JS entirely.** Kill `PebbleKit JS`, kill Pebble.js, tell our most engaged developers that the platform feature they have been building on for two years is gone. This guts the developer community and makes Pebble watches strictly worse than they are today, two months before a competitor ships with full app support. Not happening.

  **Option C: Move JS execution to the watch.** The watch does not have a JavaScript runtime. Adding one means a firmware revamp, much higher RAM and battery cost, and a hardware refresh we are not in a position to ship in 2015. Maybe a future generation. Not in time.

  **Option D: Charge for apps.** This is the one I want to talk about, because it's the one I spent the most time on, and it's the one I lost.

  The original plan was for paid apps to flow through Stripe (or a similar processor) directly to developers, with Pebble taking a small fee. That plan does not survive contact with the App Store Review Guidelines. The moment we put a "Buy" button in the store rendered inside the iOS companion app, that's an in-app purchase. Apple gets 30%, full stop. Worse: because the content is "consumed" on a hardware device that isn't Apple's, and is rendered through an app that has to ship a JS runtime, the entire payment surface area is in a gray area that is more or less designed to fail review.

  We modeled what a paid app store would look like with the 30% cut, the IAP-only flow, and the ongoing review risk for any update touching the catalog. Even ignoring the review risk, the unit economics do not work. A developer pricing their watchface at $1.99 nets $1.39 from Apple, gives Pebble whatever cut we take, and has to do that across millions of installs to make it worth anyone's time. A small developer who hand-makes a beautiful clock face is not signing up for that.

  Independently of all of this, our conversations with Apple have made it pretty clear that a vibrant third-party developer monetization story on a competing wrist platform is not something the team currently shipping their own wrist platform is enthusiastic about helping us thread. I will leave it at that.

  ## What we shipped

  No paid app store. Not now. The store stays free. Developers ship watchfaces and apps for free, with the existing tip-jar pattern as the only monetization path. We will keep pushing on this and we will keep talking to Apple, but I am writing this down so that when someone asks me in 2017 why the Pebble store isn't paid, I have a place to point.

  On the technical side, we did several things to defuse the JS-in-companion-app issue:

  * The JS payloads for each watchface are sandboxed inside a per-app JS context with strict resource limits, and the companion apps make it very clear in their App Store metadata that this code runs only to bridge the watch to its developer's web services.
  * We added server-side review tooling so every uploaded JS payload is statically scanned for the patterns Apple has previously flagged (eval-of-remote-strings, dynamic script injection, attempts to call iOS-only APIs through bridges, etc.) and rejected at upload time with a useful error.
  * The store itself, both in the companion app and on the web, was redesigned to put curation and discovery much more front-and-center than "browse and install," which made it easier to argue that the surface is editorial rather than transactional.

  These are mitigations. They are not a fix. The fundamental issue is that we are running a software distribution channel for a wearable device through a competing wearable maker's mandatory client app. There is no clever architecture that gets around that.

  ## What I think this means

  I am going to say something here that is going to sound unkind but I think is true.

  Every hardware company that is not Apple, that ships a device that pairs with an iPhone, is running their developer ecosystem on borrowed time. The terms of that loan are dictated by a counterparty who is also a competitor, and the terms are reviewed by humans who are looking at your product with their roadmap in their peripheral vision. We got the version of this conversation that you get when you have momentum, a community, and good intentions. I do not want to imagine the version of this conversation that a company without those things gets.

  I love working on Pebble. The hardware is special, the community is the best on any platform I have worked on, and the team in Palo Alto is the kind of focused small team that makes you understand why startups exist. None of that changes the fact that a watchface store with a paid tier was a real plan, and that plan no longer exists, and the reason it no longer exists is not a technical one.

  If you are a Pebble developer reading this and you were waiting on a paid store to ship that thing you have been working on: I am sorry. We tried. Build the thing anyway, ship it for free, and we will keep figuring out how to get you paid. There is a tip-jar API coming.

  More to come.
MARKDOWN

begin
  Post.create!(
    title: "When Apple Reviews Your App Store: Notes from the Pebble Trenches",
    created_at: "February 12, 2015",
    markdown_body: body,
    markdown_excerpt: "What happens when your watchface marketplace becomes Apple's problem two months before they ship a watch of their own.",
    post_tags: "pebble,apple,app-store,wearables,platforms,javascript"
  )
  puts "Imported When Apple Reviews Your App Store: Notes from the Pebble Trenches"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 12-02-2015-When-Apple-Reviews-Your-App-Store: #{e.message}"
rescue => e
  puts "Unexpected error importing 12-02-2015-When-Apple-Reviews-Your-App-Store: #{e.message}"
end
