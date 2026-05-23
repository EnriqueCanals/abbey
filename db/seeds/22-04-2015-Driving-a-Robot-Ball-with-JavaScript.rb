body = <<~MARKDOWN
  #__April 22, 2015__

  **_Lessons from shipping Sphero.js, the official JavaScript SDK for a Bluetooth robot ball that thousands of kids use to learn to program._**

  Today we cut the 1.0 release of [sphero.js](https://github.com/orbotix/sphero.js), the official JavaScript SDK for Sphero robots. This is the result of about a year of work with the team at Orbotix, and it's the first time I can write about it publicly. So: a writeup.

  If you haven't seen Sphero in person, the elevator pitch is that it's a programmable robotic ball, about the size of a billiard ball, that pairs with a phone or computer over Bluetooth Low Energy and rolls around the floor. It's a toy, but it's also a teaching tool, and the JavaScript SDK is the surface that most of the educational integrations are going to be built on top of.

  ## Why JavaScript

  The decision to do the SDK in JavaScript wasn't obvious. Sphero already had a perfectly good Objective-C SDK and a Java/Android SDK. Native is faster, has better BLE story on mobile, and doesn't depend on a runtime. So why JS?

  Two reasons:

  1. **Node has a real BLE story now.** [noble](https://github.com/sandeepmistry/noble) is genuinely good, runs on macOS, Linux, and Windows, and means a kid with a Raspberry Pi or a laptop can drive a Sphero without writing a line of native code.
  2. **Education runs on JavaScript.** Every block-based programming environment that matters for kids — Scratch, Blockly, Code.org's editor, Tickle — either targets JavaScript directly or generates it. If we want Sphero to show up in classrooms, the SDK needs to be `npm install sphero` and a five-line program.

  Once you accept those two things, the only real question is how opinionated to be. We chose: very.

  ## The API we wanted

  The Sphero protocol is a binary command/response protocol over a virtual serial port (or BLE characteristic, depending on the model). Every command is a packet with a device ID, a command ID, a sequence number, payload bytes, and a checksum. The response comes back asynchronously with a matching sequence number. There are something like 80 commands across half a dozen "devices" (drive, sensor, sphero core, bootloader, etc.).

  We did not want users to know any of this.

  ```javascript
  var sphero = require('sphero');
  var orb = sphero('/dev/tty.Sphero-RBR-AMP-SPP');

  orb.connect(function() {
    orb.color('red');
    orb.roll(100, 90);

    setTimeout(function() {
      orb.color('blue');
      orb.roll(100, 270);
    }, 2000);
  });
  ```

  That's the goal: any kid who has typed JavaScript before can read this program and predict what's going to happen. The robot is going to turn red, roll forward at speed 100 in direction 90 (east), wait two seconds, turn blue, and roll back. No packet construction, no checksums, no event listeners required for the simple case.

  Under the hood, that `orb.color('red')` call is doing a lot:

  ```javascript
  Sphero.prototype.color = function(color, callback) {
    var rgb = utils.parseColor(color);
    var packet = this.packet.create({
      sop2: 0xFF,
      did: 0x02,
      cid: 0x20,
      seq: this._nextSeq(),
      data: [rgb.red, rgb.green, rgb.blue, 0x00]
    });
    return this._queueCommand(packet, callback);
  };
  ```

  Color name to RGB, RGB to a Sphero core packet, packet to a serialized buffer with the right checksum, buffer queued onto the connection's outbound stream, response correlated by sequence number, callback fired when the ack lands. The point of an SDK is to do all of that without the caller noticing.

  ## The packet layer

  The most fun part of the SDK to design was the packet construction. The Sphero protocol uses a checksum that is "the modulo 256 sum of all the bytes from the DID through the end of the data payload, bit-inverted." That's two sentences in the spec and about ten different bugs in a naive implementation.

  We split the packet code into three layers:

  * A `Packet` class that knows how to serialize a single command to a `Buffer`, including the checksum.
  * A `Parser` class that consumes incoming bytes and emits complete response packets (with all the framing weirdness of "what happens if a response straddles two reads from the serial port").
  * A `Command` factory that holds the metadata for every command in the protocol (which device, which command ID, expected response shape) so individual SDK methods just declare what they need:

  ```javascript
  var commands = require('./commands');

  Sphero.prototype.setHeading = commands.build({
    did: 0x02,
    cid: 0x01,
    args: ['heading:uint16']
  });
  ```

  Building most of the SDK on top of a declarative `commands.build` call meant adding new commands (and there were a lot of new commands as the firmware team kept extending things) was almost free.

  ## Streaming sensor data

  The thing that took the longest to get right was sensor streaming. Sphero can stream up to about a dozen sensor values back to the host — accelerometer, gyro, IMU-derived orientation, motor back-EMF, velocity, position — at configurable rates up to 400Hz. You configure what you want by sending a "set data streaming" command with a bitmask of fields and a divisor on the base rate. The robot then starts firing async responses at you forever until you turn it off.

  The user-facing API we ended up with:

  ```javascript
  orb.streamAccelerometer();
  orb.on('accelerometer', function(data) {
    console.log(data.xAxis.value, data.yAxis.value, data.zAxis.value);
  });
  ```

  Under that one line is a config call to the robot, a parser that knows the layout of the streamed packets, a remapping step that turns raw 16-bit ints into engineering units (Gs for accelerometer, degrees for gyro, etc.), and an EventEmitter that fans the data out to listeners. Switching one of those `stream*` methods on or off rebuilds the bitmask and reconfigures the robot transparently. If you ask for accelerometer and gyro at the same time, you get one stream with both, not two streams.

  ## Things that bit us

  A few things from the field that I want to write down before I forget them.

  **BLE write coalescing on macOS.** macOS CoreBluetooth, at least in 10.10, will silently coalesce successive writes to the same characteristic if you queue them fast enough. The Sphero firmware is fine with this for most commands, but the bootloader and the OTA update path absolutely is not. We ended up adding a per-connection write throttle that defaults to about 8ms between writes. Nobody notices and the OTA flow stopped corrupting itself.

  **Serial port enumeration is platform-specific and weird.** On macOS, Spheros show up as `/dev/tty.Sphero-XXX-YYY-SPP` after you pair them in System Preferences. On Linux they're `/dev/rfcomm0` or similar, but only after you `rfcomm bind` them, and udev rules vary by distro. On Windows they're COM ports with numbers that change depending on the order things got paired. We added a `sphero.findPorts()` helper that does platform detection and returns a list of likely candidates, because the alternative is a forum full of "it doesn't work on my computer" threads.

  **Checksums are the worst kind of bug.** A packet with a bad checksum is silently dropped by the robot. No error, no log, nothing. You send the command and nothing happens. We had a stretch where about 1 in 500 packets was getting silently dropped because of an off-by-one in how we were computing the checksum length when the data payload was exactly zero bytes. The fix was three characters. Finding it took a weekend.

  ## Blockly and Coding with Chrome

  Concurrently with the SDK we shipped a Blockly extension that lets kids drag visual blocks together and have them compile down to `sphero.js` calls. We demoed it at Google I/O in June and the Chrome team liked it enough that they pulled the underlying Blockly+Sphero integration into their [Coding with Chrome](https://chrome.google.com/webstore/detail/coding-with-chrome/becloognjehhioodmnimnehjcibkloed) Chrome extension as a first-class target. Watching a fifth-grader drag five blocks together and make a robot ball draw a square on the floor is the closest thing I have ever had to a "this is why I do this job" moment.

  ## What's next

  The 2.0 of the SDK is going to be about the new Sphero models — the BB-8 partnership with Lucasfilm is going to need a much simpler driving API, and the Ollie's two-wheel-drive kinematics need their own roll command that doesn't lie to you about what "heading" means on a non-spherical robot.

  If you want to play with the SDK, `npm install sphero`, plug in a Sphero, and try the README quickstart. If you find a bug, open an issue. If you build something cool, tweet at me — I am collecting demos.
MARKDOWN

begin
  Post.create!(
    title: "Driving a Robot Ball with JavaScript: Shipping Sphero.js",
    created_at: "April 22, 2015",
    markdown_body: body,
    markdown_excerpt: "Lessons from shipping Sphero.js, the official JavaScript SDK for a Bluetooth robot ball that thousands of kids use to learn to program.",
    post_tags: "sphero,javascript,nodejs,bluetooth,hardware,sdk,robotics"
  )
  puts "Imported Driving a Robot Ball with JavaScript: Shipping Sphero.js"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 22-04-2015-Driving-a-Robot-Ball-with-JavaScript: #{e.message}"
rescue => e
  puts "Unexpected error importing 22-04-2015-Driving-a-Robot-Ball-with-JavaScript: #{e.message}"
end
