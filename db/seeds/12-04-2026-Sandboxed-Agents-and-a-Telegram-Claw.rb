body = <<~MARKDOWN
  #__April 12, 2026__

  **_How we use [harness](https://github.com/capotej/harness) to put a sandboxed coding agent inside our veterinary monorepo and a Telegram-reachable claw on fly.io — without ever handing either of them our AWS credentials._**

  We have been running a coding agent on the Nala codebase for a few months now. Two of them, actually, in different shapes: one local that I shell into when I want an agent to chew on a refactor without seeing my `~/.aws`, and one running on fly.io that I can text from Telegram to ask "how many appointments did we book yesterday" or "fix the typo in the onboarding email and open a PR for it." Both of them are wrapped around the same project — [`harness`](https://github.com/capotej/harness), a portable Docker image that runs whatever open-source coding agent you point it at inside a capability-dropped container.

  This post is the engineering log for that integration, because I think the shape of it is interesting and because it took me a few weeks of iteration to land on something I am happy with.

  ## What harness actually is

  Harness is a small CLI (`npx @capotej/harness`) plus a few pre-built container images on `ghcr.io/capotej/harness`. The CLI is a thin adapter — about 600 lines of TypeScript — that does roughly one thing: figure out the right `docker run` invocation for whichever agent you asked for, with the right mounts, the right env file, and a sensible default security profile.

  The default invocation looks like this under the hood:

  ```bash
  docker run --rm -it \\
    --cap-drop=ALL --cap-add=NET_RAW \\
    --security-opt no-new-privileges:true \\
    --security-opt seccomp=block-af-alg.json \\
    -v "$PWD:/workspace" \\
    --env-file .env.harness \\
    ghcr.io/capotej/harness:1.6.4 \\
    pi -p "your prompt"
  ```

  The agent inside the container can see exactly what you mounted and exactly what env vars you passed in. It cannot see your SSH keys, your AWS credentials, your `~/.docker/config.json`, the cookies in your default browser profile, or your `.netrc`. It has no root, no new privileges, and a seccomp profile that blocks `AF_ALG` (the kernel crypto API surface that has been the source of half the recent container escapes).

  The agent under the hood is configurable: today we use `pi` for most coding work and `hermes` for the long-running claw. Either way, harness pulls the image from GHCR, verifies it with cosign on first run, and execs into it.

  ## Tier 1: `bin/agent`

  The first place harness shows up in our repo is a 40-line bash wrapper at `bin/agent` and a committed config:

  ```bash
  # .harness.config (committed)
  HARNESS_AGENT=pi
  HARNESS_MODEL=
  HARNESS_NO_VERIFY=false
  ```

  ```bash
  # .env.harness.example (committed; .env.harness is gitignored)
  # IMPORTANT: never put AWS / Stripe / Twilio / Devise / database creds in here.
  # The whole point of harness is that the agent only sees what is in this
  # file plus the mounted directory.
  ANTHROPIC_API_KEY=
  OPENROUTER_API_KEY=
  ```

  The wrapper handles three things vanilla `npx @capotej/harness` doesn't:

  1. Sources `.harness.config` so model and agent defaults are versioned with the repo.
  2. Defaults the env file to `.env.harness` so I don't have to remember to pass it.
  3. Adds a `--submodule <name>` flag that mounts only `hv-api/`, `hv-crm/`, etc., instead of the whole monorepo. That last part matters because Nala is a submodule-flavored monorepo and "mount only what you're working on" is a meaningful security boundary.

  Typical use:

  ```bash
  # one-shot, no session state on disk
  bin/agent -p "summarize the lead → appointment data flow"

  # only mount the crm submodule
  bin/agent --submodule hv-crm -p "refactor the schedule page header"

  # pick a model and an agent on the fly
  bin/agent -a hermes -m anthropic/claude-sonnet-4-5 -p "add a test"

  # interactive — state under .harness/<agent>/, gitignored
  bin/agent
  ```

  This has become my default for any task that fits the pattern "let an agent loose for a bit on something I don't fully trust." Best-of-N attempts on a worktree, exploring an unfamiliar dependency before I add it to the Gemfile, asking an agent to write codemods against the React codebase — all of these go through `bin/agent`.

  The honest tradeoff is that the sandbox really is a sandbox. `docker compose up` doesn't work inside it (no Docker-in-Docker), so any task that needs the full local stack still happens in my host Cursor session. That has not bothered me as much as I expected — the cleaner the split between "trusted host shell with all my creds" and "sandboxed agent shell with one LLM key and a directory," the less I worry about either of them.

  ## Tier 2: the claw on fly.io

  The second place harness shows up is more fun: a Hermes agent running 24/7 on fly.io, behind a Telegram bot, that I can text questions to and ask for small PRs from. We call it the Nala claw and it lives in `fly/nala-claw/` inside the monorepo.

  The deployment is interesting because it follows the [maintainer-endorsed "claw way"](https://github.com/capotej/harness/pull/27): you do not extend the harness image with your own Dockerfile. You take the upstream image as-is and inject your customizations through fly's `[[files]]` mechanism. The whole `fly.toml` is short enough to read in one breath:

  ```toml
  app = "nala-claw"
  primary_region = "iad"

  [build]
    image = "ghcr.io/capotej/harness:hermes-1.6.4"

  [processes]
    app = "hermes gateway"

  [[mounts]]
    source      = "nala_claw_data"
    destination = "/home/harness/.hermes-openrouter"

  [[files]]
    guest_path = "/etc/harness/hermes-defaults/openrouter/config.yaml"
    local_path = "config/config.yaml"

  [[files]]
    guest_path = "/etc/harness/hermes-defaults/openrouter/SOUL.md"
    local_path = "config/SOUL.md"

  [[files]]
    guest_path = "/etc/nala-claw/bin/crm"
    local_path = "bin/crm"
  ```

  There is no Dockerfile. There is no Hermes fork. There is no custom registry. Upstream releases a new `hermes-X.Y.Z` image, we bump one version number, redeploy, done. That is a lot of operational leverage for a piece of infrastructure that talks to production.

  ### What lives inside the claw

  Four small things, all bash wrappers, all mounted in via `[[files]]`:

  - **`bin/crm`** — a `curl` wrapper around `https://api.nala.vet/api/v1/crm/*` that signs requests with a bot JWT.
  - **`bin/tg`** — outbound Telegram messages, used for the daily briefing.
  - **`bin/brief`** — fetches `/crm/bot/briefing`, formats yesterday's KPIs, fires them through `bin/tg`.
  - **`bin/pr`** — commit, push, `gh pr create`, with hard rails.

  The rails on `bin/pr` are the part I am happiest with. It refuses to push to anything that looks like a shared branch:

  ```bash
  case "$BRANCH" in
    main|master|production|staging|HEAD)
      echo "[pr] refusing: '$BRANCH' is a protected/shared branch name."
      exit 1
      ;;
  esac
  ```

  Combined with GitHub branch protection on the Rails side and a Pundit policy on the API side that scopes the bot's writes to a deliberately small surface (no money, no PII edits, no role changes), the worst the claw can do is open a PR I will see in my inbox.

  ### What the bot can actually touch

  This is the part of the integration that lives in `hv-api/` rather than `fly/nala-claw/`, but it is the half that makes the rest safe:

  - A `bot@nala.vet` user with `role: :bot` (enum 5), seeded in `db/seeds.rb`.
  - A `bot:mint_token` rake task that produces a JWT signed by Devise.
  - A `Bot::Policy` Pundit policy that whitelists exactly the controllers and actions the bot is allowed to invoke.
  - An `[bot-audit]` log prefix on every authenticated request from the bot so Loki picks it up cleanly.

  The bot is, deliberately, less powerful than the most junior person on our team. It can read everything in the CRM and it can write to a small allowlist of soft fields (appointment notes, lead status). It cannot refund a customer, change a permission, or touch payouts. If we ever want it to do more, the policy gets the change, not the bot.

  ## The rough edges, honestly

  Because this is the kind of integration post I would have wanted to read six months ago, here are the parts that took me longer than I expected:

  1. **`config.yaml` is mutable runtime state.** Hermes treats its own config as something it can rewrite at runtime when you tweak settings in the TUI. Fly `[[files]]` writes the file at deploy time, but the volume's copy is what wins after that. Our deploy script force-copies `config.yaml` and `SOUL.md` over the volume on every deploy and then SIGTERMs the gateway PID. That is intentional but very surprising the first time.
  2. **No `pkill` in the harness image.** The deploy script reads `gateway.pid` and `kill -TERM` directly. I would have liked `pkill -f hermes` to "just work," but the image is intentionally minimal.
  3. **Fly `[[files]]` writes with mode `0644`.** The `bin/crm`/`bin/tg`/etc. wrappers cannot just be called by name; SOUL.md tells the agent to invoke them as `bash /etc/nala-claw/bin/crm …`. Once I learned that I stopped fighting it.
  4. **cosign is required.** First local run on a new machine needs `brew install cosign` so harness can verify the image signature. There is a `HARNESS_NO_VERIFY=true` escape hatch but I would rather have the signature check.
  5. **The seed race on SOUL.md.** Hermes writes a generic default `SOUL.md` on first boot. The upstream entrypoint copies our customized version with `cp -rn` (which means "don't clobber"), so on a brand-new volume our version loses the race. The deploy script's force-copy is what fixes it; this is documented in our README and should probably be a PR upstream at some point.

  ## What I'd tell the next person

  A few takeaways I have written down to refer to later:

  1. **Treat the agent's sandbox boundary as an architectural decision, not a config detail.** Once you draw the line at "the agent gets a mounted directory and one LLM key," a lot of paranoia evaporates and you can move faster. We have been able to ship `bin/agent` to the whole team without anyone worrying about supply-chain attacks against an unfamiliar gem.
  2. **Server-side authority is the right place to put the rails.** The fact that the bot has a `role`, a JWT, a Pundit policy, and an audit log prefix is what makes me comfortable letting it write to anything at all. Without that, no amount of clever prompt engineering on the agent side would make this safe.
  3. **Consume the upstream image; do not fork it.** The claw is a single fly.toml plus four bash wrappers and two YAML files. Every time I have wanted to add a feature, the answer has been "mount another file," not "rebuild an image." That has kept our operational burden basically flat.
  4. **A claw fails open.** If fly is down or OpenRouter is in a bad mood, the CRM keeps running and appointments keep getting booked. The claw is additive — daily briefings, ad-hoc questions, the occasional PR — never load-bearing. Anything that needs to actually keep the lights on should not depend on it.

  Total operational cost for the claw is about $15–55/month depending on how much we talk to it. Total time-to-first-PR-from-Telegram was about four hours, most of which was spent on the Pundit policy, not on harness. That ratio is the part I keep coming back to: the agent infrastructure is genuinely a one-evening problem now. The interesting work is everything around it.

  More posts coming as we layer on the next tier (a CI-side review claw is the obvious next thing). If you are running harness against anything weird, send me a note — I would love to see what other shapes this is taking.
MARKDOWN

begin
  Post.create!(
    title: "Sandboxed Coding Agents and a Telegram Claw on a Veterinary Monorepo",
    created_at: "April 12, 2026",
    markdown_body: body,
    markdown_excerpt: "How we use harness to put a sandboxed coding agent inside our veterinary monorepo and a Telegram-reachable claw on fly.io — without ever handing either of them our AWS credentials.",
    post_tags: "ai-agents,harness,docker,fly-io,security,hermes,rails,nala"
  )
  puts "Imported Sandboxed Coding Agents and a Telegram Claw on a Veterinary Monorepo"
rescue ActiveRecord::RecordInvalid => e
  puts "Error importing 12-04-2026-Sandboxed-Agents-and-a-Telegram-Claw: #{e.message}"
rescue => e
  puts "Unexpected error importing 12-04-2026-Sandboxed-Agents-and-a-Telegram-Claw: #{e.message}"
end
