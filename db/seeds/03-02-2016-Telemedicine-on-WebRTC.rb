body = <<~MARKDOWN
  #__February 03, 2016__

  **_Building a doctor-patient video visit on WebRTC, HealthKit, and Ionic when you have six months and a pilot to ship._**

  I started Checkup last August with the idea that telemedicine in 2015 still felt like a 2003 product. Most of what was on the market was either a glorified Skype call wrapped in a HIPAA-compliant skin, or a giant enterprise EMR with a video tab bolted on the side. We wanted to build something that felt like a modern mobile app: a patient opens it, sees their doctor's availability, taps a button, and is in a video visit in under thirty seconds, with their connected device data (steps, weight, glucose) already in front of the physician.

  We have a pilot running with a small group of working physicians in Los Angeles starting next month. This is a writeup of how the technical pieces came together, and what I would do differently.

  ## The stack

  * **Mobile**: [Ionic 1.3](http://ionicframework.com/) (Angular 1.4 under the hood, Cordova for the native shell)
  * **Video**: WebRTC, with [TokBox](https://tokbox.com/) (now Vonage) as the signaling and TURN provider
  * **Connected devices**: HealthKit on iOS, Google Fit on Android, both behind a normalized API on our backend
  * **API**: Node.js / Express on Heroku, Postgres for everything that needs to be relational
  * **Auth**: JWT with refresh tokens, plus a doctor verification flow that's largely manual right now

  Why Ionic? Speed. We are two engineers. A hybrid app gets us iOS and Android off the same codebase, and the parts of the product that are not the video call (browsing availability, intake forms, reviewing past visits) are exactly the kind of CRUD-y screens that Ionic does well. We pay for it in places, which I'll get to.

  ## WebRTC, in practice

  The thing nobody tells you about WebRTC is that the API is a small part of the work. The hard parts are the parts that aren't in the spec: TURN servers, network traversal, codec negotiation in low-bandwidth conditions, and the user experience of a call that is degrading without anyone admitting it.

  We started by trying to do it ourselves. The browser API is genuinely not that complicated:

  ```javascript
  var pc = new RTCPeerConnection({
    iceServers: [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'turn:turn.checkup.example:3478', username: 'u', credential: 'p' }
    ]
  });

  navigator.mediaDevices.getUserMedia({ video: true, audio: true })
    .then(function(stream) {
      stream.getTracks().forEach(function(track) {
        pc.addTrack(track, stream);
      });
      return pc.createOffer();
    })
    .then(function(offer) {
      return pc.setLocalDescription(offer);
    })
    .then(function() {
      signaling.send('offer', pc.localDescription);
    });
  ```

  Five minutes of code, an afternoon to wire up signaling over websockets, and we had two laptops on the same wifi sending video to each other. Excellent. Ship it.

  Then we put it on cell networks. Then we put it on a doctor's office wifi behind a corporate firewall. Then we put it on an iPhone in the patient waiting room of a clinic with two bars of LTE. The 80% of the work that wasn't visible in the demo started introducing itself.

  After about three weeks of fighting our own TURN setup, monitoring NAT traversal failures, and tuning STUN timeouts, we switched the actual media path to TokBox and kept our own signaling for everything that isn't video (call setup, ringing, hangup, the in-call chat sidebar). The math on our team size made it impossible to run a real-time video infrastructure in-house, and TokBox's iOS and Android SDKs handle the codec adaptation and ICE restart logic that I do not have time to write twice.

  The lesson: WebRTC is a great API for prototyping. Running it in production is a media infrastructure business, and you should buy that business unless that is the product.

  ## Ionic and the video call screen

  The video call screen is the one place Ionic broke down for us, and it's worth describing in detail because I don't think it's well understood.

  Ionic 1 renders into a WebView. On Android, that's `WebView` (which until very recently was a different rendering engine on every Android version). On iOS, that's `UIWebView` (which is the slow one, before iOS 8) or `WKWebView` (which is faster but has a long list of quirks around media playback and getUserMedia). WebRTC inside a Cordova WebView is, generously, an adventure.

  We ended up using the `cordova-plugin-iosrtc` plugin for iOS, which polyfills the WebRTC APIs by routing them through native code, and the stock Android WebView for Android. That gets you a working RTCPeerConnection on both platforms, but with a catch: on iOS, the video element is not actually a DOM element. It's a native UIView that the plugin places on top of the WebView at the coordinates of where you put your `<video>` tag. Which means:

  * The video does not scroll with the page.
  * The video does not respect CSS `z-index` (it is always on top).
  * If you animate the position of the `<video>` element, the native view does not follow until the animation finishes.
  * If you hide the `<video>` element via `display: none`, the native view stays where it was.

  We worked around all of these. The fix that took the longest to converge on was a custom directive that watches the bounding box of the `<video>` element and tells the native plugin to reposition the underlying UIView on every animation frame. Once we had that in place, the call screen behaved correctly with the in-call chat sidebar sliding in over the video, the mute and end-call buttons floating above it, and the doctor's video resizing into a picture-in-picture when the patient opened their connected device data.

  None of this is hard. All of it is the kind of work that doesn't exist in a native app, and it's the price of getting two platforms off one codebase.

  ## HealthKit and Google Fit, normalized

  The most differentiated part of the product is that the doctor sees the patient's connected device data alongside the call. Steps, weight, sleep, heart rate. On iOS that's HealthKit. On Android that's Google Fit.

  The data models are not the same shape. HealthKit thinks in samples with start and end timestamps; Google Fit thinks in datasets keyed by data source. HealthKit gives you per-sample permission grants; Google Fit gives you scope-level grants. The units do not always match.

  We built a small normalization layer in the app that, on each platform, reads the past 30 days of a fixed set of types (steps, weight, heart rate, blood glucose, sleep) and uploads them to our backend in a single normalized schema:

  ```json
  {
    "type": "weight",
    "value": 84.2,
    "unit": "kg",
    "recorded_at": "2016-01-28T14:13:00Z",
    "source": "withings_scale",
    "source_type": "device"
  }
  ```

  On the backend, we store one row per sample with a generated `dedupe_key` so re-uploads are idempotent. The doctor's view of a patient is a single API call that returns the last N samples per type with summary statistics computed server-side.

  Two things I would do differently:

  1. **Pull less.** We started by pulling everything. We ended up pulling only what the physician dashboard actually rendered, which is about a tenth of what HealthKit exposes. The battery impact of doing background HealthKit reads is real, and the moral cost of having a thousand samples of "stair flights climbed" in our database that nobody will ever look at is also real.
  2. **Surface consent every visit.** HealthKit permissions are sticky. Once a user grants a read, you have it forever. The right pattern, I think, is to remind the patient at the start of each visit what data is being shared, give them a one-tap revoke, and treat the consent as part of the visit metadata. We did not ship this for the pilot but it's at the top of the list for v2.

  ## The pilot

  We start with a small group of physicians at a primary care practice in March. The plan is to use the first month for a "first call" with each doctor where we sit with them, watch them use the app cold, and write down everything that confuses them. The second month is real patient visits with our team available on call to triage anything that goes wrong. The third month is the doctors flying solo, with us instrumenting everything and looking at the numbers.

  The metric I care about most is "time from app open to in-call video stream." If we can get that under 30 seconds for the median visit, we have something. The current best case in our internal testing is about 14 seconds. The worst case is "the iOS app crashed because HealthKit took 8 seconds to return and we had a timeout that fired and triggered a reconnect loop." That bug is fixed. Probably.

  More to come once we have real numbers. If you are a physician reading this and you would like to talk about what telemedicine should feel like, my email is at the top of the page.
MARKDOWN

begin
  Post.create!(
    title: "Telemedicine on WebRTC, HealthKit, and a Hybrid App",
    created_at: "February 3, 2016",
    markdown_body: body,
    markdown_excerpt: "Building a doctor-patient video visit on WebRTC, HealthKit, and Ionic when you have six months and a pilot to ship.",
    post_tags: "webrtc,healthkit,ionic,telemedicine,cordova,javascript"
  )
  puts "Imported Telemedicine on WebRTC, HealthKit, and a Hybrid App"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 03-02-2016-Telemedicine-on-WebRTC: #{e.message}"
rescue => e
  puts "Unexpected error importing 03-02-2016-Telemedicine-on-WebRTC: #{e.message}"
end
