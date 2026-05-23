body = <<~MARKDOWN
  #__August 26, 2020__

  **_Notes from a year of migrating a 2014-era Angular.js + Rails monolith to React + Next.js without taking the storefront down._**

  The e-commerce stack I inherited when I joined StackCommerce in late 2019 was a textbook 2014 Rails monolith with an Angular.js (1.x) single-page frontend bolted onto it. Server-rendered Rails views for SEO-critical pages, an Angular.js app for the checkout and account flows, a shared asset pipeline that took eight minutes to build, and a Heroku deployment that we were rapidly outgrowing.

  This is the post I wish someone had handed me when we kicked off the replatform. It is partly an architecture writeup and partly a list of mistakes you do not have to make.

  ## Why now

  Angular.js went into long-term-support mode in 2018 and reached end-of-life in December 2021. That is the headline. The deeper reasons:

  * **Performance.** Angular.js's dirty-checking digest cycle was killing us on category and product listing pages with hundreds of items. We had spent years adding `track by`, `bindOnce`, and one-way bindings to claw back milliseconds, and we were out of cheap wins.
  * **Hiring.** The set of engineers who want to maintain Angular.js code in 2020 is small and shrinking. Every new hire spent their first month learning a framework that, in their next role, would be a line item on their "legacy systems I have touched" page.
  * **SEO.** Rails-server-rendered HTML with Angular.js taking over after page load was producing increasingly bad Core Web Vitals scores. Largest Contentful Paint on a category page was hovering north of 4 seconds. Google had started talking about CWV as a ranking factor for 2021.
  * **Revenue.** The product team's roadmap was full of things that would have been three lines of React Hooks and were several days of Angular.js plumbing. We were losing weeks every quarter to framework drag.

  ## The decision tree we did not take

  Two options we considered and rejected:

  1. **Angular.js → Angular (the new one).** The migration path the official Angular team recommends is `ngUpgrade`, which lets you run both frameworks side-by-side and migrate component-by-component. We did the math. Our app would have been in dual-framework mode for at least 18 months, the destination framework's idioms are very different from the React idioms our team mostly knows, and we would have come out the other end with another single-framework SPA that doesn't help our SEO problem at all.
  2. **Big-bang rewrite.** Build the new stack in parallel, ship it on a flag day. Tempting. Also the canonical way every replatform I have ever seen has failed. We discarded this in the first week.

  The path we picked:

  * The new stack is **React + Next.js**, with Next.js handling SSR for SEO and ISR for the long-tail product pages.
  * The Rails monolith stays, but its role shrinks. It becomes a JSON API plus a set of legacy server-rendered pages that we migrate one at a time.
  * The Angular.js frontend gets retired **route by route**, with Next.js serving the new version behind a reverse proxy that decides per-request which app gets to render.

  ## The shim that made everything possible

  The single most useful piece of infrastructure in the entire migration was the routing shim. It lives at the edge (CloudFront → ALB → Nginx) and looks roughly like this:

  ```nginx
  location / {
      set $upstream "legacy";

      if ($cookie_force_legacy = "1") { set $upstream "legacy"; }
      if ($cookie_force_new = "1")    { set $upstream "next"; }

      access_by_lua_block {
          local route_map = require("route_map")
          if route_map.is_migrated(ngx.var.uri, ngx.var.host) then
              ngx.var.upstream = "next"
          end
      end

      proxy_pass http://$upstream;
  }
  ```

  `route_map` is a tiny Lua module that knows, for each `(host, path)` pattern, whether the new stack is serving it. Migrating a route from legacy to new is a one-line change in the route map, plus a deploy. Rolling back is the same one-line change.

  This let us:

  * Migrate one URL pattern at a time.
  * Let QA test the new version of a page in production via a cookie before flipping the public switch.
  * Roll back a flipped route in under a minute without redeploying either app.
  * Run both apps in production indefinitely while we ground through the long tail.

  Every migration I have been part of that went well had something like this routing shim. Every one that went badly tried to do without it.

  ## Sharing the auth session

  The trickiest part of running two frontends in production at once was the session. The Rails app uses Rails's encrypted cookie session. The Next.js app uses its own session machinery (we ended up on iron-session). The user does not know or care which app is rendering their current page, and a logged-in user clicking from a Next.js category page to a legacy product page expected to stay logged in.

  We solved this by making the Rails session cookie the source of truth and giving Next.js a small server-side helper that reads it:

  ```typescript
  import { decryptRailsCookie } from "@stackcommerce/rails-session";

  export async function getServerSideProps({ req }: GetServerSidePropsContext) {
    const session = decryptRailsCookie(req.cookies["_app_session"], {
      secretKeyBase: process.env.RAILS_SECRET_KEY_BASE!,
    });

    return {
      props: {
        user: session?.user_id ? await fetchUser(session.user_id) : null,
      },
    };
  }
  ```

  The Rails cookie format is documented well enough that reimplementing the decrypt in TypeScript was a couple of days of work, and the alternative (introducing a new session store and migrating every active session) was a multi-month project. We chose the small ugly thing over the large clean thing, and I would do it again.

  ## SSR, ISR, and what we actually rendered where

  The default Next.js answer to "should this page be SSR or SSG or ISR" is "it depends," which is correct and infuriating. The rules we settled on:

  * **Product pages**: ISR with a 60-second revalidate. We have tens of thousands of these and they change rarely. SSG on build would have made the build take forever and made price updates feel sluggish; full SSR would have been wasteful and bad for cache hit rates at the CDN.
  * **Category pages**: SSR with edge-cached responses. Faceted filtering means there are too many permutations to pre-generate, and the content changes frequently enough that even a short ISR revalidate would cause stale-pricing complaints from the merchandising team.
  * **Cart and checkout**: SSR with no caching. These are per-user, full of fresh state, and need to be correct on every render.
  * **Marketing landing pages**: SSG, rebuilt nightly. These are owned by the marketing team via a headless CMS and the cadence is "we change them when we change them."

  The thing that surprised me is how much of the performance win came from the CDN being able to cache responses, not from rendering being faster. Pre-replatform, every page was a Rails template render plus an Angular bootstrap on the client. Post-replatform, the median product page response comes from CloudFront in 40 milliseconds because Next.js produced a static HTML snapshot 12 seconds ago and we have not had to regenerate it since.

  ## What the build looks like now

  ```
  /apps
    /web        # Next.js, public storefront
    /admin      # Next.js, internal merchandising tool
    /api        # The remaining Rails monolith, now in API-only mode for most routes
  /packages
    /ui         # Shared React component library
    /design     # Tailwind preset + tokens
    /api-client # Generated TypeScript client for /api
  ```

  Monorepo on Turborepo, build pipeline on GitHub Actions, deploys on Vercel for the Next.js apps and on AWS ECS for the Rails API. The build that used to take eight minutes takes about ninety seconds for an incremental change, and a full clean build is under three minutes.

  ## Numbers

  At this point, about 60% of the storefront's traffic is served by the new stack. The numbers we have, comparing the new stack to the legacy stack on the same pages:

  * Largest Contentful Paint: 4.1s → 1.3s (p75)
  * Time to Interactive: 7.8s → 2.4s (p75)
  * Conversion rate on category-to-product transitions: +14%
  * Revenue per session: +9% on the migrated traffic
  * Build time: 8 minutes → 90 seconds (incremental)

  The conversion lift is the one that matters. None of the rest of this is interesting if the page loading faster did not also mean more people buying things. It does.

  ## What I would tell a past version of me

  Three things.

  **The migration is not the project.** The project is the years of new product work that the migration unblocks. Frame it that way to the business or you will not get the runway.

  **Cut the long tail off early.** There are pages in every old app that get ten visits a month and have edge cases that will eat a sprint each. Identify them in month one, decide whether they are getting migrated or sunset, and make the decision public. The pages we did not decide on are the pages we are still maintaining in two frameworks 14 months in.

  **Hire a designer onto the migration team.** "It is supposed to look exactly the same" is a lie you tell yourself in week one and stop believing in week three. There are decisions a designer has to make about every screen — what density to use in the new system's tokens, how to handle a component that exists in three flavors in the old app, what to do with that one weird modal that the merchandising team loves and nobody else uses. A designer on the team makes those decisions in hours. Without one, they make them in weeks.

  More on the Aurora migration and the security work in subsequent posts. This one is long enough.
MARKDOWN

begin
  Post.create!(
    title: "Replatforming from Angular.js to React + Next.js Without Going Dark",
    created_at: "August 26, 2020",
    markdown_body: body,
    markdown_excerpt: "Notes from a year of migrating a 2014-era Angular.js + Rails monolith to React + Next.js without taking the storefront down.",
    post_tags: "react,nextjs,angular,rails,replatform,migration,ssr,ecommerce"
  )
  puts "Imported Replatforming from Angular.js to React + Next.js Without Going Dark"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 26-08-2020-Replatforming-from-Angular-to-Next: #{e.message}"
rescue => e
  puts "Unexpected error importing 26-08-2020-Replatforming-from-Angular-to-Next: #{e.message}"
end
