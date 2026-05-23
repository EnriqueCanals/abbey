body = <<~MARKDOWN
  #__September 18, 2017__

  **_How we built a serverless DNS blocking service on Lambda, Kinesis, and Redis — and what to do when OpenVPN can't carry IPv6 traffic in 2017._**

  The service I have been working on for the past year and a half does something pretty specific: we ship a VPN client on millions of mobile devices that routes their internet traffic through us so we can apply content policies (kid-safe filtering, ad blocking, malware blocking) regardless of which network they happen to be on. The interesting engineering is in the middle: how do you take a firehose of DNS queries from every device on the planet and decide, in milliseconds, whether each one should be blocked, allowed, or rewritten?

  This post is about the data path, the serverless decisions we made, and the IPv6 problem that ate two weeks of my life.

  ## The shape of the problem

  At peak we see several hundred thousand DNS queries per second across all devices. Each query needs:

  * A policy lookup (what is this device subscribed to?)
  * A categorization lookup (is the domain in any of the categories the device is blocking?)
  * A decision (allow, block, or rewrite)
  * A log entry (for the user-facing dashboard and for our own analytics)

  The first three need to happen in single-digit milliseconds because the user is waiting for a webpage to load. The fourth can be async.

  The naive architecture is a fleet of always-on servers running a DNS resolver and a policy engine. We started there. It works, and it scales, but the cost curve is brutal and the operational story is a nightmare because traffic is enormously bursty — a school day starts in California three hours after a school day starts in Florida, and Saturday at 9am looks nothing like Tuesday at 9am.

  The architecture we ended up with is split:

  * **Hot path** (the actual DNS resolver): a custom resolver running on a small fleet of EC2 instances, with policy decisions cached locally in-process.
  * **Decision cache rebuild**: AWS Lambda + Kinesis, rebuilding the local cache from a stream of policy and categorization changes.
  * **Domain categorization storage**: Redis, holding the categorization for tens of millions of top-level domains.
  * **Log pipeline**: Kinesis Firehose, fanning out to S3 (for compliance) and to a real-time analytics pipeline (for the user dashboard).

  ## The categorization service

  The thing I want to talk about first is the categorization service, because it's the part I am proudest of. We needed to know, for any domain on the public internet, what categories it belongs to (social, gambling, news, adult, malware, ad network, and about 80 others). We had a partnership that gave us a feed of categorizations covering most of the public web, but that feed is huge — tens of millions of domains — and it updates continuously.

  We loaded the whole thing into Redis with a really simple schema:

  ```
  KEY:   dom:example.com
  VALUE: hash of { category_id => confidence_score }
  ```

  Plus a parent-domain shortcut so a query for `cdn.example.com` falls through to `example.com` if the subdomain isn't categorized on its own. The whole index fits in about 14GB of Redis, comfortably on a single `cache.r4.xlarge` with a replica. Lookups are sub-millisecond.

  The hot path resolver never queries Redis directly. It has a local in-process cache of the categorizations for the most-queried 5 million domains, refreshed every few minutes from the Redis index. The cache eviction policy is "if you haven't been queried in the last hour, drop you," which keeps the resident set small. Cache misses fall through to Redis, and Redis misses fall through to a default-allow policy.

  ## Lambda for the streaming work

  The pieces that don't have to be hot run on Lambda. Specifically:

  * **Categorization feed ingest.** The partner feed pushes updates to a Kinesis stream. A Lambda function reads the stream in batches of 500 records and applies them to Redis with pipelined writes. Throughput is comfortably 50k updates/sec at peak; we are paying tens of dollars a month for it.
  * **Per-device policy compilation.** When a user changes their settings (toggles "block social media on weekends," adds a custom blocklist, etc.), a small Lambda compiles their policy into a flat lookup structure that gets pushed to the hot path resolvers via a config channel.
  * **Log aggregation.** Every DNS decision the resolver makes gets emitted to Kinesis Firehose as a single JSON record. A Lambda consumes from a parallel Kinesis stream of the same data and rolls up per-device, per-category counters that back the dashboard.

  The Lambda model fits this workload disturbingly well. Cold starts are not a factor because everything is event-driven and the streams keep functions warm. We get the bursty scaling for free. Cost is a fraction of what running equivalent capacity on EC2 would be.

  ## The OpenVPN IPv6 problem

  Now, the part that ate two weeks.

  The VPN client we ship is an OpenVPN tunnel. OpenVPN is great, has a long track record, has clients on every platform we care about. It has, in the version we are shipping, one fatal flaw for our use case: it does not tunnel IPv6 traffic if the underlying transport is IPv4.

  This was fine in 2014 when we built this thing. By 2017 it is decidedly not fine. T-Mobile in the US is largely IPv6-only on the cellular side. Several large mobile networks in Asia are. When a device is on one of those networks, the VPN connects fine (because the OpenVPN control channel rides over IPv4 over the carrier's NAT64 gateway), but any application traffic that wants to go over IPv6 is silently dropped. The user opens an app, the app tries to connect to its server over IPv6, the connection times out, the user blames the VPN and uninstalls.

  We had three options:

  1. Wait for OpenVPN to fix it upstream. (No timeline.)
  2. Migrate to a different VPN protocol. (Many months of work.)
  3. Solve the IPv6 problem in the middle, on our side.

  We picked option 3. The fix was a custom [NAT64](http://www.litech.org/tayga/) implementation deployed on our VPN concentrators. NAT64, very briefly, is the mechanism by which an IPv6-only client can talk to an IPv4-only server: a DNS64 server synthesizes a fake IPv6 address that encodes the real IPv4 address inside it, and the NAT64 gateway translates the IPv6 packets to IPv4 on the way out.

  We are using it backwards. The client is sending IPv4 to us (because that is what OpenVPN can carry) but the destination is a service that exists only on IPv6. So we run a DNS64 service on our resolver side that synthesizes the inverse mapping, and we run [TAYGA](http://www.litech.org/tayga/) on our concentrators to translate the outbound IPv4 packets to IPv6 toward the real destination. The reverse path does the reverse translation. From the application's point of view on the device, IPv6 destinations now work, even though the device is talking IPv4 the entire time.

  The whole thing is held together with a stack of iptables rules, a custom kernel build with TAYGA's `nat64` interface module loaded, and a fairly nervous set of monitoring alerts. It's a workaround, not a fix. But it bought us six months of runway while we evaluate moving to WireGuard, which does not have this problem at all.

  ## Predictive push

  The other thing I want to mention briefly is the predictive push notification work. Once you have a real-time stream of DNS queries per device, you have a really good picture of how each device uses its data. We built a small model that looks at the per-hour, per-app data usage pattern for each device over the past 30 days and predicts the probability that the device is going to blow through its monthly data cap before the end of the cycle. If the probability crosses a threshold, we fire a push notification with a "you are on track to exceed your data plan, here is what to do" message.

  The model is, honestly, not very sophisticated. A regression with hand-engineered features (recent slope, weekday/weekend split, recent week-over-week change, time-of-day usage profile). But the metric we care about is "did the user take action after the notification" and the signal is strong enough that we keep iterating on it. The newer version uses a small recurrent net that takes the last 30 days of hourly usage as a sequence and predicts the next 30 days. It is meaningfully better but more expensive to retrain, and the cost has not yet justified the lift.

  ## What I would do differently

  Two things.

  **I would have started with the log pipeline.** We built the hot path first and bolted logging on later, which meant the log format went through about four breaking changes in the first year, every one of which broke a downstream consumer. If I were starting over, I would design the log schema first, with versioning and a schema registry, and treat every other component as a producer or consumer of that schema.

  **I would have moved off OpenVPN earlier.** The IPv6 problem was a symptom. The deeper issue is that OpenVPN's threading model on mobile is bad, its session resumption story is bad, and its handshake is too chatty for cellular networks. WireGuard fixes all of these. The reason we did not move earlier is that WireGuard's iOS client was not ready until late 2017, and switching VPN protocols on a deployed fleet of millions of devices is the kind of decision you only get to make once. But the IPv6 workaround is going to look, in retrospect, like duct tape on top of a leak that we should have fixed at the source.

  Onward.
MARKDOWN

begin
  Post.create!(
    title: "DNS Filtering at Lambda Scale (and the OpenVPN IPv6 Problem)",
    created_at: "September 18, 2017",
    markdown_body: body,
    markdown_excerpt: "How we built a serverless DNS blocking service on Lambda, Kinesis, and Redis - and what to do when OpenVPN can't carry IPv6 traffic in 2017.",
    post_tags: "aws,lambda,kinesis,redis,dns,openvpn,nat64,networking"
  )
  puts "Imported DNS Filtering at Lambda Scale (and the OpenVPN IPv6 Problem)"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 18-09-2017-DNS-Filtering-at-Lambda-Scale: #{e.message}"
rescue => e
  puts "Unexpected error importing 18-09-2017-DNS-Filtering-at-Lambda-Scale: #{e.message}"
end
