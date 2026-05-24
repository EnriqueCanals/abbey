body = <<~MARKDOWN
  #__May 23, 2026__

  **_How I wired a Telegram-driven [Hermes](https://github.com/NousResearch/hermes-agent) claw on AWS to maintain this blog. Built on [harness](https://github.com/capotej/harness), routed through Tailscale, and writing posts via `kamal app exec` straight into the live Rails container — including the one you are reading right now._**

  Six weeks ago I [wrote about](/blog/2026/04/12/sandboxed-coding-agents-and-a-telegram-claw-on-a-veterinary-monorepo) the Nala Claw — a Hermes agent on fly.io that I text from Telegram to read CRM metrics and open PRs against our veterinary monorepo. That post ended with a hand-wave: "I would love a second claw, one that runs this blog." Tonight I built it. It is called **HomuncuCLAW**, it lives on a $13/mo EC2 instance, and it published this post.

  The shape of it is interesting because it is the same base ingredients as the Nala claw — `ghcr.io/capotej/harness:hermes-1.6.4` running `hermes gateway`, Telegram long-poll, OpenRouter for the model, a `SOUL.md` for the persona — but the deployment target is AWS instead of fly.io, the workload is an opinionated Rails 8 blog instead of a complex Rails API, and the production hop is `kamal app exec` instead of an HTTP bot API. That swap turned out to surface a different set of sharp edges, which is what this post is actually about.

  ## Why a claw for the blog

  Abbey runs on Kamal on a tiny EC2 with SQLite on an EBS volume. Publishing is a one-liner inside the container: `Post.create!(title:, markdown_body:, post_tags:, draft: false)`. Editing is `Post.find_by(slug:).update!(markdown_body:)`. Promoting a draft is `update!(draft: false)`. All of it works fine from `bin/kamal app exec --reuse "bin/rails console"` on my laptop — but my laptop is not always open and I am not always at a keyboard.

  What I actually want, sitting on a couch with a phone, is to text "publish that draft about agents" or "what posts went up this month" and get a useful answer. That is a small enough surface area to model precisely, and big enough that scripting it without an LLM in the middle gets tedious. A claw is the right shape: the agent reads my intent, picks the right tool, runs it, and reports back. No webhooks, no UI, no app to maintain.

  ## Why AWS, not fly.io

  Nala runs on fly.io because Nala itself runs on fly. HomuncuCLAW runs on AWS because this blog runs on AWS, and I wanted the claw on the same network surface as the thing it manages. The connection model is symmetric — the claw lives in my Tailnet, the blog lives in my Tailnet, the claw `ssh root@<blog-tailnet-fqdn>` and runs `docker exec` against the abbey container. No public bot API, no extra firewall holes, no IAM ping-pong. The blog already has all the deploy machinery; the claw is just a second tenant on the same private network.

  The harness project has [a draft AWS deploy guide](https://github.com/capotej/harness/blob/docs/deploy-to-aws/docs/deploying-to-aws.md) (PR #_pending_) covering both ECS Fargate + EFS and a small EC2 + Docker + systemd. HomuncuCLAW took the EC2 path because it is what the docs call "hobbyist" and what I actually wanted: a `t4g.small`, a `cloud-init.yml`, a systemd unit, an EBS volume. ~$13/mo, no managed-service indirection, one box I can SSH to.

  ## Architecture

  ```
  Telegram  ──►  HomuncuCLAW EC2 (t4g.small, $13/mo)
                 • cloud-init: docker, tailscale, systemd
                 • systemd unit runs the harness hermes image
                 • hermes gateway long-polls Telegram
                 • SOUL.md gives the agent its persona
                 • /etc/homuncuclaw/bin/* are shell wrappers
                                │
                                │ ssh root@<blog-tailnet-fqdn>
                                ▼
                 abbey EC2 (running enriquecanals.com)
                                │
                                │ docker exec abbey-web-<sha>
                                ▼
                 bin/rails runner -  (full Post / Page / Tag API)
  ```

  The entire claw repo is fifteen files and ~1,400 lines. The agent itself is one container, one `hermes gateway` process, mounted volumes for state and tool wrappers, and the same OpenRouter key I use for Nala. The only thing I had to actually design was the bridge to the blog — `bin/blog`, a 40-line bash wrapper that pipes Ruby on stdin to the live Rails runner via SSH and `docker exec`.

  ```bash
  # bin/blog (lives at /etc/homuncuclaw/bin/blog inside the container)
  remote_cmd="$(cat <<REMOTE
  container="\\$(docker ps \\
    --filter 'label=service=abbey' \\
    --filter 'label=role=web' \\
    --filter 'status=running' \\
    --format '{{.Names}}' | head -n1)"
  docker exec -i "\\$container" bin/rails runner -
  REMOTE
  )"

  ssh root@"$ABBEY_SSH_HOST" "$remote_cmd" <<< "$ruby_code"
  ```

  Resolving the container by Kamal label rather than hard-coded name means it survives deploys — Kamal rotates container names with each version tag, but the labels stay. No need to teach the bot what release SHA is live.

  ## What the agent has

  | Tool | What it does |
  | --- | --- |
  | `bin/blog '<ruby>'` | Pipes Ruby to `bin/rails runner -` in the live abbey container. Primary CRUD path. |
  | `bin/status` | HTTP sweep of public pages, container snapshot, post / page / tag counts. |
  | `bin/deploy` | `kamal deploy` from `~/workspace/abbey`. Behind a `YES, DEPLOY` literal confirmation. |
  | `bin/pr` | `git add` + `commit` + `push` to a feature branch + `gh pr create`. Hard rails: no `main`/`ec-blog` direct, no force-push, 2k-line diff cap. |
  | `bin/tg` | Outbound `sendMessage` for proactive replies. |

  Persona lives in `SOUL.md` (the system-prompt slot Hermes loads first). It tells the agent it manages enriquecanals.com, points at the tool wrappers, and codifies confirmation rails: literal `YES` for publishing, `YES, DEPLOY` for shipping code, `YES, DESTROY` for anything that deletes a record. That style is a direct lift from the Nala SOUL — "your bot will never destroy something you did not explicitly tell it to destroy" is the only design rule I am dogmatic about.

  ## Three things that bit me

  This is the part that was actually interesting, not the happy-path build.

  ### 1. Tailscale SSH `requires an additional check`

  My abbey EC2 runs `tailscale up --ssh`, which means inbound SSH gets gated by Tailscale's policy engine. Browser-driven for interactive humans, fine. **Headless for a bot, broken**:

  ```
  # Tailscale SSH requires an additional check.
  # To authenticate, visit: https://login.tailscale.com/a/l11305c935f6bc
  Connection to 100.89.90.124 port 22 timed out
  ```

  The fix is one ACL rule and two machine tags. Tag the abbey EC2 `tag:abbey`, tag the claw EC2 `tag:claw`, and add:

  ```jsonc
  "ssh": [
    { "action": "accept", "src": ["tag:claw"], "dst": ["tag:abbey"], "users": ["root"] }
  ]
  ```

  Worth noting: the moment you add any `ssh:` block, Tailscale's default "owner can SSH to own devices" rule disappears entirely. So you also need a second rule for yourself — `autogroup:admin` → `tag:claw`, `users: ["ubuntu", "root"]` — or you lock yourself out of the host you just provisioned.

  ### 2. Cloud-init bootstrap chicken-and-egg

  The first version of my launch script was naive: `aws ec2 run-instances --user-data file://cloud-init.yml`, then `scripts/deploy.sh` ships `/etc/homuncuclaw.env` (with the `TAILSCALE_AUTH_KEY` in it) over Tailscale SSH. Except `scripts/deploy.sh` needs Tailscale SSH, which needs the env file, which needs the deploy script. Egg-meets-chicken.

  Fix: template the local `.env` into the `cloud-init.yml` `write_files:` block at launch time, before sending it to `aws ec2`. Then first boot has `/etc/homuncuclaw.env` already in place, `tailscale up --authkey=$TAILSCALE_AUTH_KEY` runs in the cloud-init `runcmd`, the host joins my tailnet, and `scripts/deploy.sh` can take it from there to ship `bin/`, the SSH key, and the hermes defaults.

  A real fix, not a workaround: it means the launch script is the single source of truth for "the secrets the host knows on its first second of life," which is the correct boundary.

  ### 3. Small papercuts that add up

  Two more bites that cost me ten minutes each:

  - **`awscli` is gone from Ubuntu 24.04's repos.** Canonical pushed everyone to snap. Cloud-init's `packages:` install batch failed atomically on the first run because of one missing package. I removed it (we do not actually need it on the claw host — the harness image has its own toolchain) and the rest of the apt install succeeded.
  - **MarkdownV2 in `bin/tg` is unforgiving.** My very first proactive `tg` message contained a literal `-` and the Telegram API rejected the whole send: `Bad Request: can't parse entities: Character '-' is reserved and must be escaped`. Solution: default `bin/tg` to plain text (no `parse_mode`), make Markdown/HTML opt-in via `TG_PARSE_MODE=`. Safer for an agent that is going to construct strings with dashes, dots, exclamation marks, and parens — i.e. always.

  ## The meta moment

  This post was written by me in a regular editor, then handed to HomuncuCLAW from my laptop, which texted my bot, which executed a `Post.create!` inside the live abbey container, which wrote a row into SQLite on an EBS volume, which Rails will render the next time anyone hits this URL. The bot replied to me with the slug and the public URL. From a Telegram chat on my phone, the round-trip — agent thought → SSH → docker exec → Rails runner → SQLite → bot reply → tap link → live page — takes under five seconds.

  The way I have been describing this to myself today is: I bought the cheapest viable EC2, dropped a signed container on it, and now I have a hand-on-keyboard equivalent in my pocket that knows exactly one job. That feels like the right size for an agent.

  ## The repo

  The HomuncuCLAW repo is sitting in a private GitHub repo for now while I sand the rough edges. It is fifteen files: a `cloud-init.yml`, a systemd unit, five bash tools, a `SOUL.md`, a `config.yaml`, a `launch-instance.sh`, a `deploy.sh`, and a `RUNBOOK.md`. If you have a Kamal-deployed Rails app on AWS and want a Telegram claw for it, the bones should transplant pretty cleanly — swap the persona, swap the tool wrappers, keep the deploy shape. Happy to share the source if you ping me.

  Next on the list: a scheduled morning digest (post counts, draft queue, last deploy SHA — same pattern as the Nala briefing) and a `bin/draft` tool that accepts a markdown file path and turns it into a draft Post in one shot. Both fit in `SOUL.md` and an extra cron entry; both are small. Most of the work, as always, is already done.
MARKDOWN

excerpt = <<~MARKDOWN
  How I built HomuncuCLAW — a Telegram-driven Hermes coding agent on AWS — that maintains this blog. SSH over Tailscale, kamal app exec into the Rails container, and a few sharp edges worth writing down.
MARKDOWN

Post.create!(
  title:            "HomuncuCLAW: A Telegram Coding Agent on AWS for This Blog",
  markdown_body:    body,
  markdown_excerpt: excerpt,
  post_tags:        "agents,harness,homuncuclaw,telegram,aws,tailscale,kamal,hermes,ai-agents,claw",
  draft:            false,
  created_at:       Time.zone.local(2026, 5, 23, 23, 35)
)
